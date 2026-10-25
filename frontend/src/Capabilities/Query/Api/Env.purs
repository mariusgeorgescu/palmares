-- | Row constraint pinning the fields the Query.Api capability needs from the
-- | reader env. `AppEnv.Env` satisfies it; the capability never reaches for
-- | unrelated config.
module Capabilities.Query.Api.Env
  ( HasApiEnv
  ) where

type HasApiEnv r = (apiBaseUrl :: String | r)
