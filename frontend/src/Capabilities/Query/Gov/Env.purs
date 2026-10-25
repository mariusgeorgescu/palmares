-- | Rândul care fixează ce are nevoie capabilitatea de citire din env. `AppEnv.Env` îl satisface;
-- | capabilitatea nu ajunge niciodată la configurație care nu o privește — în particular nu la
-- | `interactionBaseUrl`, pentru că suprafața de citire nu scrie nimic.
module Capabilities.Query.Gov.Env
  ( HasGovEnv
  ) where

type HasGovEnv r = (queryBaseUrl :: String | r)
