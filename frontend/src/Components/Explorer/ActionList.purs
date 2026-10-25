-- | Lista acțiunilor de guvernanță: `GET /gov-actions`, cu filtre și paginare în URL.
-- |
-- | Spre deosebire de lista de DRep-i, ruta asta __nu__ are compozit de pagină, deci nu vin facete
-- | cu numere. Valorile de filtru sunt enumerările protocolului, scrise aici pentru că serverul le
-- | publică în schemă și nu le poate publica altfel: fără compozit n-ar avea unde să le numere.
-- | Diferența se vede pe ecran — aici nu scrie niciun număr lângă un filtru, exact ca să nu pară un
-- | facet.
module Components.Explorer.ActionList
  ( Slot
  , Output
  , _actionList
  , component
  , actionTypes
  , actionStates
  , stateClass
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getGovActions)
import Capabilities.Query.Gov.Types (ChainPoint(..), GovActionPage(..), GovActionSummary(..), Lifecycle(..))
import Data.Array (elem, length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Format (formatAda, formatInt, humanize, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter, navigate)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route(..))
import Route.GovQueries (GovActionFilters, actionDetailHrefFor, actionListHrefFor, emptyGovActionFilters, toggleIn)
import Type.Proxy (Proxy(..))
import Web.UIEvent.KeyboardEvent as KE

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_actionList :: Proxy "actionList"
_actionList = Proxy

type Input = GovActionFilters

type State =
  { filters :: GovActionFilters
  , page :: RemoteData ApiError GovActionPage
  , searchDraft :: String
  }

data Action
  = Initialize
  | Receive Input
  | SearchDraft String
  | SearchKey KE.KeyboardEvent
  | SubmitSearch

-- | Cele șapte tipuri de acțiune din ledger, în ordinea din schemă.
actionTypes :: Array String
actionTypes =
  [ "parameter_change"
  , "hard_fork_initiation"
  , "treasury_withdrawals"
  , "no_confidence"
  , "new_committee"
  , "new_constitution"
  , "info_action"
  ]

-- | Cele cinci stări posibile. `proposed` înseamnă „încă se votează".
actionStates :: Array String
actionStates = [ "proposed", "ratified", "enacted", "expired", "dropped" ]

