-- | The UI-facing data-fetching seam. Components depend on this type class,
-- | not on HTTP/GraphQL/mock specifics. AppM delegates to `Default`; DemoM to
-- | `Mock`. Add new methods here, mirror in both implementations.
module Capabilities.Query.Api.MonadQueryApi
  ( class MonadQueryApi
  , getItemsPage
  ) where

import Prelude

import Capabilities.Query.Api.Types (ItemsPage, ItemsQuery)
import Control.Monad.Trans.Class (lift)
import Data.Either (Either)
import Halogen (HalogenM)

class Monad m <= MonadQueryApi m where
  -- | Page-shaped query: returns the data the explorer page needs in one call.
  getItemsPage :: ItemsQuery -> m (Either String ItemsPage)

instance monadQueryApiHalogenM ::
  MonadQueryApi m =>
  MonadQueryApi (HalogenM st act slots msg m) where
  getItemsPage = lift <<< getItemsPage
