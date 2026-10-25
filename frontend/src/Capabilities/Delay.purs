-- | Capability for delaying execution (e.g. debounce, focus-after-open).
-- | Components use this instead of MonadAff / direct Aff.delay.
module Capabilities.Delay
  ( class MonadDelay
  , delayMs
  ) where

import Prelude

import Control.Monad.Trans.Class (lift)
import Effect.Aff (Milliseconds)
import Halogen (HalogenM)

class Monad m <= MonadDelay m where
  delayMs :: Milliseconds -> m Unit

instance delayHalogenM ::
  MonadDelay m =>
  MonadDelay (HalogenM st act slots msg m) where
  delayMs = lift <<< delayMs
