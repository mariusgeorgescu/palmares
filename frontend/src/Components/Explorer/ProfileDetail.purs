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
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getAttestations, getProfile)
import Capabilities.Query.Gov.Types (AttestationPage(..), AttestationRow(..), ProfileRow(..))
import Components.Shared.DRepIdentity (shortId)
import Components.Shared.Remote as Remote
import Components.Shared.Refresh (subscribeRefresh)
import Components.Shared.OnchainId as OnchainId
import Data.Array (filter, length, null, take)
import Data.Const (Const)
import Data.Either (either)
import Data.Maybe (Maybe(..), isJust, maybe)
import Data.String (Pattern(..), stripPrefix)
import Format (enumLabel, imageRef, formatDay, humanize, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Halogen.Store.Monad (class MonadStore, emitSelected, getStore)
import Halogen.Store.Select (selectAll)
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
import Store as Store
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
  -- Identitatea activă, oglindită din `Store`. Pagina trebuie să știe dacă profilul ăsta e AL TĂU:
  -- altfel oferă un buton care duce la un refuz garantat — regula `Mr` interzice auto-girarea, iar
  -- refuzul vine după ce ai semnat.
  , mine :: Maybe String
  , ownedCount :: Int
  }

data Action
  = Initialize
  | StoreChanged Store.Store
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

-- | Id-ul identității active, dacă există una.
activeId :: Store.Store -> Maybe String
activeId store = map (\(ProfileRow r) -> r.id) store.active

-- | Cîte profiluri deține portofelul. Contează pentru mesaj: cu mai multe, auto-girarea se rezolvă
-- | comutînd identitatea; cu unul singur, nu se rezolvă deloc.
ownedCount' :: Store.Store -> Int
ownedCount' store = case store.owned of
  Success rows -> length rows
  _ -> 0

component
  :: forall q m
   . MonadQueryGov m
  => MonadStore Store.Action Store.Store m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \profileId ->
        { profileId, profile: NotAsked, about: NotAsked, by: NotAsked, mine: Nothing, ownedCount: 0 }
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
    Initialize -> do
      -- O scriere confirmată schimbă ce arată ecranul ăsta, iar proiecția vine ~45s după
      -- tranzacție — deci nu se poate încărca o dată și gata.
      subscribeRefresh Retry
      store <- getStore
      H.modify_ _ { mine = activeId store, ownedCount = ownedCount' store }
      emitter <- emitSelected selectAll
      void (H.subscribe (StoreChanged <$> emitter))
      void (H.fork load)
    StoreChanged store ->
      H.modify_ _ { mine = activeId store, ownedCount = ownedCount' store }
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

  failure msg e = Remote.errorCard msg e Retry

  header st (ProfileRow r) =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text r.name ]
          , HH.span [ HP.class_ (HH.ClassName "badge badge-outline") ] [ HH.text (enumLabel r.kind) ]
          -- Că e al tău se vede, fiindcă schimbă ce poți face aici.
          , if st.mine == Just st.profileId then
              HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-primary") ] [ HH.text "this is you" ]
            else HH.text ""
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
      , imageLine r
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-3 pt-1") ]
          [ vouchAction st
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

  -- Girarea, sau motivul pentru care n-are rost.
  --
  -- Regula `Mr` a validatorului interzice auto-girarea: subiectul și emitentul nu pot fi același
  -- profil. Pînă acum butonul se oferea oricum, iar refuzul venea DUPĂ ce omul completase
  -- formularul și semnase — exact drumul închis pe care traducerea refuzurilor îl făcea lizibil,
  -- în loc să-l prevină. Cu o identitate a sesiunii se poate preveni.
  vouchAction st =
    if st.mine == Just st.profileId then
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        [ HH.text
            ( if st.ownedCount > 1 then
                "This is the profile you are acting as, and nobody can vouch for themselves — the \
                \chain refuses it. Switch identity with the avatar in the top bar to vouch for it."
              else
                "This is your profile, and nobody can vouch for themselves — the chain refuses it. \
                \Someone else's vouch is what counts here."
            )
        ]
    else
      HH.a
        [ HP.href (writeHrefFor { flow: Just "issue-attestation", subject: Just st.profileId })
        , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
        ]
        [ HH.text "Vouch for this profile" ]

  -- Imaginea profilului, ca ADRESĂ și nu ca imagine. Motivul întreg e la `Format.imageRef`: n-avem
  -- poartă IPFS, iar încărcarea directă de pe gazda altcuiva ar trimite IP-ul vizitatorului acolo
  -- la fiecare rînd. Pînă acum cîmpul nu se vedea nicăieri, deși e obligatoriu și costă min-ADA în
  -- fiecare datum — deci nici nu se putea observa că registrul e plin de adrese care nu duc nicăieri.
  imageLine r = case imageRef r.imageUri of
    Nothing -> HH.text ""
    Just img ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        ( [ HH.text "Image: " ]
            <> case img.href of
              Just href ->
                [ HH.a
                    [ HP.href href
                    , HP.target "_blank"
                    , HP.rel "noopener noreferrer"
                    , HP.class_ (HH.ClassName "link link-hover font-mono break-all")
                    ]
                    [ HH.text img.shown ]
                ]
              Nothing -> [ HH.span [ HP.class_ (HH.ClassName "font-mono break-all") ] [ HH.text img.shown ] ]
            <> [ HH.text (" " <> img.note) ]
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
