-- | Atestările: `GET /attestations`.
-- |
-- | O atestare e o afirmație a cuiva (`issuer`) despre altcineva (`subject`). Ecranul ține trei
-- | stări SEPARATE, pentru că înseamnă lucruri diferite și confundarea lor ar fi exact greșeala
-- | pe care un registru de reputație n-are voie s-o facă:
-- |
-- |   * __acceptată sau nu__ — e alegerea SUBIECTULUI. O atestare neacceptată e afirmată, nu
-- |     recunoscută, și asta nu spune nimic despre adevărul ei;
-- |   * __contestată__ — cineva a deschis o dispută și a pus un depozit la bătaie;
-- |   * __confirmată în dispută__ (`upheld`) — disputa s-a judecat și a căzut împotriva atestării.
-- |
-- | O atestare poate fi acceptată și contestată în același timp. De-aia sînt două coloane și nu o
-- | singură „stare".
module Components.Explorer.AttestationList
  ( Slot
  , Output
  , _attestationList
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getAttestations)
import Capabilities.Query.Gov.Types (AttestationPage(..), AttestationRow(..))
import Components.Shared.DRepIdentity (shortId)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Format (formatDay, formatInt, humanize, matchLine)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries (RegistryFilters, attestationListHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_attestationList :: Proxy "attestationList"
_attestationList = Proxy

type Input = RegistryFilters

type State =
  { filters :: RegistryFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError AttestationPage
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
    -- `H.fork`, nu `load` direct: initializatorul unui copil ține deschisă inițializarea
    -- PĂRINTELUI, iar părintele e cel care pune titlul documentului. Măsurat pe deploy:
    -- `/activity` răspunde în 12 secunde pe baza vie, iar tab-ul scria titlul generic tot timpul
    -- ăla. Un ecran lent nu are voie să țină în loc cadrul aplicației.
    Initialize -> void (H.fork load)
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
    res <- getAttestations st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Attestations" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "Someone stating something about someone else, on chain. Whether the subject \
                  \accepted it and whether anyone disputed it are separate questions, and both are \
                  \shown."
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
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading attestations…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The attestations could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(AttestationPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "attestation")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState else table p.items
      , if null p.items then HH.text "" else pager st page
      ]

  emptyState =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "No attestations have been issued yet." ] ]
      ]

  table items =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ HH.th_ [ HH.text "Attestation" ]
                          , HH.th_ [ HH.text "Subject" ]
                          , HH.th_ [ HH.text "Issuer" ]
                          , HH.th_ [ HH.text "Date" ]
                          , HH.th_ [ HH.text "Accepted" ]
                          , HH.th_ [ HH.text "Disputes" ]
                          ]
                      ]
                  , HH.tbody_ (map row items)
                  ]
              ]
          ]
      ]

  row (AttestationRow a) =
    HH.tr_
      [ HH.td_
          [ HH.div_ [ HH.text a.name ]
          , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text (humanize a.kind) ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "font-mono text-xs"), HP.title a.subject ] [ HH.text (shortId a.subject) ]
      , HH.td [ HP.class_ (HH.ClassName "font-mono text-xs"), HP.title a.issuer ] [ HH.text (shortId a.issuer) ]
      , HH.td [ HP.class_ (HH.ClassName "text-sm whitespace-nowrap"), HP.title a.date ] [ HH.text (formatDay a.date) ]
      -- „Afirmată, nerecunoscută" și nu „respinsă": subiectul care n-a acceptat încă nu a negat.
      , HH.td_
          [ HH.span
              [ HP.class_ (HH.ClassName ("badge badge-sm " <> if a.accepted then "badge-success" else "badge-outline")) ]
              [ HH.text (if a.accepted then "accepted" else "not yet accepted") ]
          ]
      , HH.td_ [ disputeCell a ]
      ]

  -- Zero dispute e cazul obișnuit și se scrie discret; o dispută deschisă e o întrebare în curs,
  -- iar una confirmată e un verdict împotriva atestării. Trei lucruri, trei culori.
  disputeCell a =
    if a.disputeCount == 0 then
      HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text "none" ]
    else
      HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-1") ]
        [ if a.openDisputeCount > 0 then
            HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-warning") ]
              [ HH.text (formatInt a.openDisputeCount <> " open") ]
          else HH.text ""
        , if a.upheldDisputeCount > 0 then
            HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-error") ]
              [ HH.text (formatInt a.upheldDisputeCount <> " upheld") ]
          else HH.text ""
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text (formatInt a.disputeCount <> " in total") ]
        ]

  pager st (AttestationPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = attestationListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
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
