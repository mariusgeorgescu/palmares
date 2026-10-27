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
import Data.Array (length, null, take)
import Data.Const (Const)
import Data.Either (either)
import Data.Maybe (Maybe(..), maybe)
import Format (enumLabel, formatDay, humanize, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Route (Route)
import Route.GovQueries
  ( attestationListHrefFor
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
    H.modify_ _ { about = either Failure Success a }
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

  -- Linia care poarta promisiunea produsului: controlul e DOVEDIT prin semnatura, nu declarat.
  -- Un profil fara credentiala nu e incomplet, si propozitia o spune. `credentialIsScript`
  -- lipseste cind nu se stie, si atunci nu se afirma nici cheie, nici script.
  credentialLine r = case r.credential of
    Nothing ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        [ HH.text "Claims no on-chain governance credential." ]
    Just c ->
      HH.p [ HP.class_ (HH.ClassName "text-sm") ]
        [ HH.text "Proved control of "
        , HH.a [ HP.href (drepDetailHrefFor c), HP.class_ (HH.ClassName "link link-hover font-mono") ]
            [ HH.text (shortId c) ]
        , OnchainId.chip { value: c, kind: OnchainId.DRep, explorerBase: AppEnv.explorerBase }
        , HH.text
            ( case r.credentialIsScript of
                Just true -> " — a script credential, proved the same way a key is."
                Just false -> " — a key credential."
                Nothing -> "."
            )
        , HH.text (maybe "" (\n -> " " <> pluralize n "claimant" <> " in all.") r.claimantCount)
        ]

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
          [ HP.href (attestationListHrefFor (emptyRegistryFilters { subject = Just a.subject }))
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
