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

import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDRepExplorer)
import Capabilities.Query.Gov.Types (DRepExplorerPage(..), DRepSummary(..), Lovelace, PowerBucket(..))
import Components.Chart.Histogram as Histogram
import Components.Shared.DRepIdentity as DRepIdentity
import Components.Shared.Remote as Remote
import Data.Array (elem, length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Data.Number.Format (fixed, toStringWith)
import Data.Tuple (Tuple(..))
import Format (formatAda, formatAdaOnly, formatInt, formatPercent, humanize, matchLine, pluralize)
import Halogen as H
import Components.Shared.Pager as Pager
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route(..))
import Route.GovQueries (DRepFilters, drepDetailHrefFor, drepListHrefFor, emptyDRepFilters, toggleIn)
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
  -- Cât timp vine următorul răspuns, cel vechi rămâne pe ecran. Fără asta, orice clic pe o
  -- fațetă, pe un cap de coloană sau pe „Next" ștergea tabelul ȘI bara de filtre de sub degetul
  -- utilizatorului, lăsând un card de 50px cu trei puncte.
  -- Pliat pe telefon, deschis pe desktop (prin CSS, nu prin stare): măsurat, bara de filtre cerea
  -- peste un ecran de derulat înainte de primul rând de date.
  , filtersOpen :: Boolean
  , refreshing :: Boolean
  , page :: RemoteData ApiError DRepExplorerPage
  , searchDraft :: String
  }

data Action
  = Initialize
  | Retry
  | ToggleFilters
  | Receive Input
  | SearchDraft String
  | SearchKey KE.KeyboardEvent
  | SubmitSearch

