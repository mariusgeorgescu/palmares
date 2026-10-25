-- | Capability for logging messages. Implement for your application monad
-- | (e.g. console, external service); components use this instead of Console.log.
module Capabilities.LogMessages
  ( class LogMessages
  , LogLevel(..)
  , logMessage
  , logDebug
  , logInfo
  , logWarning
  , logError
  ) where

import Prelude

import Control.Monad.Trans.Class (lift)
import Halogen (HalogenM)

data LogLevel
  = Debug
  | Info
  | Warning
  | Error

derive instance Eq LogLevel
derive instance Ord LogLevel

instance Show LogLevel where
  show = case _ of
    Debug -> "DEBUG"
    Info -> "INFO"
    Warning -> "WARNING"
    Error -> "ERROR"

class Monad m <= LogMessages m where
  logMessage :: LogLevel -> String -> m Unit

instance logMessagesHalogenM ::
  ( LogMessages m
  ) =>
  LogMessages (HalogenM st act slots msg m) where
  logMessage level msg = lift (logMessage level msg)

logDebug :: forall m. LogMessages m => String -> m Unit
logDebug = logMessage Debug

logInfo :: forall m. LogMessages m => String -> m Unit
logInfo = logMessage Info

logWarning :: forall m. LogMessages m => String -> m Unit
logWarning = logMessage Warning

logError :: forall m. LogMessages m => String -> m Unit
logError = logMessage Error
