-- | Implementarea HTTP a lui `MonadQueryGov`. `AppM` deleagă aici.
-- |
-- | Fiecare funcție primește prin `HasGovEnv` doar partea de env de care are nevoie, și trece prin
-- | `Http.getJson` — care e singurul loc care știe cum arată o eroare a acestui API.
module Capabilities.Query.Gov.Default
  ( getStatusDefault
  , getDashboardDefault
  ) where

import Prelude

import Capabilities.Query.Gov.Env (HasGovEnv)
import Capabilities.Query.Gov.Http (ApiError, getJson)
import Capabilities.Query.Gov.Types (DashboardPage, GovStatus)
import Data.Either (Either)
import Effect.Aff.Class (class MonadAff)

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