-- | Eticheta unui facet. Limba e un câmp liber din metadate, iar măsurătoarea a găsit patru DRep-i
-- | cu limba scrisă ca șir gol — ceea ce nu e același lucru cu „nu a declarat o limbă", și se vede
-- | ca atare.
-- | Eticheta unui facet. Cheia contează: `humanize` e corect pentru enumerările ledgerului
-- | (`hash_mismatch` → „Hash mismatch"), dar aplicat unei etichete BCP-47 scotea „En-us", o formă
-- | care nu există nici ca limbă, nici ca tag.
facetLabel :: String -> String -> String
facetLabel _ "" = "declared, but empty"
facetLabel "language" value = value
facetLabel _ value = humanize value

-- | Eticheta unui interval de putere. `hi` lipsă înseamnă „și peste".
-- |
-- | Primul interval măsurat e `lo: 0, hi: 1` — adică exact zero lovelace, fiindcă `hi` e exclusiv.
-- | Formatat ca ADA ar ieși „0,00 ADA – 0,00 ADA", care nu spune nimic. Are nume propriu, și e
-- | intervalul cu cei mai mulți DRep-i din el (109 din 294).
-- | Unitatea nu se repetă de douăsprezece ori într-o coloană de etichete: stă o singură dată, în
-- | titlul blocului. Iar `lo == 1` lovelace formatat ca ADA dădea „0.00 ADA – 1,000 ADA", care se
-- | citea ca același interval cu „No voting power" de deasupra lui.
bucketLabel :: Lovelace -> Maybe Lovelace -> String
bucketLabel lo hi
  | lo == 0.0 && hi == Just 1.0 = "No voting power"
  | lo == 1.0 = case hi of
      Nothing -> "any"
      Just h -> "under " <> formatAdaOnly h
  | otherwise = case hi of
      Nothing -> formatAdaOnly lo <> " and up"
      Just h -> formatAdaOnly lo <> " – " <> formatAdaOnly h

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
    { initialState: \filters ->
        { filters
        , page: NotAsked
        , filtersOpen: false
        , refreshing: false
        , searchDraft: fromMaybe "" filters.q
        }
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
    ToggleFilters -> H.modify_ \st -> st { filtersOpen = not st.filtersOpen }
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
    -- `Loading` doar la prima încărcare; la o re-filtrare rămâne ce era, cu un semn discret.
    H.modify_ \s0 -> case s0.page of
      Success _ -> s0 { refreshing = true }
      _ -> s0 { page = Loading }
    res <- getDRepExplorer st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
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

  loading = Remote.loadingCard "Loading DReps…"

  failure e = Remote.errorCard "The DRep list could not be loaded." e Retry

  body st page@(DRepExplorerPage p) =
    HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-4") ]
      -- Pe telefon bara de filtre ajunge DEASUPRA rezultatelor, și e lungă: măsurat, peste un
      -- ecran întreg de derulat până la primul rând de date. Pliată, rămâne la un rând; pe desktop
      -- `open` o ține mereu deschisă, deci nu se schimbă nimic acolo.
      [ HH.div [ HP.class_ (HH.ClassName "lg:col-span-1 min-w-0 space-y-2") ]
          [ HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm btn-ghost w-full justify-start lg:hidden")
              , HP.type_ HP.ButtonButton
              , HE.onClick (const ToggleFilters)
              , HP.attr (HH.AttrName "aria-expanded") (if st.filtersOpen then "true" else "false")
              ]
              [ HH.text (if st.filtersOpen then "Hide filters" else "Filters") ]
          , HH.div
              [ HP.class_
                  (HH.ClassName (if st.filtersOpen then "space-y-4" else "hidden lg:block space-y-4"))
              ]
              [ sidebar st page ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "lg:col-span-3 min-w-0 space-y-3") ]
          [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline justify-between gap-2") ]
              [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                  [ HH.text (matchLine p.total p.offset (length p.items) "DRep")
                  , if st.refreshing then
                      HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
                    else HH.text ""
                  ]
              , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
                  [ HH.text ("Voting power as of epoch " <> show p.epoch <> ".") ]
              ]
          , if null p.items then emptyState st else table st page
          , if null p.items then HH.text "" else pager st page
          ]
      ]

  -- Zero rezultate nu e un tabel gol cu capete de coloană: e o propoziție care spune ce s-a
  -- întâmplat și un drum înapoi. „showing 1–0" nu înseamnă nimic pentru nimeni.
  emptyState st =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
          [ HH.p_ [ HH.text (if hasAnyFilter st.filters then "No DReps match these filters." else "No DReps have been recorded yet.") ]
          , if hasAnyFilter st.filters then
              HH.a
                [ HP.href (drepListHrefFor emptyDRepFilters)
                , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
                ]
                [ HH.text "Clear the filters" ]
            else HH.text ""
          ]
      ]

  sidebar st (DRepExplorerPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ facetBlock st "Status" "status" p.statusFacets
      , facetBlock st "Metadata" "anchor_status" p.anchorFacets
      , facetBlock st "Language" "language" p.languageFacets
      , HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
          [ HH.div [ HP.class_ (HH.ClassName "card-body p-3 gap-2") ]
              [ HH.h3 [ HP.class_ (HH.ClassName "font-medium text-sm") ] [ HH.text "Voting power (ADA)" ]
              , Histogram.render (map (bucketBar st.filters) p.powerBuckets)
              ]
          ]
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text
              "Each count shows how many DReps you would get by picking that option on its own, so \
              \the options overlap and do not add up to the number of matches. The voting-power \
              \ranges do add up."
          ]
      ]

  facetBlock st title key facets =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-3 gap-1") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "font-medium text-sm") ] [ HH.text title ]
          , if null facets then
              HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text "No values yet." ]
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
                ( "flex items-center justify-between gap-2 text-xs rounded px-2 py-2 lg:px-1 lg:py-0.5 hover:bg-base-300 "
                    <> (if active then "bg-base-300 font-medium" else "")
                )
            )
        ]
        [ HH.span_ [ HH.text (facetLabel key value) ]
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
                  , HH.th [ HP.scope HP.ScopeCol ] [ HH.text "Metadata" ]
                  ]
              ]
          , HH.tbody_ (map row p.items)
          ]
      ]

  sortHeader st column label alignRight =
    let
      sorted = st.filters.order_by == Just column
      -- Semn neutru pe coloanele sortabile, nu nimic: altfel șase capete din opt sunt linkuri și
      -- două nu, iar nimic nu le deosebește până nu dai clic. Săgeata e un nod separat și ascuns
      -- de cititoarele de ecran — starea o spune `aria-sort` pe celulă, nu un caracter în nume.
      -- U+FE0E după săgeata neutră: fără el, „↕" se randează ca emoji colorat pe telefon.
      arrow =
        if not sorted then "↕\xfe0e"
        else if st.filters.sort_order == Just "asc" then "▲"
        else "▼"

      sortState =
        if not sorted then "none"
        else if st.filters.sort_order == Just "asc" then "ascending"
        else "descending"
    in
      HH.th
        [ HP.class_ (HH.ClassName (if alignRight then "text-right" else ""))
        , HP.attr (HH.AttrName "aria-sort") sortState
        , HP.scope HP.ScopeCol
        ]
        [ HH.a
            [ HP.href (drepListHrefFor (sortToggle column st.filters))
            , HP.class_ (HH.ClassName ("link link-hover inline-block py-1.5 " <> (if sorted then "font-semibold" else "")))
            ]
            [ HH.text (label <> arrow) ]
        ]

  row (DRepSummary d) =
    HH.tr [ HP.class_ (HH.ClassName "hover:bg-base-300") ]
      [ HH.td [ HP.class_ (HH.ClassName "max-w-xs") ]
          [ HH.a [ HP.href (drepDetailHrefFor d.id), HP.class_ (HH.ClassName "hover:underline") ]
              [ DRepIdentity.render { givenName: d.givenName, drepId: d.id, hasScript: d.hasScript } ]
          ]
      , HH.td_
          [ HH.div [ HP.class_ (HH.ClassName "flex flex-col gap-0.5") ]
              [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> statusClass d.status)) ]
                  [ HH.text (humanize d.status) ]
              -- „until epoch 296" cu epoca curentă 321 se citea „inactiv până în 296", adică
              -- exact pe dos. Timpul verbal vine din status, care e în același rând de date.
              , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
                  [ HH.text (activeUntilLabel d.status d.activeUntilEpoch) ]
              ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
          [ HH.text (formatAda d.votingPower) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt d.delegatorCount) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ]
          [ HH.div_ [ HH.text (formatPercent d.participationRate) ]
          , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
              [ HH.text (pluralize d.votesCast "vote" <> " of " <> formatInt d.eligibleActions) ]
          ]
      -- `rationale_rate` e `null` la 172 din 200 de DRep-i măsurați. „n/a", nu „0%": zero ar fi o
      -- afirmație despre autor, nu despre date.
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatPercent d.rationaleRate) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt d.openActionsUnvoted) ]
      , HH.td [ HP.class_ (HH.ClassName "text-xs") ]
          [ HH.text (maybe "none" humanize d.anchorStatus) ]
      ]

  -- Timpul verbal al epocii de expirare, derivat din status: același număr înseamnă „până când
  -- rămâne activ" pentru unul activ și „de când nu mai e" pentru unul expirat.
  activeUntilLabel status = case _ of
    Nothing -> "no expiry on record"
    Just e ->
      if status == "active" then "active until epoch " <> show e
      else "was active until epoch " <> show e

  statusClass = case _ of
    "active" -> "badge-success"
    "inactive" -> "badge-warning"
    "retired" -> -- `badge-ghost` are fundalul `base-200`, adică exact culoarea cardului în care stă: starea
      -- neutră era singura invizibilă. `badge-outline` are contur și text, deci se vede.
      "badge-outline"
    _ -> "badge-outline"

  pager st (DRepExplorerPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = drepListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      Pager.render
        { total: p.total
        , offset: p.offset
        , shown: length p.items
        , ceiling: offsetCeiling
        , prev
        , next
        , hrefFor
        , noun: "DRep"
        }

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
