-- | Implementarea HTTP a lui `MonadQueryGov`. `AppM` deleagă aici.
-- |
-- | Fiecare funcție primește prin `HasGovEnv` doar partea de env de care are nevoie, și trece prin
-- | `Http.getJson` — care e singurul loc care știe cum arată o eroare a acestui API.
module Capabilities.Query.Gov.Default
  ( getStatusDefault
  , getDashboardDefault
  , getDRepExplorerDefault
  , getDRepDetailDefault
  , getGovActionsDefault
  , getGovActionDetailDefault
  , getVotesDefault
  ) where

import Prelude

import Capabilities.Query.Gov.Env (HasGovEnv)
import Capabilities.Query.Gov.Http (ApiError, getJson)
import Capabilities.Query.Gov.Types
  ( DRepDetail
  , DRepExplorerPage
  , DashboardPage
  , GovActionDetail
  , GovActionPage
  , GovStatus
  , VotePage
  )
import Data.Either (Either)
import Effect.Aff.Class (class MonadAff)
import Route.GovQueries
  ( DRepFilters
  , GovActionFilters
  , VoteFilters
  , encodePathSegment
  , renderDRepFilters
  , renderGovActionFilters
  , renderVoteFilters
  )

getStatusDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> m (Either ApiError GovStatus)
getStatusDefault env = getJson (env.queryBaseUrl <> "/status")

getDashboardDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> m (Either ApiError DashboardPage)
getDashboardDefault env = getJson (env.queryBaseUrl <> "/pages/dashboard")

getDRepExplorerDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> DRepFilters
  -> m (Either ApiError DRepExplorerPage)
getDRepExplorerDefault env filters =
  getJson (env.queryBaseUrl <> "/pages/drep-explorer" <> renderDRepFilters filters)

getDRepDetailDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> String
  -> m (Either ApiError DRepDetail)
getDRepDetailDefault env drepId =
  getJson (env.queryBaseUrl <> "/pages/drep/" <> encodePathSegment drepId)

getGovActionsDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> GovActionFilters
  -> m (Either ApiError GovActionPage)
getGovActionsDefault env filters =
  getJson (env.queryBaseUrl <> "/gov-actions" <> renderGovActionFilters filters)

getGovActionDetailDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> String
  -> m (Either ApiError GovActionDetail)
getGovActionDetailDefault env actionId =
  getJson (env.queryBaseUrl <> "/pages/gov-action/" <> encodePathSegment actionId)

getVotesDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> VoteFilters
  -> m (Either ApiError VotePage)
getVotesDefault env filters = getJson (env.queryBaseUrl <> "/votes" <> renderVoteFilters filters)
