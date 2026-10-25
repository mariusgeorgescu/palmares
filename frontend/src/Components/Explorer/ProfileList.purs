-- | Registrul de profiluri: `GET /profiles`.
-- |
-- | Un profil e un TOKEN, nu un rînd într-o bază: `id` e o clasă de activ (`policy.assetName`), și
-- | cine deține tokenul deține profilul. De-aia ecranul arată identificatorul întreg și nu-l
-- | ascunde într-un link — e lucrul pe care îl verifici pe lanț.
-- |
-- | `credential` leagă profilul de o identitate de guvernanță și lipsește la jumătate din
-- | profilurile măsurate. Asta nu e un profil incomplet: e un profil care nu pretinde nimic
-- | despre cine e pe lanț, ceea ce e o stare validă și e scrisă ca atare.
module Components.Explorer.ProfileList
  ( Slot
  , Output
  , _profileList
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getProfiles)
import Capabilities.Query.Gov.Types (ProfilePage(..), ProfileRow(..))
import Components.Shared.DRepIdentity (shortId)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Format (formatInt, humanize, matchLine, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries (RegistryFilters, drepDetailHrefFor, profileListHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_profileList :: Proxy "profileList"
_profileList = Proxy

type Input = RegistryFilters

type State =
  { filters :: RegistryFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError ProfilePage
  }

data Action
  = Initialize
  | Retry
  | Receive Input

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, page: NotAsked, refreshing: false }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  handleAction = case _ of
    Initialize -> load
    Retry -> load
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters }
        load

  load = do
    st <- H.get
    H.modify_ \s0 -> case s0.page of
      Success _ -> s0 { refreshing = true }
      _ -> s0 { page = Loading }
    res <- getProfiles st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Profiles" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "Identities in the attestation registry. A profile is a token: whoever holds it \
                  \holds the profile, and a profile may or may not claim a governance credential."
              ]
          ]
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading profiles…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The profiles could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(ProfilePage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "profile")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState else cards p.items
      , if null p.items then HH.text "" else pager st page
      ]

  emptyState =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "No profiles have been registered yet." ] ]
      ]

  -- Carduri, nu tabel: descrierea e text liber de lungime necontrolată, iar într-o coloană ar
  -- împinge totul la dreapta sau s-ar tăia exact unde începe informația.
  cards items =
    HH.div [ HP.class_ (HH.ClassName "grid gap-3 md:grid-cols-2") ] (map card items)

  card (ProfileRow r) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
          [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
              [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-base") ] [ HH.text r.name ]
              , HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ] [ HH.text (humanize r.kind) ]
              ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-80") ] [ HH.text r.description ]
          , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 break-all"), HP.title r.id ]
              [ HH.text r.id ]
          , credentialLine r
          ]
      ]

  -- Un profil fără credențial nu e incomplet, și propoziția o spune. Cînd există, duce la pagina
  -- DRep-ului — singura identitate de guvernanță care are una în produs.
  credentialLine r = case r.credential of
    Nothing ->
      HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
        [ HH.text "Claims no on-chain governance credential." ]
    Just c ->
      HH.p [ HP.class_ (HH.ClassName "text-xs") ]
        [ HH.text "Claims "
        , HH.a [ HP.href (drepDetailHrefFor c), HP.class_ (HH.ClassName "link link-hover font-mono") ]
            [ HH.text (shortId c) ]
        , HH.text
            ( if r.credentialIsScript == Just true then " (a script credential)"
              else " (a key credential)"
            )
        , HH.text (maybe "" (\n -> " · " <> pluralize n "claimant") r.claimantCount)
        ]

  pager st (ProfilePage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = profileListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
        [ pagerLink prev hrefFor "Previous"
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text (formatInt p.total <> " in total") ]
        , pagerLink next hrefFor "Next"
        ]

  pagerLink target hrefFor label = case target of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off -> HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]
