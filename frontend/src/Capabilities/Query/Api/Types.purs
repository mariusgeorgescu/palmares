-- | DTOs and query inputs for the example `MonadQueryApi` capability.
-- | Rename `Item`/`ItemId`/`ItemsQuery`/`ItemsPage` to your domain.
module Capabilities.Query.Api.Types
  ( ItemId(..)
  , unItemId
  , Item
  , ItemsQuery
  , ItemsPage
  , defaultItemsQuery
  ) where

import Prelude

import Data.Argonaut.Decode (class DecodeJson)
import Data.Argonaut.Encode (class EncodeJson)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype)

-- | Opaque identifier — use a newtype rather than a raw `String` so you
-- | can't accidentally mix it up with other ids in the same function.
newtype ItemId = ItemId String

derive instance Eq ItemId
derive instance Ord ItemId
derive instance Newtype ItemId _
derive newtype instance Show ItemId
derive newtype instance EncodeJson ItemId
derive newtype instance DecodeJson ItemId

unItemId :: ItemId -> String
unItemId (ItemId s) = s

-- | One item returned by the example explorer.
type Item =
  { id :: ItemId
  , name :: String
  , createdAt :: String -- ISO 8601 timestamp
  }

-- | Inputs accepted by `getItemsPage`. Extend with sort, filter, etc. as needed.
type ItemsQuery =
  { limit :: Int
  , offset :: Int
  , search :: Maybe String
  }

defaultItemsQuery :: ItemsQuery
defaultItemsQuery = { limit: 10, offset: 0, search: Nothing }

-- | Page-shaped response: the data the explorer screen needs in one call.
-- | If you find yourself fetching more than one of these per page, fold them
-- | into a single composite DTO instead of spreading RemoteData fields.
type ItemsPage =
  { items :: Array Item
  , total :: Int
  }