stateClass :: String -> String
stateClass = case _ of
  "proposed" -> "badge-info"
  "ratified" -> "badge-success"
  "enacted" -> "badge-success"
  "expired" -> "badge-ghost"
  "dropped" -> "badge-error"
  _ -> "badge-outline"

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, page: NotAsked, searchDraft: fromMaybe "" filters.q }
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
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters, searchDraft = fromMaybe "" filters.q }
        load
    SearchDraft s -> H.modify_ _ { searchDraft = s }
    SearchKey ev -> when (KE.key ev == "Enter") (handleAction SubmitSearch)
    SubmitSearch -> do
      st <- H.get
      let q = if st.searchDraft == "" then Nothing else Just st.searchDraft
      navigate (ActionList (st.filters { q = q, offset = Nothing }))

  load = do
    st <- H.get
    H.modify_ _ { page = Loading }
    res <- getGovActions st.filters
    H.modify_ _
      { page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ header st
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  header st =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Governance actions" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "Every proposal ever submitted on this network, what it asked for, and what became \
              \of it."
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-2 items-center") ]
          [ HH.input
              [ HP.type_ HP.InputSearch
              , HP.class_ (HH.ClassName "input input-bordered input-sm w-72")
              , HP.placeholder "Search titles and abstracts"
              , HP.value st.searchDraft
              , HE.onValueInput SearchDraft
              , HE.onKeyDown SearchKey
              ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm btn-primary"), HE.onClick (const SubmitSearch) ]
              [ HH.text "Search" ]
          , if hasAnyFilter st.filters then
              HH.a
                [ HP.href (actionListHrefFor emptyGovActionFilters)
                , HP.class_ (HH.ClassName "btn btn-sm btn-ghost")
                ]
                [ HH.text "Clear filters" ]
            else HH.text ""
          ]
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading proposals…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The proposals could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          ]
      ]

  body st page@(GovActionPage p) =
    HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "lg:col-span-1 min-w-0 space-y-4") ] [ sidebar st ]
      , HH.div [ HP.class_ (HH.ClassName "lg:col-span-3 min-w-0 space-y-3") ]
          [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text
                  ( formatInt p.total <> " proposals match, showing "
                      <> show (p.offset + 1)
                      <> "–"
                      <> show (p.offset + length p.items)
                  )
              ]
          , table st page
          , pager st page
          ]
      ]

  sidebar st =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ filterBlock st "Kind" "type" actionTypes
      , filterBlock st "Outcome" "state" actionStates
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
          [ HH.text
              "These are the values the ledger allows, not counts: this route has no facet \
              \endpoint, so nothing here claims how many there are."
          ]
      ]

  filterBlock st title key values =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-3 gap-1") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "font-medium text-sm") ] [ HH.text title ]
          , HH.div [ HP.class_ (HH.ClassName "space-y-0.5") ] (map (filterRow st key) values)
          ]
      ]

  filterRow st key value =
    let
      selected = selectedFor key st.filters
      active = value `elem` selected
      next = withSelected key (toggleIn value selected) st.filters
    in
      HH.a
        [ HP.href (actionListHrefFor (next { offset = Nothing }))
        , HP.class_
            ( HH.ClassName
                ( "block text-xs rounded px-2 py-2 lg:px-1 lg:py-0.5 hover:bg-base-300 "
                    <> (if active then "bg-base-300 font-medium" else "")
                )
            )
        ]
        [ HH.text (humanize value) ]

  table st (GovActionPage p) =
    HH.div [ HP.class_ (HH.ClassName "overflow-x-auto card bg-base-200") ]
      [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
          [ HH.thead_
              [ HH.tr_
                  [ HH.th_ [ HH.text "Proposal" ]
                  , sortHeader st "type" "Kind" false
                  , HH.th_ [ HH.text "Outcome" ]
                  , sortHeader st "proposed_at" "Proposed" false
                  , sortHeader st "expires_epoch" "Expires" true
                  , sortHeader st "votes_cast" "Votes" true
                  , sortHeader st "treasury_amount" "Asked for" true
                  , HH.th_ [ HH.text "Metadata" ]
                  ]
              ]
          , HH.tbody_ (map row p.items)
          ]
      ]

  sortHeader st column label alignRight =
    let
      sorted = st.filters.order_by == Just column
      arrow =
        if not sorted then ""
        else if st.filters.sort_order == Just "asc" then " ▲"
        else " ▼"

      next =
        if sorted then
          st.filters
            { sort_order = Just (if st.filters.sort_order == Just "asc" then "desc" else "asc")
            , offset = Nothing
            }
        else st.filters { order_by = Just column, sort_order = Just "desc", offset = Nothing }
    in
      HH.th [ HP.class_ (HH.ClassName (if alignRight then "text-right" else "")) ]
        [ HH.a
            [ HP.href (actionListHrefFor next)
            , HP.class_ (HH.ClassName ("link link-hover inline-block py-1.5 " <> (if sorted then "font-semibold" else "")))
            ]
            [ HH.text (label <> arrow) ]
        ]

  row (GovActionSummary a) =
    let
      ChainPoint at = a.proposedAt
      Lifecycle lc = a.lifecycle
    in
      HH.tr_
        [ HH.td [ HP.class_ (HH.ClassName "max-w-md") ]
            [ HH.a [ HP.href (actionDetailHrefFor a.id), HP.class_ (HH.ClassName "hover:underline") ]
                [ HH.div [ HP.class_ (HH.ClassName "font-medium truncate") ]
                    [ HH.text (fromMaybe "Untitled proposal" a.title) ]
                , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-60 truncate"), HP.title a.id ]
                    [ HH.text a.bech32 ]
                ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (humanize a.type_) ]
        , HH.td_
            [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> stateClass lc.state)) ]
                [ HH.text (humanize lc.state) ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-sm whitespace-nowrap") ]
            [ HH.text ("epoch " <> show at.epoch) ]
        , HH.td [ HP.class_ (HH.ClassName "text-right text-sm whitespace-nowrap") ]
            [ HH.div_ [ HH.text ("epoch " <> show a.expiresEpoch) ]
            , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                [ HH.text ("votable to " <> show a.lastVotableEpoch) ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt a.votesCast) ]
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
            [ HH.text (maybe "—" formatAda a.treasuryAmount) ]
        , HH.td [ HP.class_ (HH.ClassName "text-xs") ] [ HH.text (maybe "none" humanize a.anchorStatus) ]
        ]

  pager st (GovActionPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = actionListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
        [ pagerLink prev hrefFor "Previous"
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
            [ HH.text
                ( case next of
                    Just _ -> pluralize p.total "proposal" <> " in total"
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

  hasAnyFilter f =
    not (null f.type_) || not (null f.state) || not (null f.anchor_status) || isJust f.q

  selectedFor key f = case key of
    "type" -> f.type_
    "anchor_status" -> f.anchor_status
    _ -> f.state

  withSelected key values f = case key of
    "type" -> f { type_ = values }
    "anchor_status" -> f { anchor_status = values }
    _ -> f { state = values }
