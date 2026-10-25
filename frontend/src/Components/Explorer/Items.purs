-- | Worked example of an explorer page: page-shaped capability (`getItemsPage`)
-- | with `RemoteData`, debounced search via `MonadDelay`, and DaisyUI markup.
-- |
-- | Copy this module as the template for new explorer pages: rename `Item`,
-- | `ItemsQuery`, `ItemsPage`, and the capability method to your domain.
module Components.Explorer.Items
  ( Slot
  , _items
  , Query
  , Output
  , Input
  , component
  ) where

import Prelude

import Capabilities.Delay (class MonadDelay, delayMs)
import Capabilities.Query.Api.MonadQueryApi (class MonadQueryApi, getItemsPage)
import Capabilities.Query.Api.Types (Item, ItemsPage, ItemsQuery, defaultItemsQuery, unItemId)
import Data.Const (Const)
import Data.Either (either)
import Data.Maybe (Maybe(..))
import Data.String (length) as String
import Effect.Aff (Milliseconds(..))
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Type.Proxy (Proxy(..))

type Slot = H.Slot Query Output Unit

_items :: Proxy "items"
_items = Proxy

type Input = Unit
type Output = Void

type Query :: forall k. k -> Type
type Query = Const Void

type State =
  { items :: RemoteData String ItemsPage
  , query :: ItemsQuery
  , searchToken :: Int -- bumped on each keystroke; used to drop stale debounced loads
  }

data Action
  = Initialize
  | SetSearch String
  | Paginate Int -- delta (e.g. +1 / -1)
  | LoadPage Int -- the searchToken at the time of scheduling

component
  :: forall m
   . MonadQueryApi m
  => MonadDelay m
  => H.Component Query Input Output m
component =
  H.mkComponent
    { initialState: const
        { items: NotAsked
        , query: defaultItemsQuery
        , searchToken: 0
        }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  handleAction = case _ of
    Initialize -> load
    SetSearch s -> do
      st <- H.get
      let nextToken = st.searchToken + 1
      H.modify_ _
        { query = st.query
            { search = if String.length s == 0 then Nothing else Just s
            , offset = 0
            }
        , searchToken = nextToken
        }
      -- Debounce: fork so we don't block the action queue while waiting. If
      -- another keystroke bumps searchToken before the fork wakes, the guard
      -- in LoadPage drops this stale call.
      void $ H.fork do
        delayMs (Milliseconds 250.0)
        handleAction (LoadPage nextToken)
    LoadPage token -> do
      currentToken <- H.gets _.searchToken
      when (token == currentToken) load
    Paginate delta -> do
      st <- H.get
      let nextOffset = max 0 (st.query.offset + delta * st.query.limit)
      H.modify_ _ { query = st.query { offset = nextOffset } }
      load

  load = do
    H.modify_ _ { items = Loading }
    q <- H.gets _.query
    res <- getItemsPage q
    H.modify_ _ { items = either Failure Success res }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto p-6 space-y-6") ]
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Items" ]
      , kpiStrip st
      , searchBar st
      , body st
      ]

  kpiStrip st =
    HH.div [ HP.class_ (HH.ClassName "stats shadow") ]
      [ HH.div [ HP.class_ (HH.ClassName "stat") ]
          [ HH.div [ HP.class_ (HH.ClassName "stat-title") ] [ HH.text "Total" ]
          , HH.div [ HP.class_ (HH.ClassName "stat-value") ]
              [ HH.text (totalLabel st.items) ]
          ]
      ]

  totalLabel = case _ of
    Success p -> show p.total
    Loading -> "…"
    Failure _ -> "—"
    NotAsked -> "—"

  searchBar _ =
    HH.input
      [ HP.type_ HP.InputText
      , HP.placeholder "Search items…"
      , HP.class_ (HH.ClassName "input input-bordered w-full max-w-md")
      , HE.onValueInput SetSearch
      ]

  body st = case st.items of
    NotAsked -> HH.div_ []
    Loading -> HH.div [ HP.class_ (HH.ClassName "py-12 flex justify-center") ]
      [ HH.span [ HP.class_ (HH.ClassName "loading loading-spinner loading-lg") ] [] ]
    Failure err -> HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.span_ [ HH.text err ] ]
    Success page ->
      HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
        [ itemsTable page.items
        , pagination st page
        ]

  itemsTable items =
    HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
      [ HH.table [ HP.class_ (HH.ClassName "table table-zebra") ]
          [ HH.thead_
              [ HH.tr_
                  [ HH.th_ [ HH.text "Id" ]
                  , HH.th_ [ HH.text "Name" ]
                  , HH.th_ [ HH.text "Created" ]
                  ]
              ]
          , HH.tbody_ (map renderRow items)
          ]
      ]

  renderRow :: forall w i. Item -> HH.HTML w i
  renderRow i =
    HH.tr_
      [ HH.td [ HP.class_ (HH.ClassName "font-mono text-xs") ]
          [ HH.text (unItemId i.id) ]
      , HH.td_ [ HH.text i.name ]
      , HH.td [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text i.createdAt ]
      ]

  pagination st page =
    HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between") ]
      [ HH.div [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text
              ( "Showing "
                  <> show (st.query.offset + 1)
                  <> "–"
                  <> show (min page.total (st.query.offset + st.query.limit))
                  <> " of "
                  <> show page.total
              )
          ]
      , HH.div [ HP.class_ (HH.ClassName "join") ]
          [ HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm join-item")
              , HP.disabled (st.query.offset == 0)
              , HE.onClick (\_ -> Paginate (-1))
              ]
              [ HH.text "Prev" ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm join-item")
              , HP.disabled (st.query.offset + st.query.limit >= page.total)
              , HE.onClick (\_ -> Paginate 1)
              ]
              [ HH.text "Next" ]
          ]
      ]
