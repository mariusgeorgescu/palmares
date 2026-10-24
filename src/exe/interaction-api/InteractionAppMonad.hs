{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

-- | Application monad and context for the interaction API server.
-- Wraps a 'ReaderT' over Servant's 'Handler' with access to auth and
-- transaction-building context, plus standardized error handling.
module InteractionAppMonad where

import Palmares.Constants qualified as Constants
import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import Control.Exception (SomeException, displayException, fromException, try)
import Control.Monad.Except
import Control.Monad.Reader
import Data.Aeson (encode, object, (.=))
import Data.Text hiding (elem, reverse, take)
import Data.Time (NominalDiffTime, UTCTime, defaultTimeLocale, diffUTCTime, getCurrentTime)
import Data.Time.Format (formatTime)
import Data.Typeable (cast)
import System.IO.Unsafe (unsafePerformIO)
import GeniusYield.TxBuilder.Errors (GYTxMonadException (..))
import GeniusYield.Types
import Servant
import Palmares.TxBuilding.Context
import Palmares.TxBuilding.Exceptions
  ( ApiFailure (..),
    TxBuildingException,
    classifyWriteFailure,
    txBuildingExceptionCode,
    txBuildingExceptionToHttpStatus,
  )
import Palmares.TxBuilding.Interactions (Interaction)
import Palmares.TxBuilding.Operations (ensureDeployedScriptsAreReady)
import Palmares.TxBuilding.Transactions (interactionToHexEncodedCBOR, submitTx)
import Palmares.WebAPI.Auth (AuthContext)
import Palmares.WebAPI.Envelope (ErrorCode (..))
import Palmares.WebAPI.Errors (mkServantErr, mkServantErrBody)
import Palmares.WebAPI.ServiceProbe (ServiceProbeStatus (..))

------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------

-- | Shared environment for all interaction-API request handlers.
data InteractionAppContext = InteractionAppContext
  { authContext :: AuthContext, -- ^ Basic-auth credentials for protected routes
    txBuildingContext :: TxBuildingContext -- ^ Provider, deployed scripts, and network config for building transactions
  }

newtype InteractionAppMonad a = InteractionAppMonad {unInteractionAppMonad :: ReaderT InteractionAppContext Servant.Handler a}
  deriving (Functor, Applicative, Monad)

-- | Run an 'InteractionAppMonad' computation with the given context.
runInteractionAppMonad :: InteractionAppContext -> InteractionAppMonad a -> Servant.Handler a
runInteractionAppMonad ctx app = runReaderT (unInteractionAppMonad app) ctx

instance MonadIO InteractionAppMonad where
  liftIO :: IO a -> InteractionAppMonad a
  liftIO = InteractionAppMonad . liftIO

instance MonadReader InteractionAppContext InteractionAppMonad where
  ask :: InteractionAppMonad InteractionAppContext
  ask = InteractionAppMonad ask

  local :: (InteractionAppContext -> InteractionAppContext) -> InteractionAppMonad a -> InteractionAppMonad a
  local f (InteractionAppMonad app) = InteractionAppMonad (local f app)

-- | Build a 'ServerError' for a 'TxBuildingException' with a structured JSON
-- body @{"code": <constructor>, "message": <human text>}@. Clients match on the
-- stable @code@; @message@ stays available for display/fallback text matching.
txBuildingServantErr :: Int -> TxBuildingException -> ServerError
txBuildingServantErr status txEx =
  mkServantErrBody status $ encode $ object ["code" .= txBuildingExceptionCode txEx, "message" .= displayException txEx]

-- | Run an IO action in the TxBuilding context with standardized error handling.
--
-- __Catches 'SomeException', and that is the fix.__ The patterns here used to type @try@ to
-- 'GYTxMonadException', so a provider's HTTP failure or a submission rejected by the node was not
-- caught at all: it reached Warp's default handler, which answers @text\/plain@ with no @code@ under
-- a 500 (@OF-05@). Every exception now gets a JSON body with a code a client can match on, and the
-- table that decides which one is 'classifyWriteFailure' — pure, total, and tested.
runWithTxErrorHandling :: IO a -> InteractionAppMonad a
runWithTxErrorHandling action = InteractionAppMonad $ do
  res <- liftIO $ try @SomeException action
  case res of
    Right ok -> pure ok
    Left ex -> do
      let ApiFailure {..} = classifyWriteFailure ex
      -- The full exception is LOGGED and the client gets the classified message: a script's trace
      -- codes are a protocol fact and travel, but a provider URL or a wallet address in a balancing
      -- error is not the client's business.
      liftIO $ putStrLn $ "Write failure (" <> show afStatus <> ") [" <> afCode <> "]: " <> show ex
      throwError $
        mkServantErrBody afStatus $
          encode $ object ["code" .= afCode, "message" .= afMessage]

-- | Build a transaction from an 'Interaction' and return its hex-encoded CBOR.
buildInteractionApp :: Interaction -> InteractionAppMonad String
buildInteractionApp inter = do
  InteractionAppContext {..} <- ask
  runWithTxErrorHandling $ runReaderT (interactionToHexEncodedCBOR inter) txBuildingContext

-- | Submit a signed transaction and return its transaction ID.
submitTxApp :: GYTx -> InteractionAppMonad GYTxId
submitTxApp tx = do
  InteractionAppContext {..} <- ask
  runWithTxErrorHandling $ runReaderT (submitTx tx) txBuildingContext

-- | Poll whether a transaction has been confirmed on-chain.
-- Performs a single check attempt and returns 'True' if confirmed, 'False' otherwise.
pollTxConfirmation :: GYTxId -> InteractionAppMonad Bool
pollTxConfirmation txId = do
  InteractionAppContext {..} <- ask
  let providers = ctxProviders (providerCtx txBuildingContext)
  -- Single attempt, 100ms delay, 1 confirmation
  let params = GYAwaitTxParameters 1 100000 1
  -- 'SomeException' and not 'GYTxMonadException' — @OF-05@(c). Atlas signals "I waited and it is
  -- still not there" with its own 'GYAwaitTxException', which is a standalone newtype and NOT a
  -- 'GYTxMonadException', so the one exception this function exists to absorb was the one it did not
  -- catch: a transaction that simply had not confirmed yet produced a 500. The smoke script survived
  -- only because `curl -f` reads that 500 as "not yet".
  res <- liftIO $ try @SomeException $ gyAwaitTxConfirmed providers params txId
  case res of
    Right () -> return True
    Left _ -> return False

------------------------------------------------------------------------------------------------

-- * Caching the unauthenticated probe routes

------------------------------------------------------------------------------------------------

-- | How long @\/ready@ and @\/status@ reuse a chain read before taking another (@OF-13@).
--
-- __Why five seconds and not less.__ Both routes are public, unauthenticated and cost five
-- @deployedScriptsProblems@ @utxoAtTxOutRef@ calls each — @\/status@ two oracle reads on top. Measured
-- against a local node+Kupo on preprod, 20 sequential requests: @\/ready@ 67 ms and @\/status@ 69 ms
-- per request, against 6 ms for @\/health@, which touches nothing. So ONE @curl@ loop on one
-- connection sustained 15 requests a second, which is 75 provider queries a second off @\/ready@ and
-- about 100 off @\/status@ — with no credential, and multiplying by however many connections the
-- caller opens. The bound has to come from the server, because nothing stops the asking. At this TTL
-- the same loop costs one fan-out every five seconds: 1 query a second off @\/ready@, 1.4 off
-- @\/status@, whatever the request rate.
--
-- __And not more.__ Every fact these routes report is on chain: a reference script resolving, the
-- oracle's pause flag, the oracle's parameters. None of them can change faster than a block, and
-- Cardano's mean block interval is ~20 s — so any TTL comfortably inside one block costs an operator
-- no freshness they could have had. Five seconds is inside it by a factor of four, keeps a
-- @periodSeconds: 10@ readiness probe always reading a fresh value, and still collapses an unbounded
-- request rate to at most one fan-out per route per five seconds.
--
-- The cost of the TTL is that a deployment which just broke still answers @ready@ for up to five
-- seconds. A readiness probe with any @failureThreshold@ above 1 absorbs that; a probe with
-- @failureThreshold: 1@ and @periodSeconds: 1@ would not, and does not exist in this deployment.
probeCacheTtl :: NominalDiffTime
probeCacheTtl = 5

-- | Reuse the cell's value while it is younger than 'probeCacheTtl', otherwise run @action@ and
-- store what it returns, timestamped.
--
-- __'modifyMVar' and not an 'Data.IORef.IORef'__, so the lock is held across @action@: with an
-- 'Data.IORef.IORef' every request that arrives during a cold miss starts its own fan-out, and the
-- amplification is then bounded by the attacker's connection count rather than by the TTL. Here the
-- second concurrent request waits for the first and reads its answer, so the bound is absolute. The
-- price is that one slow provider call delays the probe routes for its duration instead of
-- multiplying — which on a readiness probe is the behaviour you want, since a provider that cannot
-- answer is the thing being reported.
--
-- @action@ must not throw: both call sites hand it an already-'try'-wrapped read, so a failure is a
-- 'Left' that gets cached like any other answer — a dead provider must not be re-queried five times
-- per request either. 'modifyMVar' would restore the cell on an exception anyway.
cachedFor :: MVar (Maybe (UTCTime, a)) -> IO a -> IO a
cachedFor cell action = modifyMVar cell $ \cached -> do
  now <- getCurrentTime
  case cached of
    Just (at, a) | diffUTCTime now at < probeCacheTtl -> return (cached, a)
    _ -> do
      a <- action
      return (Just (now, a), a)

-- | @\/ready@'s cell.
--
-- Top-level and 'unsafePerformIO', the same idiom (and the same @NOINLINE@ obligation) as
-- @Test.Pg.scratchCounter@: without the pragma GHC may inline the 'unsafePerformIO' and hand each
-- use site its own cell, which is exactly the sharing this exists for.
--
-- __ponytail: process-global, one server per process.__ The alternative is a field on
-- 'InteractionAppContext', which is constructed in @Main.hs@ — a file this change does not own, and
-- one a positional constructor would break. If this process ever runs two contexts, the cell moves
-- into the context and this becomes wrong rather than merely blunt.
readyProbeCache :: MVar (Maybe (UTCTime, Either SomeException ()))
readyProbeCache = unsafePerformIO (newMVar Nothing)
{-# NOINLINE readyProbeCache #-}

-- | Readiness probe: verify that all deployed validator scripts are available on-chain.
--
-- Cached for 'probeCacheTtl'. The TIMESTAMP is not: a cached @ready@ still reports the current
-- time, because the claim being made is "as of now, this service can build", and the cache only
-- bounds how recently that was checked.
checkDeployedScriptsAreReady :: InteractionAppMonad (ServiceProbeStatus Text)
checkDeployedScriptsAreReady = do
  InteractionAppMonad $ do
    InteractionAppContext {..} <- ask
    let queryScriptsReady = runReaderT ensureDeployedScriptsAreReady (deployedScriptsCtx txBuildingContext)
    -- @SomeException@, not @GYTxMonadException@. The pattern match below monomorphised this `try`,
    -- so a provider HTTP failure, a dropped connection or a timeout — none of which is a
    -- `GYTxMonadException` — was not caught at all: it propagated out of the Handler to Warp, which
    -- answers `text/plain` "Something went wrong" under a 500. On a readiness probe the truth is a
    -- 503, and `mkServantErr 503 NotReady` was already on the next branch. `OF-05`'s own note said
    -- to catch `SomeException` at the handler; `runWithTxErrorHandling` got that and this did not.
    res <- liftIO $ cachedFor readyProbeCache $ try @SomeException $ runQuery (providerCtx txBuildingContext) queryScriptsReady
    now <- liftIO getCurrentTime
    case res of
      Left ex ->
        case fromException ex of
          Just (GYApplicationException appE)
            | Just txEx <- cast appE -> do
                let status = txBuildingExceptionToHttpStatus txEx
                liftIO $ putStrLn $ "checkDeployedScriptsAreReady TxBuildingException (" <> show status <> ") [" <> txBuildingExceptionCode txEx <> "]: " <> displayException txEx
                throwError $ txBuildingServantErr status txEx
          _ -> do
            liftIO $ putStrLn $ "checkDeployedScriptsAreReady GYTxMonadException: " <> show ex
            throwError $ mkServantErr 503 NotReady
      Right () ->
        return $
          ServiceProbeStatus
            { status = "ready" :: Text,
              service = "interaction-api" :: Text,
              version = pack Constants.appVersion,
              timestamp = pack $ formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now
            }
