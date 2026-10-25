-- | Pure mock implementation of `MonadQueryApi` for demo builds and tests.
-- | Coherent: `total` matches the underlying list length, and search is
-- | applied before pagination so the visible total updates as you type.
module Capabilities.Query.Api.Mock
  ( getItemsPageMock
  ) where

import Prelude

import Capabilities.Query.Api.Types (Item, ItemId(..), ItemsPage, ItemsQuery)
import Data.Array (filter, length, slice)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..))
import Data.String as String

mockItems :: Array Item
mockItems =
  [ { id: ItemId "01", name: "Genesis", createdAt: "2025-01-01T12:00:00Z" }
  , { id: ItemId "02", name: "Atlas", createdAt: "2025-01-02T12:00:00Z" }
  , { id: ItemId "03", name: "Beacon", createdAt: "2025-01-03T12:00:00Z" }
  , { id: ItemId "04", name: "Cardano", createdAt: "2025-01-04T12:00:00Z" }
  , { id: ItemId "05", name: "Daedalus", createdAt: "2025-01-05T12:00:00Z" }
  , { id: ItemId "06", name: "Emurgo", createdAt: "2025-01-06T12:00:00Z" }
  , { id: ItemId "07", name: "Foundation", createdAt: "2025-01-07T12:00:00Z" }
  , { id: ItemId "08", name: "Goguen", createdAt: "2025-01-08T12:00:00Z" }
  , { id: ItemId "09", name: "Hydra", createdAt: "2025-01-09T12:00:00Z" }
  , { id: ItemId "10", name: "Iota", createdAt: "2025-01-10T12:00:00Z" }
  , { id: ItemId "11", name: "Juno", createdAt: "2025-01-11T12:00:00Z" }
  , { id: ItemId "12", name: "Kappa", createdAt: "2025-01-12T12:00:00Z" }
  ]

getItemsPageMock :: forall m. Applicative m => ItemsQuery -> m (Either String ItemsPage)
getItemsPageMock query =
  let
    matched = case query.search of
      Nothing -> mockItems
      Just s ->
        let
          needle = String.toLower s
        in
          filter (\i -> String.contains (Pattern needle) (String.toLower i.name)) mockItems
    page = slice query.offset (query.offset + query.limit) matched
  in
    pure (Right { items: page, total: length matched })
