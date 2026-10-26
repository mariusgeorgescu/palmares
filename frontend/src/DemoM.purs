-- | Demo application monad: same stack as AppM but `MonadQueryApi` uses Mock
-- | (no real API). Use for demo builds and tests.
module DemoM
  ( DemoM
  , runDemoM
  ) where

import Prelude

import AppBase (appBaseNavigate, appBaseCurrent, appBasePrint, appBaseEmitMatched, runAppBase)
import AppEnv (Env)
import Capabilities.Delay (class MonadDelay)
import Capabilities.DomEvent (class MonadDomEvent)
import Capabilities.LogMessages (class LogMessages)
import Capabilities.Interaction.MonadInteract (class MonadInteract)
import Capabilities.Interaction.Mock (buildFlowMock, interactionStatusMock, submitSignedMock, txStatusMock)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov)
import Capabilities.Wallet.Governance (class MonadGovWallet)
import Capabilities.Wallet.GovernanceMock (connectGovernanceMock)
import Capabilities.Query.Gov.Mock
  ( getDRepDetailMock
  , getDRepExplorerMock
  , getDashboardMock
  , getGovActionDetailMock
  , getGovActionsMock
  , getFormulasMock
  , getSposMock
  , getCommitteeMock
  , getWithdrawalsMock
  , getDelegationsMock
  , getActivityMock
  , getProfileMock
  , getProfilesMock
  , getAttestationsMock
  , getDisputesMock
  , getRegistrySummaryMock
  , getStatusMock
  , getVotesMock
  , searchAllMock
  )
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

newtype DemoM a = DemoM (RouterT Route (ReaderT Env (StoreT Store.Action Store.Store Aff)) a)

runDemoM
  :: forall q i o
   . Env
  -> Store.Store
  -> H.Component q i o DemoM
  -> Aff (H.Component q i o Aff)
runDemoM = runAppBase

derive newtype instance functorDemoM :: Functor DemoM
derive newtype instance applyDemoM :: Apply DemoM
derive newtype instance applicativeDemoM :: Applicative DemoM
derive newtype instance bindDemoM :: Bind DemoM
derive newtype instance monadDemoM :: Monad DemoM
derive newtype instance monadEffectDemoM :: MonadEffect DemoM
derive newtype instance monadAffDemoM :: MonadAff DemoM
derive newtype instance monadStoreDemoM :: MonadStore Store.Action Store.Store DemoM
derive newtype instance monadErrorDemoM :: MonadThrow Error DemoM

instance monadReaderDemoM :: MonadReader Env DemoM where
  local f (DemoM (RouterT m)) = DemoM (RouterT (mapReaderT (local f) m))

instance monadAskDemoM :: MonadAsk Env DemoM where
  ask = DemoM (lift ask)

instance MonadCIP30 DemoM
instance MonadInteraction DemoM

instance MonadNavigate Route DemoM where
  navigate r = DemoM (appBaseNavigate r)
  current = DemoM appBaseCurrent

instance MonadRouter Route DemoM where
  print r = DemoM (appBasePrint r)
  emitMatched = DemoM appBaseEmitMatched

instance LogMessages DemoM where
  logMessage level msg = liftEffect (Console.log ("[" <> show level <> "] " <> msg))

instance MonadDelay DemoM where
  delayMs = liftAff <<< delay

instance MonadDomEvent DemoM where
  preventDefaultEvent = liftEffect <<< preventDefault

instance MonadQueryGov DemoM where
  getStatus = getStatusMock
  getDashboard = getDashboardMock
  getDRepExplorer = getDRepExplorerMock
  getDRepDetail = getDRepDetailMock
  getGovActions = getGovActionsMock
  getGovActionDetail = getGovActionDetailMock
  getVotes = getVotesMock
  searchAll = searchAllMock
  getFormulas = getFormulasMock
  getSpos = getSposMock
  getCommittee = getCommitteeMock
  getWithdrawals = getWithdrawalsMock
  getDelegations = getDelegationsMock
  getActivity = getActivityMock
  getProfile = getProfileMock
  getProfiles = getProfilesMock
  getAttestations = getAttestationsMock
  getDisputes = getDisputesMock
  getRegistrySummary = getRegistrySummaryMock

instance monadInteractDemoM :: MonadInteract DemoM where
  buildFlow = buildFlowMock
  submitSigned = submitSignedMock
  txStatus = txStatusMock
  interactionStatus = interactionStatusMock

instance monadGovWalletDemoM :: MonadGovWallet DemoM where
  connectGovernance = connectGovernanceMock
