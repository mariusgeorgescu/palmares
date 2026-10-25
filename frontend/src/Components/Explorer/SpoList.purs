-- | Lista operatorilor de pool cu putere de vot: `GET /spos`.
-- |
-- | Ecranul are DOUĂ coloane goale pe toată rețeaua de preprod — `ticker` și rata de participare —
-- | și asta nu e o scăpare, ci exact ce trebuie arătat. Măsurat pe toate cele 511 rânduri:
-- | fiecare are amândouă `null`. Un ecran care le-ar scoate ar ascunde o proprietate a
-- | deployment-ului, iar unul care ar pune „0%" ar acuza 511 operatori că n-au votat niciodată
-- | când de fapt nu li s-a putut calcula un numitor. Deci coloanele rămân, cu „n/a", și o
-- | propoziție sub tabel spune de ce.
-- |
-- | Trei coloane se pot sorta — puterea, voturile și identificatorul — pentru că atât acceptă
-- | serverul (`SPOsOrderBy`). `delegator_count` arată sortabil dar dă 400, deci nu e cap de
-- | coloană apăsabil aici.
module Components.Explorer.SpoList
  ( Slot
  , Output
  , _spoList
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getSpos)
import Capabilities.Query.Gov.Types (SpoPage(..), SpoRow(..))
import Data.Array (head, length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Format (formatAda, formatInt, formatPercent, matchLine, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries (SpoFilters, spoListHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_spoList :: Proxy "spoList"
_spoList = Proxy

type Input = SpoFilters

type State =
  { filters :: SpoFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError SpoPage
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
    res <- getSpos st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ header
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  header =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Stake pool operators" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "Pools vote on a subset of governance actions — hard forks, no-confidence motions, \
              \committee changes and the security group of parameter changes — with the stake \
              \delegated to them."
          ]
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading pools…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The pools could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(SpoPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline justify-between gap-2") ]
          [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text (matchLine p.total p.offset (length p.items) "pool")
              , if st.refreshing then
                  HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
                else HH.text ""
              ]
          , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
              [ HH.text (powerEpochNote p.items) ]
          ]
      , if null p.items then emptyState else table st page
      , if null p.items then HH.text "" else pager st page
      ]

  emptyState =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "No pools have been recorded yet." ] ]
      ]

  -- Epoca distribuției e aceeași pentru tot tabelul, deci se scrie o dată, deasupra, și nu de 200
  -- de ori într-o coloană.
  powerEpochNote items =
    maybe "" (\(SpoRow r) -> "Voting power as of epoch " <> show r.votingPowerEpoch <> ".") (head items)

  table st (SpoPage p) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ sortHeader st "pool_id" "Pool" ""
                          , sortHeader st "voting_power" "Voting power" "text-right"
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Delegators" ]
                          , sortHeader st "votes_cast" "Votes cast" "text-right"
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Participation" ]
                          ]
                      ]
                  , HH.tbody_ (map row p.items)
                  ]
              ]
          ]
      ]

  -- Capul de coloană e un LINK, nu un buton: sortarea trăiește în URL, deci rezultatul sortat e
  -- partajabil și butonul înapoi îl anulează. Clicul următor pe aceeași coloană inversează sensul.
  sortHeader st key label align =
    let
      active = st.filters.order_by == Just key
      dir = fromMaybe "desc" st.filters.sort_order
      nextDir = if active && dir == "desc" then "asc" else "desc"
      arrow = if active then (if dir == "desc" then " ↓" else " ↑") else ""
      href = spoListHrefFor (st.filters { order_by = Just key, sort_order = Just nextDir, offset = Nothing })
    in
      HH.th [ HP.class_ (HH.ClassName align) ]
        [ HH.a
            [ HP.href href
            , HP.class_ (HH.ClassName ("link link-hover" <> if active then " font-bold" else ""))
            , HP.attr (HH.AttrName "aria-sort") (if active then (if dir == "desc" then "descending" else "ascending") else "none")
            ]
            [ HH.text (label <> arrow) ]
        ]

  row (SpoRow r) =
    HH.tr_
      [ HH.td [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ]
          [ HH.div_ [ HH.text (fromMaybe "Unnamed pool" r.ticker) ]
          , HH.div [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text r.poolId ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
          [ HH.text (formatAda r.votingPower) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt r.delegatorCount) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt r.votesCast) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatPercent r.participationRate) ]
      ]

  pager st (SpoPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = spoListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
        [ HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
            [ pagerLink prev hrefFor "Previous"
            , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
                [ HH.text
                    ( case next of
                        Just _ -> pluralize p.total "pool" <> " in total"
                        Nothing ->
                          if p.offset + length p.items >= p.total then "End of results."
                          else "Deeper pages are refused past offset " <> show offsetCeiling <> "."
                    )
                ]
            , pagerLink next hrefFor "Next"
            ]
        -- Nota nu e o scuză, e citirea corectă a două coloane goale. Fără ea, un vizitator
        -- concluzionează că niciun pool de pe rețea n-a votat vreodată.
        , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text
                "Tickers come from each pool's off-chain metadata, which this deployment does not \
                \fetch, so the name column is empty for every pool. Participation needs a \
                \denominator — the actions a pool was entitled to vote on — which this network has \
                \not produced yet; \"n/a\" there means unmeasured, not zero."
            ]
        ]

  pagerLink target hrefFor label = case target of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off -> HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]
