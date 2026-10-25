-- | Production application monad: AppM = RouterT Route (ReaderT Env (StoreT Store Aff)).
-- | RouterT provides navigation and route subscription; ReaderT provides Env;
-- | StoreT provides global mutable state; the `MonadQueryApi` instance delegates
-- | to the HTTP `Default` implementation.
module AppM
  ( AppM
  , runAppM
  ) where

import Prelude

import AppBase (appBaseNavigate, appBaseCurrent, appBasePrint, appBaseEmitMatched, runAppBase)
import AppEnv (Env)
import Capabilities.Delay (class MonadDelay)
import Capabilities.DomEvent (class MonadDomEvent)
import Capabilities.LogMessages (class LogMessages)
import Capabilities.Query.Gov.Default
  ( getDRepDetailDefault
  , getDRepExplorerDefault
  , getDashboardDefault
  , getGovActionDetailDefault
  , getGovActionsDefault
  , getStatusDefault
  , getVotesDefault
  )
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov)
import Cardano.Capabilities.Transaction.MonadInteraction (class MonadInteraction)
import Cardano.Capabilities.Wallet.MonadCIP30 (class MonadCIP30)
import Control.Monad.Error.Class (class MonadThrow)
import Control.Monad.Reader (class MonadReader, ReaderT, mapReaderT)
import Control.Monad.Reader.Class (class MonadAsk, ask, local)
import Control.Monad.Trans.Class (lift)
import Effect.Aff (Aff, Error, delay)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Console (log) as Console
import Halogen as H
import Halogen.Router.Class (class MonadNavigate, class MonadRouter)
import Halogen.Router.Trans.PushState (RouterT(..))
import Halogen.Store.Monad (class MonadStore, StoreT)
import Route (Route)
import Store as Store
import Web.Event.Event (preventDefault)

newtype AppM a = AppM (RouterT Route (ReaderT Env (StoreT Store.Action Store.Store Aff)) a)

runAppM
  :: forall q i o
   . Env
  -> Store.Store
  -> H.Component q i o AppM
  -> Aff (H.Component q i o Aff)
runAppM = runAppBase

derive newtype instance functorAppM :: Functor AppM
derive newtype instance applyAppM :: Apply AppM
derive newtype instance applicativeAppM :: Applicative AppM
derive newtype instance bindAppM :: Bind AppM
derive newtype instance monadAppM :: Monad AppM
derive newtype instance monadEffectAppM :: MonadEffect AppM
derive newtype instance monadAffAppM :: MonadAff AppM
derive newtype instance monadStoreAppM :: MonadStore Store.Action Store.Store AppM
derive newtype instance monadErrorAppM :: MonadThrow Error AppM

-- RouterT does not export MonadReader Env; lift from inner ReaderT.
instance monadReaderAppM :: MonadReader Env AppM where
  local f (AppM (RouterT m)) = AppM (RouterT (mapReaderT (local f) m))

-- RouterT provides MonadAsk (Maybe Route); we need Env, so lift ReaderT's ask.
instance monadAskAppM :: MonadAsk Env AppM where
  ask = AppM (lift ask)

-- Marker instances unlock the standalone functions from cardano-capabilities.
instance MonadCIP30 AppM
instance MonadInteraction AppM

instance MonadNavigate Route AppM where
  navigate r = AppM (appBaseNavigate r)
  current = AppM appBaseCurrent

instance MonadRouter Route AppM where
  print r = AppM (appBasePrint r)
  emitMatched = AppM appBaseEmitMatched

instance LogMessages AppM where
  logMessage level msg = liftEffect (Console.log ("[" <> show level <> "] " <> msg))

instance MonadDelay AppM where
  delayMs = liftAff <<< delay

instance MonadDomEvent AppM where
  preventDefaultEvent = liftEffect <<< preventDefault

instance MonadQueryGov AppM where
  getStatus = ask >>= getStatusDefault
  getDashboard = ask >>= getDashboardDefault
  getDRepExplorer filters = ask >>= \env -> getDRepExplorerDefault env filters
  getDRepDetail drepId = ask >>= \env -> getDRepDetailDefault env drepId
  getGovActions filters = ask >>= \env -> getGovActionsDefault env filters
  getGovActionDetail actionId = ask >>= \env -> getGovActionDetailDefault env actionId
  getVotes filters = ask >>= \env -> getVotesDefault env filters
