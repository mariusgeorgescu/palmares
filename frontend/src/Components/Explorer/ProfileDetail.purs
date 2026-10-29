-- | Pagina unui singur profil: `GET /profiles/{id}` plus palmaresul lui.
-- |
-- | De ce exista. Pina acum registrul avea doar liste, iar palmaresul unei identitati — teza
-- | produsului, „the on-chain record of governance conduct" — nu se vedea nicaieri per persoana.
-- | Rindurile din lista arata id-uri trunchiate cu elipsa, deci ca sa afli ce s-a afirmat despre
-- | cineva trebuia sa copiezi un identificator de saizeci de caractere si sa filtrezi de mina.
-- |
-- | Palmaresul are DOUA jumatati, si asta e decizia care conteaza aici: ce spun altii DESPRE
-- | profil, si pentru ce gireaza EL. Ruta dedicata `/profiles/{id}/attestations` da doar prima —
-- | masurat pe preprod: 4 rinduri, identic cu `?subject=`, in timp ce `?issuer=` da 1. Deci nu o
-- | folosim: doua cereri pe lista existenta spun mai mult decit una pe o ruta speciala, si nu cer
-- | nici tip nou, nici decodor nou.
module Components.Explorer.ProfileDetail
  ( Slot
  , Output
  , _profileDetail
  , component
  ) where

import Prelude

