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
import Format (formatAda, formatInt, humanize, matchLine)
import Halogen as H
import Components.Shared.Pager as Pager
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
  -- Cât timp vine următorul răspuns, cel vechi rămâne pe ecran. Fără asta, orice clic pe o
  -- fațetă, pe un cap de coloană sau pe „Next" ștergea tabelul ȘI bara de filtre de sub degetul
  -- utilizatorului, lăsând un card de 50px cu trei puncte.
  -- Pliat pe telefon, deschis pe desktop (prin CSS, nu prin stare): măsurat, bara de filtre cerea
  -- peste un ecran de derulat înainte de primul rând de date.
  , filtersOpen :: Boolean
  , refreshing :: Boolean
  , page :: RemoteData ApiError GovActionPage
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
  "expired" -> -- `badge-ghost` are fundalul `base-200`, adică exact culoarea cardului în care stă: starea
    -- neutră era singura invizibilă. `badge-outline` are contur și text, deci se vede.
    "badge-outline"
  "dropped" -> "badge-error"
  _ -> "badge-outline"

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
    -- `Loading` doar la prima încărcare; la o re-filtrare rămâne ce era, cu un semn discret.
    H.modify_ \s0 -> case s0.page of
      Success _ -> s0 { refreshing = true }
      _ -> s0 { page = Loading }
    res <- getGovActions st.filters
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
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
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
          -- Un ecran de eroare fără nimic de apăsat e un fund de sac: singura ieșire rămâne
          -- reîncărcarea din browser, care pe ruta asta costă încă o dată cele ~30 de secunde de
          -- așteptare. `isRetryable` există deja în transport, dar nu-l folosea nimeni.
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm")
              , HP.type_ HP.ButtonButton
              , HE.onClick (const Retry)
              ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(GovActionPage p) =
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
              [ sidebar st ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "lg:col-span-3 min-w-0 space-y-3") ]
          [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text (matchLine p.total p.offset (length p.items) "proposal")
              , if st.refreshing then
                  HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
                else HH.text ""
              ]
          , if null p.items then emptyState st else table st page
          , if null p.items then HH.text "" else pager st page
          ]
      ]

  emptyState st =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
          [ HH.p_ [ HH.text (if hasAnyFilter st.filters then "No proposals match these filters." else "No proposals have been recorded yet.") ]
          , if hasAnyFilter st.filters then
              HH.a
                [ HP.href (actionListHrefFor emptyGovActionFilters)
                , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
                ]
                [ HH.text "Clear the filters" ]
            else HH.text ""
          ]
      ]

  sidebar st =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ filterBlock st "Kind" "type" actionTypes
      , filterBlock st "Outcome" "state" actionStates
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text "Filter options, not counts." ]
      ]

  filterBlock st title key values =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
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

      next =
        if sorted then
          st.filters
            { sort_order = Just (if st.filters.sort_order == Just "asc" then "desc" else "asc")
            , offset = Nothing
            }
        else st.filters { order_by = Just column, sort_order = Just "desc", offset = Nothing }
    in
      HH.th
        [ HP.class_ (HH.ClassName (if alignRight then "text-right" else ""))
        , HP.attr (HH.AttrName "aria-sort") sortState
        , HP.scope HP.ScopeCol
        ]
        [ HH.a
            [ HP.href (actionListHrefFor next)
            , HP.class_ (HH.ClassName ("link link-hover inline-block py-1.5 " <> (if sorted then "font-semibold" else "")))
            ]
            [ HH.text label
            , HH.span
                [ HP.class_ (HH.ClassName ("ml-1 " <> (if sorted then "" else "opacity-70")))
                , HP.attr (HH.AttrName "aria-hidden") "true"
                ]
                [ HH.text arrow ]
            ]
        ]

  row (GovActionSummary a) =
    let
      ChainPoint at = a.proposedAt
      Lifecycle lc = a.lifecycle
    in
      HH.tr [ HP.class_ (HH.ClassName "hover:bg-base-300") ]
        -- `max-w-xs` ca în celelalte două liste, iar starea documentului coboară aici, sub titlu:
        -- cu opt coloane, „Asked for" — cifra de bani a propunerii — rămânea în afara ecranului
        -- chiar și la 1280px, fără nicio bară de derulare vizibilă.
        [ HH.td [ HP.class_ (HH.ClassName "max-w-xs") ]
            [ HH.a [ HP.href (actionDetailHrefFor a.id), HP.class_ (HH.ClassName "hover:underline") ]
                [ HH.div [ HP.class_ (HH.ClassName "font-medium truncate") ]
                    [ HH.text (fromMaybe "Untitled proposal" a.title) ]
                , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 truncate"), HP.title a.id ]
                    [ HH.text a.bech32 ]
                ]
            , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
                [ HH.text ("metadata: " <> maybe "none" humanize a.anchorStatus) ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (humanize a.type_) ]
        , HH.td_
            [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> stateClass lc.state)) ]
                [ HH.text (humanize lc.state) ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-sm whitespace-nowrap") ]
            [ HH.text ("epoch " <> show at.epoch) ]
        , HH.td [ HP.class_ (HH.ClassName "text-right text-sm whitespace-nowrap") ]
            [ HH.div_ [ HH.text (maybe "not recorded" (\e -> "epoch " <> show e) a.expiresEpoch) ]
            , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
                [ HH.text (maybe "" (\e -> "votable to " <> show e) a.lastVotableEpoch) ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt a.votesCast) ]
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
            [ HH.text (maybe "—" formatAda a.treasuryAmount) ]
        ]

  pager st (GovActionPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = actionListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      Pager.render
        { total: p.total
        , offset: p.offset
        , shown: length p.items
        , ceiling: offsetCeiling
        , prev
        , next
        , hrefFor
        , noun: "proposal"
        }

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
