{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

-- | The three endpoints that answer \"can this service be trusted right now\".
--
-- They are three questions, not one, and conflating them is how a registry ends up serving stale
-- data confidently:
--
--   * @\/health@ — is the process alive. Touches nothing, so a slow database cannot get the pod
--     restarted.
--   * @\/ready@ — should it receive traffic. Four checks, any of which makes an answer
--     misleading rather than wrong.
--   * @\/status@ — the numbers behind that verdict, plus the protocol parameters a client needs
--     to audit any tally we publish.
module Query.ServiceStatus
  ( getHealthProbe,
    getReadyProbe,
    getStatusQuery,
    startIndexWatch,
  )
where

import Control.Concurrent (ThreadId, forkIO, threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (forever, unless)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVarIO, writeTVar)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks)
import Data.Text (Text, pack)
import Data.Text qualified as T
import Database.Persist.Sql (ConnectionPool)
import Palmares.Admin.ApplySql (declaredIndexes, indexProblems)
import System.IO (hPutStrLn, stderr)
import Palmares.Constants (appVersion)
import Data.Time (diffUTCTime, getCurrentTime)
import Palmares.DomainTypes.Transfer.QueryResponses (AttestationStatus (..), StatusResponse (..))
import Palmares.WebAPI.Envelope (ErrorCode (..))
import Palmares.WebAPI.ServiceProbe (ServiceProbeStatus, alwaysHealthy, mkProbeStatus)
import Query.Gov
  ( Freshness (..),
    ReadyInputs (..),
    epochParamsQuery,
    metricsAsOfEpochQuery,
    readyVerdict,
    syncStatusOf,
  )
import QueryAppMonad (QueryAppContext (..), QueryAppMonad, runRead, throwApi)

-- | Liveness. Deliberately stateless.
getHealthProbe :: QueryAppMonad (ServiceProbeStatus Text)
getHealthProbe = alwaysHealthy (pack appVersion) "query-api"

-- | Readiness, from the cached freshness. 503 with the failing code, or @ready@.
--
-- An empty cache is 'DbUnavailable' rather than a 200: the poll is seeded synchronously at boot,
-- so an empty cache means every poll since has failed.
getReadyProbe :: QueryAppMonad (ServiceProbeStatus Text)
getReadyProbe = do
  (maxLag, inputs) <- readyInputs
  case readyVerdict maxLag inputs of
    Just code -> throwApi code
    Nothing -> mkProbeStatus "ready" (pack appVersion) "query-api"

-- | @GET \/status@: the freshness numbers and the protocol parameters they mean something against.
--
-- @is_ready@ is the same verdict @\/ready@ gives, computed from the same inputs, so a client sees
-- one answer rather than two that can disagree.
getStatusQuery :: QueryAppMonad StatusResponse
getStatusQuery = do
  mf <- currentFreshness
  case mf of
    Nothing -> throwApi DbUnavailable
    Just f -> do
      (maxLag, inputs) <- readyInputs
      mParams <- runRead epochParamsQuery
      case mParams of
        -- No epoch_param row at all means db-sync has not reached Shelley, or is running without
        -- the ledger state that writes it. Either way no tally we publish could be audited, which
        -- is a readiness condition rather than an empty field.
        Nothing -> throwApi IndexerBehind
        Just params -> do
          net <- asks expectedNetwork
          attest <- currentAttest
          amber <- asks amberLag
          metricsEpoch <- runRead metricsAsOfEpochQuery
          missing <- asks missingIndexes >>= liftIO . readTVarIO
          pure
            StatusResponse
              { statusNetwork = net,
                statusGovernance = syncStatusOf f (readyVerdict maxLag inputs == Nothing),
                -- The same 'ReadyInputs' the verdict above is computed from, so a @503
                -- IndexerBehind@ and the number a reader diagnoses it with cannot come from two
                -- different polls. Published AS MEASURED — the projector's distance from db-sync's
                -- cursor — while 'readyVerdict' tests that plus @governance.lag_seconds@, because
                -- the ceiling bounds absolute staleness. So this field is an INPUT to the verdict
                -- and not the quantity compared against the ceiling; both numbers are on this
                -- response, and their sum is what the probe judged.
                statusAttestLagSeconds = readyAttestLagSeconds inputs,
                -- `CS-07`. The same cached row the lag above came from, published whole: the state,
                -- the moment the projector last reported, and its own readiness. @null@ here is the
                -- one thing the lag number could never say — this database has no attestation
                -- pipeline at all.
                statusAttestation = attest,
                -- `GV-23`: four numbers `/ready` already decides with and `/status` did not publish,
                -- so a reader could see the verdict but not the inputs.
                statusDrepDistrEpoch = freshDrepDistrEpoch f,
                statusAmberLagSeconds = amber,
                statusReadyMaxLagSeconds = maxLag,
                statusMetricsAsOfEpoch = metricsEpoch,
                -- `GV-17`: the declared indexes that are absent or unusable. Empty is the healthy
                -- answer and the common one; a non-empty list is why a committee query times out,
                -- published so the cause is readable instead of only the symptom.
                statusMissingIndexes = missing,
                statusEpochParams = params
              }

