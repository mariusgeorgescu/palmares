-- | Lista de DRep-i: un apel la `/pages/drep-explorer`, rândurile cu tot ce-i trebuie tabelului,
-- | facetele pentru bara laterală și intervalele de putere.
-- |
-- | Patru lucruri deliberate:
-- |
-- |   * __niciun procent nu se calculează dintr-un facet.__ Facetele se numără fiecare cu propriul
-- |     predicat scos, deci 17+187+526+90 = 820 pe un total de 294. Se afișează numărul, niciodată
-- |     o parte dintr-un întreg care nu există;
-- |   * filtrele și pagina trăiesc în URL, nu în starea componentei. Componenta primește filtrele ca
-- |     input, deci butonul „înapoi" al browserului e un control al ecranului, nu un accident;
-- |   * facetele randate sunt cele pe care le-a trimis serverul, nu o listă de valori scrisă aici.
-- |     Când apare un status nou, bara laterală îl arată fără să schimbăm codul;
-- |   * paginarea se oprește unde serverul dă 400 (`offsetCeiling`), nu când utilizatorul descoperă
-- |     eroarea.
module Components.Explorer.DRepList
  ( Slot
  , Output
  , _drepList
  , component
  , facetLabel
  , bucketLabel
  , sortToggle
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDRepExplorer)
import Capabilities.Query.Gov.Types (DRepExplorerPage(..), DRepSummary(..), Lovelace, PowerBucket(..))
import Components.Chart.Histogram as Histogram
import Components.Shared.DRepIdentity as DRepIdentity
import Data.Array (elem, length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Data.Number.Format (fixed, toStringWith)
import Data.Tuple (Tuple(..))
import Format (formatAda, formatInt, formatPercent, humanize, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route(..))
import Route.GovQueries (DRepFilters, drepListHrefFor, emptyDRepFilters, toggleIn)
import Halogen.Router.Class (class MonadRouter, navigate)
import Type.Proxy (Proxy(..))
import Web.UIEvent.KeyboardEvent as KE

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_drepList :: Proxy "drepList"
_drepList = Proxy

type Input = DRepFilters

type State =
  { filters :: DRepFilters
  , page :: RemoteData ApiError DRepExplorerPage
  , searchDraft :: String
  }

data Action
  = Initialize
  | Receive Input
  | SearchDraft String
  | SearchKey KE.KeyboardEvent
  | SubmitSearch

-- | Eticheta unui facet. Limba e un câmp liber din metadate, iar măsurătoarea a găsit patru DRep-i
-- | cu limba scrisă ca șir gol — ceea ce nu e același lucru cu „nu a declarat o limbă", și se vede
-- | ca atare.
facetLabel :: String -> String
facetLabel "" = "(blank)"
facetLabel s = humanize s

-- | Eticheta unui interval de putere. `hi` lipsă înseamnă „și peste".
-- |
-- | Primul interval măsurat e `lo: 0, hi: 1` — adică exact zero lovelace, fiindcă `hi` e exclusiv.
-- | Formatat ca ADA ar ieși „0,00 ADA – 0,00 ADA", care nu spune nimic. Are nume propriu, și e
-- | intervalul cu cei mai mulți DRep-i din el (109 din 294).
bucketLabel :: Lovelace -> Maybe Lovelace -> String
bucketLabel lo hi
  | lo == 0.0 && hi == Just 1.0 = "No voting power"
  | otherwise = case hi of
      Nothing -> formatAda lo <> " and up"
      Just h -> formatAda lo <> " – " <> formatAda h

-- | Al doilea clic pe aceeași coloană întoarce ordinea; primul clic pe o coloană nouă începe
-- | descrescător, pentru că „cine are cea mai multă putere" e întrebarea pe care o pune cineva care
-- | dă clic pe „putere de vot".
sortToggle :: String -> DRepFilters -> DRepFilters
sortToggle column f =
  if f.order_by == Just column then
    f { sort_order = Just (if f.sort_order == Just "asc" then "desc" else "asc"), offset = Nothing }
  else f { order_by = Just column, sort_order = Just "desc", offset = Nothing }

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
      -- Doar o schimbare reală de filtre reîncarcă. Halogen retrimite input-ul la fiecare randare a
      -- părintelui, iar un apel pe randare ar bate serverul la fiecare tastă apăsată altundeva.
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters, searchDraft = fromMaybe "" filters.q }
        load
    SearchDraft s -> H.modify_ _ { searchDraft = s }
    SearchKey ev -> when (KE.key ev == "Enter") (handleAction SubmitSearch)
    SubmitSearch -> do
      st <- H.get
      let
        trimmed = st.searchDraft
        q = if trimmed == "" then Nothing else Just trimmed
      navigate (DRepList (st.filters { q = q, offset = Nothing }))

  load = do
    st <- H.get
    H.modify_ _ { page = Loading }
    res <- getDRepExplorer st.filters
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
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "DReps" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "Every registered delegated representative, with the power delegated to them and \
              \what they did with it."
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-2 items-center") ]
          [ HH.input
              [ HP.type_ HP.InputSearch
              , HP.class_ (HH.ClassName "input input-bordered input-sm w-72")
              , HP.placeholder "Search by name or DRep id"
              , HP.value st.searchDraft
              , HE.onValueInput SearchDraft
              , HE.onKeyDown SearchKey
              ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm btn-primary")
              , HE.onClick (const SubmitSearch)
              ]
              [ HH.text "Search" ]
          , if hasAnyFilter st.filters then
              HH.a
                [ HP.href (drepListHrefFor emptyDRepFilters)
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
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading DReps…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The DRep list could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          ]
      ]

  body st page@(DRepExplorerPage p) =
    HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "lg:col-span-1 space-y-4") ] [ sidebar st page ]
      , HH.div [ HP.class_ (HH.ClassName "lg:col-span-3 space-y-3") ]
          [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline justify-between gap-2") ]
              [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                  [ HH.text
                      ( formatInt p.total <> " DReps match"
                          <> ", showing "
                          <> show (p.offset + 1)
                          <> "–"
                          <> show (p.offset + length p.items)
                      )
                  ]
              , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                  [ HH.text ("Voting power as of epoch " <> show p.epoch <> ".") ]
              ]
          , table st page
          , pager st page
          ]
      ]

  sidebar st (DRepExplorerPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ facetBlock st "Status" "status" p.statusFacets
      , facetBlock st "Metadata" "anchor_status" p.anchorFacets
      , facetBlock st "Language" "language" p.languageFacets
      , HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
          [ HH.div [ HP.class_ (HH.ClassName "card-body p-3 gap-2") ]
              [ HH.h3 [ HP.class_ (HH.ClassName "font-medium text-sm") ] [ HH.text "Voting power" ]
              , Histogram.render (map (bucketBar st.filters) p.powerBuckets)
              ]
          ]
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
          [ HH.text
              "Facet counts are each computed with their own filter removed, so they do not add up \
              \to the number of matches. Voting-power ranges do."
          ]
      ]

  facetBlock st title key facets =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-3 gap-1") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "font-medium text-sm") ] [ HH.text title ]
          , if null facets then
              HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ HH.text "No values yet." ]
            else HH.div [ HP.class_ (HH.ClassName "space-y-0.5") ] (map (facetRow st key) facets)
          ]
      ]

  facetRow st key (Tuple value count) =
    let
      selected = selectedFor key st.filters
      active = value `elem` selected
      next = withSelected key (toggleIn value selected) st.filters
    in
      HH.a
        [ HP.href (drepListHrefFor (next { offset = Nothing }))
        , HP.class_
            ( HH.ClassName
                ( "flex items-center justify-between gap-2 text-xs rounded px-1 py-0.5 hover:bg-base-300 "
                    <> (if active then "bg-base-300 font-medium" else "")
                )
            )
        ]
        [ HH.span_ [ HH.text (facetLabel value) ]
        , HH.span [ HP.class_ (HH.ClassName "font-mono opacity-70") ] [ HH.text (formatInt count) ]
        ]

  bucketBar filters (PowerBucket b) =
    let
      lo = toStringWith (fixed 0) b.lo
      hi = map (toStringWith (fixed 0)) b.hi
      active = filters.min_voting_power == Just lo && filters.max_voting_power == hi
      next =
        if active then filters { min_voting_power = Nothing, max_voting_power = Nothing, offset = Nothing }
        else filters { min_voting_power = Just lo, max_voting_power = hi, offset = Nothing }
    in
      { label: bucketLabel b.lo b.hi
      , count: b.count
      , href: drepListHrefFor next
      , active
      }

  table st (DRepExplorerPage p) =
    HH.div [ HP.class_ (HH.ClassName "overflow-x-auto card bg-base-200") ]
      [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
          [ HH.thead_
              [ HH.tr_
                  [ sortHeader st "name" "DRep" false
                  , HH.th_ [ HH.text "Status" ]
                  , sortHeader st "voting_power" "Voting power" true
                  , sortHeader st "delegator_count" "Delegators" true
                  , sortHeader st "participation_rate" "Participation" true
                  , sortHeader st "rationale_rate" "Rationale" true
                  , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Open, unvoted" ]
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
    in
      HH.th [ HP.class_ (HH.ClassName (if alignRight then "text-right" else "")) ]
        [ HH.a
            [ HP.href (drepListHrefFor (sortToggle column st.filters))
            , HP.class_ (HH.ClassName ("link link-hover " <> (if sorted then "font-semibold" else "")))
            ]
            [ HH.text (label <> arrow) ]
        ]

  row (DRepSummary d) =
    HH.tr_
      [ HH.td [ HP.class_ (HH.ClassName "max-w-xs") ]
          [ DRepIdentity.render { givenName: d.givenName, drepId: d.id, hasScript: d.hasScript } ]
      , HH.td_
          [ HH.div [ HP.class_ (HH.ClassName "flex flex-col gap-0.5") ]
              [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> statusClass d.status)) ]
                  [ HH.text (humanize d.status) ]
              , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                  [ HH.text (maybe "no expiry on record" (\e -> "until epoch " <> show e) d.activeUntilEpoch) ]
              ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
          [ HH.text (formatAda d.votingPower) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt d.delegatorCount) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ]
          [ HH.div_ [ HH.text (formatPercent d.participationRate) ]
          , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
              [ HH.text (pluralize d.votesCast "vote" <> " of " <> formatInt d.eligibleActions) ]
          ]
      -- `rationale_rate` e `null` la 172 din 200 de DRep-i măsurați. „n/a", nu „0%": zero ar fi o
      -- afirmație despre autor, nu despre date.
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatPercent d.rationaleRate) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt d.openActionsUnvoted) ]
      , HH.td [ HP.class_ (HH.ClassName "text-xs") ]
          [ HH.text (maybe "none" humanize d.anchorStatus) ]
      ]

  statusClass = case _ of
    "active" -> "badge-success"
    "inactive" -> "badge-warning"
    "retired" -> "badge-ghost"
    _ -> "badge-outline"

  pager st (DRepExplorerPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = drepListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
        [ pagerLink prev hrefFor "Previous"
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
            [ HH.text
                ( case next of
                    Just _ -> ""
                    Nothing ->
                      if p.offset + length p.items >= p.total then "End of results."
                      else "Deeper pages are refused past offset " <> show offsetCeiling
                        <> "; narrow the filters instead."
                )
            ]
        , pagerLink next hrefFor "Next"
        ]

  pagerLink target hrefFor label = case target of
    Nothing ->
      HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off ->
      HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]

  hasAnyFilter f =
    not (null f.status) || not (null f.anchor_status) || not (null f.language)
      || isJust f.q
      || isJust f.has_script
      || isJust f.min_voting_power
      || isJust f.max_voting_power

  selectedFor key f = case key of
    "status" -> f.status
    "anchor_status" -> f.anchor_status
    _ -> f.language

  withSelected key values f = case key of
    "status" -> f { status = values }
    "anchor_status" -> f { anchor_status = values }
    _ -> f { language = values }
