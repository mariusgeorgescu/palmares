-- | Shared monad stack infrastructure for AppM and DemoM.
-- | Both application monads wrap the same RouterT/ReaderT/StoreT/Aff stack;
-- | the only difference is the `MonadQueryApi` instance (Default vs Mock).
module AppBase
  ( AppMBase
  , appBaseNavigate
  , appBaseCurrent
  , appBasePrint
  , appBaseEmitMatched
  , runAppBase
  ) where

import Prelude

import AppEnv (Env)
import Control.Monad.Reader (ReaderT, runReaderT)
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.Router.Class (class MonadNavigate, class MonadRouter, current, emitMatched, navigate, print)
import Halogen.Router.Trans.PushState (RouterT, mkRouter, runRouterT)
import Halogen.Subscription (Emitter)
import Halogen.Store.Monad (StoreT, runStoreT)
import Route (Route)
import Route.Codec (routeCodec)
import Safe.Coerce (coerce)
import Store as Store

type AppMBase = RouterT Route (ReaderT Env (StoreT Store.Action Store.Store Aff))

appBaseNavigate :: MonadNavigate Route AppMBase => Route -> AppMBase Unit
appBaseNavigate r = navigate r

appBaseCurrent :: MonadNavigate Route AppMBase => AppMBase (Maybe Route)
appBaseCurrent = current

appBasePrint :: MonadRouter Route AppMBase => Route -> AppMBase String
appBasePrint r = print r

appBaseEmitMatched :: MonadRouter Route AppMBase => AppMBase (Emitter Route)
appBaseEmitMatched = emitMatched

-- | Run a root component in the shared monad stack, producing an Aff component.
-- | Used by both runAppM and runDemoM (via coerce from their newtype).
runAppBase
  :: forall q i o m
   . Env
  -> Store.Store
  -> H.Component q i o m
  -> Aff (H.Component q i o Aff)
runAppBase env initialStore rootComponent = do
  router <- liftEffect (mkRouter routeCodec)
  runStoreT initialStore Store.reduce
    ( H.hoist (flip runReaderT env)
        ( H.hoist (runRouterT router)
            (coerce rootComponent)
        )
    )