-- | Watch the declared index set, seeded synchronously so a boot that is missing it says so.
--
-- __Why a watcher and not a query per request.__ The 23 indexes live in @public@, which is
-- db-sync's schema: a db-sync migration or a re-sync from genesis recreates its tables and takes our
-- indexes with them, and nothing in this repository re-applies the file (ADR 0001). query-api then
-- boots perfectly and answers every committee query with a 30 s @503 db_unavailable@, because
-- without @gov_idx_committee_reg_hot@ the CC arm of @palmares.vote@ never finishes. So the fact has
-- to be published — but it changes on the timescale of a migration, not of a request, and @\/status@
-- is a probe a dashboard polls. One poller, one 'TVar', nothing on the hot path: the same shape the
-- freshness poll already uses, and for the same reason.
--
-- Sixty seconds, and no environment variable for it: the quantity being watched changes when an
-- operator runs a migration, and a minute is already far faster than anyone could react. A knob
-- nobody would turn is a knob to document, test and get wrong.
--
-- __Warns, never dies__ (`GV-17`). A reader with no indexes is slow; a reader that refuses to boot
-- is absent, and absent is worse. The remedy is a Job in another repository, so the process that
-- notices cannot be the process that fixes it.
startIndexWatch :: ConnectionPool -> IO (TVar [Text], ThreadId)
startIndexWatch pool = do
  tv <- newTVarIO []
  check tv
  tid <- forkIO . forever $ do
    threadDelay (indexWatchSeconds * 1000000)
    check tv
  pure (tv, tid)
  where
    indexWatchSeconds = 60

    check tv = do
      r <- try (indexProblems pool)
      case r of
        Right problems -> do
          atomically (writeTVar tv (map fst problems))
          unless (null problems) $
            hPutStrLn stderr $
              "[indexes] "
                <> show (length problems)
                <> " of "
                <> show (length declaredIndexes)
                <> " declared indexes are MISSING or INVALID — run `admin apply-indexes`. Committee \
                   \queries will time out until then: "
                <> T.unpack (T.intercalate ", " [n <> " (" <> p <> ")" | (n, p) <- problems])
        -- A catalogue read that fails says nothing about the index set, so the previous answer
        -- stands rather than being replaced by an empty list that reads as "all present".
        Left (e :: SomeException) ->
          hPutStrLn stderr ("[indexes] check failed, keeping the previous value: " <> show e)

currentFreshness :: QueryAppMonad (Maybe Freshness)
currentFreshness = asks freshness >>= liftIO . readTVarIO

currentAttest :: QueryAppMonad (Maybe AttestationStatus)
currentAttest = asks attestLag >>= liftIO . readTVarIO

-- | Gather the configured lag ceiling and the four readiness inputs.
--
-- A missing @drep_distr_epoch@ or @network_name@ counts as failing rather than as unknown: both
-- are subqueries in @palmares.sync_state@ that go NULL when the table behind them is empty, which
-- is exactly the \"db-sync is not ready\" condition the probe exists to report. @-1@ and @\"\"@
-- are chosen so each falls on the failing side of its own check rather than needing a fifth one.
readyInputs :: QueryAppMonad (Int, ReadyInputs)
readyInputs = do
  mf <- currentFreshness
  attest <- currentAttest
  net <- asks expectedNetwork
  maxLag <- asks readyMaxLag
  -- The report's AGE, computed here because the verdict stays pure: a projector that died leaves a
  -- cursor that stops moving, and if db-sync has also stopped there is no lag to notice (`CS-07`).
  now <- liftIO getCurrentTime
  pure . (maxLag,) $ case mf of
    Nothing ->
      ReadyInputs
        { readyDbOk = False,
          readyLagSeconds = 0,
          readyEpochNo = 0,
          readyDrepDistrEpoch = 0,
          readyNetworkName = "",
          readyExpectedNetwork = net,
          -- No database reading at all, so no evidence about the projector either. `readyDbOk`
          -- already fails this case; claiming a projector lag here would be inventing one.
          readyAttestLagSeconds = Nothing,
          readyAttestState = Nothing,
          readyAttestReportAgeSeconds = Nothing
        }
    Just f ->
      ReadyInputs
        { readyDbOk = True,
          readyLagSeconds = freshLagSeconds f,
          readyEpochNo = freshEpoch f,
          readyDrepDistrEpoch = maybe (-1) id (freshDrepDistrEpoch f),
          readyNetworkName = maybe "" id (freshNetworkName f),
          readyExpectedNetwork = net,
          readyAttestLagSeconds = attestSyncLagSeconds <$> attest,
          readyAttestState = attestSyncState <$> attest,
          readyAttestReportAgeSeconds =
            (\a -> floor (diffUTCTime now (attestSyncLastSyncAt a))) <$> attest
        }
