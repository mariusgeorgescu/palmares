-- | Retragerile din trezorerie, toate la un loc: `GET /treasury-withdrawals`.
-- |
-- | Ecranul separă CERUT de PLĂTIT, pentru că sunt două întrebări diferite și pe preprod răspunsul
-- | la a doua e „niciodată": toate cele 83 de rînduri măsurate au `enacted_epoch` null. Un singur
-- | număr ar sugera că s-au plătit 656 de milioane de ADA.
-- |
-- | Când o retragere ESTE adoptată, plata în sine nu se poate citi direct pentru fiecare caz, iar
-- | serverul spune asta prin `paid_heuristic`. Ecranul nu prezintă o deducție ca pe o observație.
module Components.Explorer.TreasuryList
  ( Slot
  , Output
  , _treasuryList
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getWithdrawals)
import Capabilities.Query.Gov.Types (ChainPoint(..), Lovelace, WithdrawalPage(..), WithdrawalRow(..))
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Foldable (sum)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Format (formatAda, formatDay, matchLine, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries (WithdrawalFilters, actionDetailHrefFor, withdrawalListHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_treasuryList :: Proxy "treasuryList"
_treasuryList = Proxy

type Input = WithdrawalFilters

type State =
  { filters :: WithdrawalFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError WithdrawalPage
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
    res <- getWithdrawals st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Treasury withdrawals" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "Every withdrawal a governance action has ever asked the treasury for, and \
                  \whether it was enacted. Asking and being paid are different questions."
              ]
          ]
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading withdrawals…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The withdrawals could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(WithdrawalPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ summary p.items
      , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "withdrawal")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState else table st page
      , if null p.items then HH.text "" else pager st page
      ]

  -- Suma e peste PAGINA curentă, și scrie asta. Un total peste toate cele 83 ar cere un apel pe
  -- care nu-l face nimeni, iar a-l prezenta ca total al rețelei fără să-l fi cerut ar fi o
  -- afirmație inventată.
  summary items =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-1") ]
          [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-x-8 gap-y-2") ]
              [ figure "Requested on this page" (formatAda (sumAmounts items))
              , figure "Enacted on this page" (formatAda (sumEnacted items))
              ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "Requested is what the proposals asked for. Enacted is what the treasury actually paid out." ]
          ]
      ]

  sumAmounts :: Array WithdrawalRow -> Lovelace
  sumAmounts items = sum (map (\(WithdrawalRow w) -> w.amount) items)

  sumEnacted :: Array WithdrawalRow -> Lovelace
  sumEnacted items = sum (map (\(WithdrawalRow w) -> maybe 0.0 (const w.amount) w.enactedEpoch) items)

  figure label value =
    HH.div_
      [ HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-70") ] [ HH.text label ]
      , HH.div [ HP.class_ (HH.ClassName "text-2xl font-bold") ] [ HH.text value ]
      ]

  emptyState =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "No withdrawals have been recorded yet." ] ]
      ]

  table st (WithdrawalPage p) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ HH.th_ [ HH.text "Proposal" ]
                          , HH.th_ [ HH.text "Beneficiary" ]
                          , sortHeader st "amount" "Amount" "text-right"
                          , sortHeader st "enacted_epoch" "Enacted" "text-right"
                          ]
                      ]
                  , HH.tbody_ (map row p.items)
                  ]
              ]
          ]
      ]

  sortHeader st key label align =
    let
      active = st.filters.order_by == Just key
      dir = fromMaybe "desc" st.filters.sort_order
      nextDir = if active && dir == "desc" then "asc" else "desc"
      arrow = if active then (if dir == "desc" then " ↓" else " ↑") else ""
      href = withdrawalListHrefFor (st.filters { order_by = Just key, sort_order = Just nextDir, offset = Nothing })
    in
      HH.th [ HP.class_ (HH.ClassName align) ]
        [ HH.a
            [ HP.href href
            , HP.class_ (HH.ClassName ("link link-hover" <> if active then " font-bold" else ""))
            , HP.attr (HH.AttrName "aria-sort")
                (if active then (if dir == "desc" then "descending" else "ascending") else "none")
            ]
            [ HH.text (label <> arrow) ]
        ]

  row (WithdrawalRow w) =
    HH.tr_
      [ HH.td_
          [ HH.a
              [ HP.href (actionDetailHrefFor w.govActionId), HP.class_ (HH.ClassName "link link-hover") ]
              [ HH.text (fromMaybe "Untitled proposal" w.govActionTitle) ]
          , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 break-all") ]
              [ HH.text w.govActionId ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ] [ HH.text w.beneficiary ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
          [ HH.text (formatAda w.amount) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right text-sm whitespace-nowrap") ] [ enactedCell w ]
      ]

  -- „Nu a fost adoptată" e o stare, nu o celulă goală. Iar când a fost, se spune și CUM se știe:
  -- `paid_heuristic` înseamnă că plata a fost dedusă, nu citită dintr-o ieșire de tranzacție.
  enactedCell w = case w.enactedAt of
    Just (ChainPoint at) ->
      HH.div_
        [ HH.div_ [ HH.text ("epoch " <> show at.epoch) ]
        , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text (formatDay at.time) ]
        , if w.paidHeuristic == Just true then
            HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text "inferred, not read on chain" ]
          else HH.text ""
        ]
    Nothing -> HH.span [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "not enacted" ]

  pager st (WithdrawalPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = withdrawalListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
        [ pagerLink prev hrefFor "Previous"
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text
                ( case next of
                    Just _ -> pluralize p.total "withdrawal" <> " in total"
                    Nothing ->
                      if p.offset + length p.items >= p.total then "End of results."
                      else "Deeper pages are refused past offset " <> show offsetCeiling <> "."
                )
            ]
        , pagerLink next hrefFor "Next"
        ]

  pagerLink target hrefFor label = case target of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off -> HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]