import AppEnv as AppEnv
import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getAttestations, getProfile)
import Capabilities.Query.Gov.Types (AttestationPage(..), AttestationRow(..), ProfileRow(..))
import Components.Shared.DRepIdentity (shortId)
import Components.Shared.OnchainId as OnchainId
import Data.Array (filter, length, null, take)
import Data.Const (Const)
import Data.Either (either)
import Data.Maybe (Maybe(..), isJust, maybe)
import Data.String (Pattern(..), stripPrefix)
import Format (enumLabel, formatDay, humanize, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Route (Route)
import Route.GovQueries
  ( attestationDetailHrefFor
  , drepDetailHrefFor
  , emptyRegistryFilters
  , vouchesAboutHrefFor
  , vouchesByHrefFor
  , writeHrefFor
  )
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_profileDetail :: Proxy "profileDetail"
_profileDetail = Proxy

type Input = String

type State =
  { profileId :: String
  , profile :: RemoteData ApiError ProfileRow
  , about :: RemoteData ApiError AttestationPage
  , by :: RemoteData ApiError AttestationPage
  }

data Action
  = Initialize
  | Retry
  | Receive Input

-- | Cite rinduri se arata din fiecare jumatate inainte de „see all". Opt, nu toate: pagina asta
-- | e un rezumat cu doua liste, iar o lista intreaga aici ar fi acelasi ecran de doua ori.
shown :: Int
shown = 8

-- | Dacă credențiala e a unui DRep, citit din prefixul CIP-129.
-- |
-- | Rolul e în prefix: `drep1…` pentru un DRep, `cc_cold1…`/`cc_hot1…` pentru o cheie de comitet,
-- | revendicabilă de la ADR 0006. `drepDetailHrefFor` e o simplă concatenare, deci fără verificarea
-- | asta o cheie de comitet ajungea la `/dreps/cc_cold1…` — pagina de DRep a ceva care nu e DRep.
isDRepCredential :: String -> Boolean
isDRepCredential c = isJust (stripPrefix (Pattern "drep1") c)

-- | Scoate din palmares rîndurile pe care profilul și le-a emis singur.
-- |
-- | O revendicare de credențială are `subject == issuer` (regula `Mc1`, iar `Mr` scutește exact
-- | felurile de credențială), deci apare în AMBELE jumătăți. În cea despre el contrazice textul de
-- | sub titlu — „claims made by someone else" — și nu pierdem nimic scoțînd-o, fiindcă credențiala
-- | are linia ei dedicată mai sus pe pagină. Se scade și din `total`, altfel „See all N" ar număra
-- | alte rînduri decît cele de deasupra lui.
dropSelfIssued :: String -> AttestationPage -> AttestationPage
dropSelfIssued pid (AttestationPage p) =
  AttestationPage (p { items = kept, total = p.total - (length p.items - length kept) })
  where
  kept = filter (\(AttestationRow a) -> a.issuer /= pid) p.items

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \profileId ->
        { profileId, profile: NotAsked, about: NotAsked, by: NotAsked }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  -- `H.fork` pentru acelasi motiv ca in liste: initializatorul copilului tine deschisa
  -- initializarea PARINTELUI, iar parintele pune titlul documentului.
  handleAction = case _ of
    Initialize -> void (H.fork load)
    Retry -> load
    Receive pid -> do
      st <- H.get
      when (pid /= st.profileId) do
        H.modify_ _ { profileId = pid }
        load

  load = do
    st <- H.get
    H.modify_ _ { profile = Loading, about = Loading, by = Loading }
    p <- getProfile st.profileId
    H.modify_ _ { profile = either Failure Success p }
    -- Cele doua jumatati, in doua cereri. `Data.Either.either`, nu un ajutor local: unul definit
    -- in `where` se monomorfizeaza la prima folosire, deci a doua cerere nu mai compila.
    a <- getAttestations (emptyRegistryFilters { subject = Just st.profileId })
    -- Filtrul se aplică la sosire, nu la randare: așa `total`-ul pe care îl vede omul în „See all N"
    -- e cel al rîndurilor rămase, iar funcția de randare rămîne aceeași pentru ambele jumătăți.
    H.modify_ _ { about = either Failure Success (map (dropSelfIssued st.profileId) a) }
    b <- getAttestations (emptyRegistryFilters { issuer = Just st.profileId })
    H.modify_ _ { by = either Failure Success b }

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
      [ case st.profile of
          NotAsked -> loading "Loading the profile…"
          Loading -> loading "Loading the profile…"
          Failure e -> failure "The profile could not be loaded." e
          Success r -> header st r
      , section "What others state about this profile"
          "Claims made by someone else, and whether this profile countersigned them."
          (vouchesAboutHrefFor st.profileId)
          st.about
      , section "What this profile vouches for"
          "Claims this profile made about others. A vouch is a signed opinion, not a finding of fact."
          (vouchesByHrefFor st.profileId)
          st.by
      ]

  loading msg =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text msg ]
          ]
      ]

  failure msg e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text msg ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  header st (ProfileRow r) =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text r.name ]
          , HH.span [ HP.class_ (HH.ClassName "badge badge-outline") ] [ HH.text (enumLabel r.kind) ]
          ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ] [ HH.text r.description ]
      , HH.div [ HP.class_ (HH.ClassName "opacity-70") ]
          [ OnchainId.withChip
              { value: r.id
              , shown: shortId r.id
              , kind: OnchainId.Asset
              , explorerBase: AppEnv.explorerBase
              }
          ]
      , credentialLine r
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-3 pt-1") ]
          [ HH.a
              [ HP.href (writeHrefFor { flow: Just "issue-attestation", subject: Just st.profileId })
              , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
              ]
              [ HH.text "Vouch for this profile" ]
          , HH.a
              [ HP.href (writeHrefFor { flow: Just "update-profile", subject: Just st.profileId })
              , HP.class_ (HH.ClassName "link link-hover text-sm self-center")
              ]
              [ HH.text "Edit" ]
          , HH.a
              [ HP.href (writeHrefFor { flow: Just "claim-credential", subject: Just st.profileId })
              , HP.class_ (HH.ClassName "link link-hover text-sm self-center")
              ]
              [ HH.text "Claim a credential" ]
          ]
      ]

  -- Linia care poartă promisiunea produsului: controlul e DOVEDIT, nu declarat. Dar NU la fel de
  -- tare în cele două cazuri, și de aceea propoziția spune ce a cerut validatorul în fiecare: pentru
  -- o cheie, o semnătură pe tranzacția care revendică; pentru un script, doar că tranzacția a
  -- cheltuit de la adresa scriptului — ce poate face un singur membru al unui multisig 1-din-N
  -- (ADR 0003). Un profil fără credențială nu e incomplet, și propoziția o spune. `credentialIsScript`
  -- lipsește cînd nu se știe, și atunci nu se afirmă nici cheie, nici script.
  credentialLine r = case r.credential of
    Nothing ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        [ HH.text "Claims no on-chain governance credential." ]
    Just c ->
      HH.p [ HP.class_ (HH.ClassName "text-sm") ]
        ( [ HH.text "Proved control of " ]
            <> credentialIdent c
            <>
              [ HH.text
                  ( case r.credentialIsScript of
                      Just true ->
                        " — a script credential: the proof is only that the claiming transaction spent \
                        \an output at the script's address, which one member of a 1-of-N multisig can do."
                      Just false -> " — a key credential: the claiming transaction carries its signature."
                      Nothing -> "."
                  )
              , HH.text (maybe "" (\n -> " " <> pluralize n "claimant" <> " in all.") r.claimantCount)
              ]
        )

  -- Link doar cînd rolul din prefix are unde să ducă. Registrul n-are pagină de membru de comitet,
  -- iar nici chipul nu apare atunci: `IdKind` n-are valoare de comitet, iar `DRep` ar trimite
  -- explorerul la `/drep/cc_cold1…` — tot o pagină greșită, doar în altă parte.
  credentialIdent c =
    if isDRepCredential c then
      [ HH.a [ HP.href (drepDetailHrefFor c), HP.class_ (HH.ClassName "link link-hover font-mono") ]
          [ HH.text (shortId c) ]
      , OnchainId.chip { value: c, kind: OnchainId.DRep, explorerBase: AppEnv.explorerBase }
      ]
    else [ HH.span [ HP.class_ (HH.ClassName "font-mono") ] [ HH.text (shortId c) ] ]

  section title blurb allHref rd =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text title ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text blurb ]
          , case rd of
              NotAsked -> HH.text ""
              Loading -> HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-sm") ] []
              Failure e -> failure "These could not be loaded." e
              Success (AttestationPage p) ->
                if null p.items then
                  HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text "Nothing here yet." ]
                else
                  HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
                    [ HH.ul [ HP.class_ (HH.ClassName "space-y-1") ]
                        (map row (take shown p.items))
                    , HH.a [ HP.href allHref, HP.class_ (HH.ClassName "link link-hover text-sm") ]
                        [ HH.text
                            ( if p.total > length (take shown p.items) then
                                "See all " <> pluralize p.total "vouch"
                              else "See these in the register"
                            )
                        ]
                    ]
          ]
      ]

  row (AttestationRow a) =
    HH.li [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2 text-sm") ]
      [ HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-ghost") ] [ HH.text (humanize a.kind) ]
      , HH.a
          -- Rîndul duce la vouch-ul ÎNSUȘI, nu la lista filtrată pe subiectul lui: pe un rînd din
          -- palmares, lucrul pe care vrei să-l deschizi e documentul, nu o altă listă.
          [ HP.href (attestationDetailHrefFor a.id)
          , HP.class_ (HH.ClassName "link link-hover font-medium")
          ]
          [ HH.text a.name ]
      , HH.span
          [ HP.class_
              (HH.ClassName ("badge badge-sm " <> if a.accepted then "badge-success" else "badge-outline"))
          ]
          [ HH.text (if a.accepted then "accepted" else "not yet") ]
      , if a.openDisputeCount > 0 then
          HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-warning") ]
            [ HH.text (pluralize a.openDisputeCount "open challenge") ]
        else HH.text ""
      , HH.span [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text (formatDay a.date) ]
      ]
