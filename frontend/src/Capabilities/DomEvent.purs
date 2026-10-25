-- | Capability for DOM event handling (e.g. preventDefault).
-- | Components use this instead of MonadEffect / direct Web.Event.
module Capabilities.DomEvent
  ( class MonadDomEvent
  , preventDefaultEvent
  ) where

import Prelude

import Control.Monad.Trans.Class (lift)
import Halogen (HalogenM)
import Web.Event.Event (Event)

class Monad m <= MonadDomEvent m where
  preventDefaultEvent :: Event -> m Unit

instance domEventHalogenM ::
  MonadDomEvent m =>
  MonadDomEvent (HalogenM st act slots msg m) where
  preventDefaultEvent = lift <<< preventDefaultEvent
