{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Main where

import ChainSyncLogic
import ChainSyncServer (startProbeServer)
import ChainsyncAPI (ChainSyncState (..), SyncMetrics (..))
import Palmares.Constants
import Control.Concurrent.Extra
import Control.Monad.Extra
import Control.Monad.IO.Class
import Control.Monad.Logger (runStdoutLoggingT)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time
import Database.Persist.Postgresql (ConnectionString, createPostgresqlPool)
import Database.Persist.Sql (runSqlPool)
import GeniusYield.GYConfig (GYCoreConfig (..))
import GeniusYield.Types (mintingPolicyIdFromText)
import Palmares.ChainSync.KupoClient (KupoCheckpoint (..))
import Palmares.Storage
  ( currentSchemaVersion,
    ensureAttestSchema,
    putStoredPolicyHistory,
    parsePolicyHistory,
    readSchemaProbe,
    rollbackTo,
    runAttest,
    runMigrations,
    wipeChainSyncTablesRaw,
  )
import System.Environment (lookupEnv)
import System.Exit (die)
import Text.Printf
import Text.Read (readMaybe)
import Palmares.TxBuilding.Context
import Palmares.Utils (decodeConfigEnvOrFile)
import Palmares.WebAPI.CORS (getCorsConfigFromEnv)
import Palmares.WebAPI.Utils
import System.IO (BufferMode (LineBuffering), hSetBuffering, stdout)


-- | Show only the host and dbname fields of a Postgres DSN, hiding the password.
redactConnStr :: String -> String
redactConnStr s =
  unwords [kv | kv <- words s, let k = takeWhile (/= '=') kv, k `elem` ["host", "dbname", "port"]]

main :: IO ()
main = do
  -- Line-buffer stdout: GHC block-buffers it when it is not a TTY, which is the case under
  -- Docker and Kubernetes, so boot lines would sit in a buffer while the service already serves.
  -- Measured on query-api, fixed in all three servers at once.
  hSetBuffering stdout LineBuffering

  port <- getPortFromEnvOrDefault 8084
  corsCfg <- getCorsConfigFromEnv

  -- FAIL-CLOSED, like PG_CONN_STR beside it and for the same reason: a wrong configuration that
  -- works is worse than one that stops. This defaulted to `http://localhost:1442` on the one
  -- service whose whole job is reading the chain — and that port is wrong for every deployment in
  -- this repo. Unset in a container it meant an invisible retry loop against nothing, with
  -- `/health` still reporting the last good state.
  kupoUrl <- liftIO $ requireEnv "KUPO_URL"
  connStr <- liftIO requirePgConnStr

  let connBS :: ConnectionString = TE.encodeUtf8 (T.pack connStr)
  pool <- runStdoutLoggingT $ createPostgresqlPool connBS 16

  atlasConfig <- maybe (die "Atlas configuration failed") return =<< decodeConfigEnvOrFile "ATLAS_CORE_CONFIG" defaultAtlasCoreConfig
  let networkId = cfgNetworkId atlasConfig

  deployedScriptsContext <- maybe (die "Deployed validators configuration failed") return =<< decodeConfigEnvOrFile @DeployedScriptsContext "DEPLOYED_VALIDATORS_CONFIG" defaultTxBuildingContextFile
  let policyHexText = T.pack $ printf "%s" (getMintingPolicyHash deployedScriptsContext)

  -- The same hash, typed, because the projection path needs it to authenticate every output it
  -- indexes (inherited fix #3) and the Kupo pattern needs it as text. Parsed once, here, so a
  -- deployed-config hash that is not a policy id is a boot failure and not a per-match surprise.
  ourPolicy <-
    either
      (\e -> die ("Deployed minting policy hash is not a policy id: " <> e))
      return
      (mintingPolicyIdFromText policyHexText)

  -- Probe the existing schema BEFORE migrating. Wipe (drop) the chain-sync tables if the schema
  -- version changed AND the operator confirmed it, so migrateAll only CREATEs fresh tables and never
  -- runs an incompatible in-place ALTER (varchar->bigint / ADD COLUMN NOT NULL) Postgres would reject.
  -- The schema first, and the path pinned to it for everything after: these tables are declared
  -- unqualified, so without this they land in `palmares`, which query-api drops on every boot.
  runSqlPool ensureAttestSchema pool
  mProbe <- runAttest pool readSchemaProbe

  -- A POLICY CHANGE NO LONGER WIPES — ADR 0007, stance (a) of `OC-09`.
  --
  -- It used to: `storedPolicy /= policyHexText` dropped every chain-sync table, so a redeploy
  -- destroyed the previous registry's records. That is precisely what the stance promises not to do
  -- — "a redeploy is a new registry and the old records remain readable" — and the promise would
  -- have been false in the one place that could falsify it.
  --
  -- Nothing has to be migrated for the old rows to stay readable: every id is stored as a
  -- `GYAssetClass`, which is @policy.name@, so each row already says which registry it belongs to
  -- and a reader unions deployments for free. What changes is only that the table keeps them.
  --
  -- A SCHEMA VERSION BUMP STILL WIPES, and that is a different question: those tables would need an
  -- in-place ALTER that Postgres rejects (varchar->bigint, ADD COLUMN NOT NULL), so a fresh CREATE
  -- is the only safe path and the records are re-indexed from the chain afterwards.
  --
  -- IT NO LONGER WIPES UNASKED, and a DOWNGRADE no longer migrates — `CS-06` / `TD-19`. The decision
  -- is 'ChainSyncLogic.schemaDecision', which also documents why the confirmation gates the wipe
  -- rather than the boot: a guard that refuses to START would crash-loop every ordinary restart and
  -- be pasted permanently into the manifest, which is the defect it was added to prevent.
  mConfirmWipe <- lookupEnv confirmWipeEnvVar
  needWipe <- case schemaDecision mConfirmWipe currentSchemaVersion (fst <$> mProbe) of
    SchemaMigrate -> pure False
    SchemaWipe -> pure True
    SchemaRefuseDowngrade stored current ->
      die
        ( "REFUSING TO START: this database is at attest-sync schema version "
            <> show stored
            <> " and this binary writes version "
            <> show current
            <> ".\nA DOWNGRADE IS NOT A MIGRATION: migrateAll would ALTER a schema this binary does"
            <> " not know, under rows a newer writer wrote — corruption rather than a failed boot."
            <> "\nDeploy attest-sync at schema version "
            <> show stored
            <> " or newer. To re-index this registry from the chain under THIS binary instead, drop"
            <> " the palmares_attest schema by hand first: "
            <> confirmWipeEnvVar
            <> " authorises a wipe, not a downgrade."
        )
    SchemaRefuseWipe stored current ->
      die
        ( "REFUSING TO WIPE: this database is at attest-sync schema version "
            <> show stored
            <> " and this binary writes version "
            <> show current
            <> ".\nThose tables cannot be migrated in place (varchar->bigint, ADD COLUMN NOT NULL),"
            <> " so the next step would DROP every chain-sync table in palmares_attest and re-index"
            <> " the whole registry from the chain — hours, during which every projection is"
            <> " incomplete.\nIf that is what you mean, set "
            <> confirmWipeEnvVar
            <> "="
            <> show stored
            <> " — the version being destroyed — and start again."
        )
  when needWipe $ do
    putStrLn
      ( "Schema version changed; dropping chain-sync tables before migration ("
          <> confirmWipeEnvVar
          <> " authorises destroying the stored version)."
      )
    runAttest pool wipeChainSyncTablesRaw
  runAttest pool runMigrations

  -- The history this database holds, newest first. The current policy goes to the head unless it is
  -- already there, so a restart is idempotent and a redeploy appends.
  let previousPolicies = if needWipe then [] else maybe [] (parsePolicyHistory . snd) mProbe
      policyHistory = policyHexText : filter (/= policyHexText) previousPolicies
  runAttest pool (putStoredPolicyHistory policyHistory)
  case filter (/= policyHexText) previousPolicies of
    [] -> return ()
    older ->
      putStrLn
        ( "Policy history: indexing "
            <> T.unpack policyHexText
            <> " and KEEPING the records of "
            <> show (length older)
            <> " earlier registry/registries ("
            <> T.unpack (T.intercalate ", " older)
            <> "). Their records stay readable and stop being updated: a redeploy is a new registry."
        )

  fetchBatchSize <- do
    mb <- lookupEnv "FETCH_BATCH_SIZE"
    pure $ max 1 (maybe (10_000_000 :: Integer) id (mb >>= readMaybe))

  rollbackMargin <- do
    mb <- lookupEnv "ROLLBACK_MARGIN"
    pure $ max 1 (maybe defaultRollbackMargin id (mb >>= readMaybe))

  -- One number, read once here and used in both places that measure staleness: the tip comparison
  -- below computes the `is_way_behind` a probe PUBLISHES with it, and `readyVerdict` measures the
  -- tick's age against it. Read it twice and a client could see `is_way_behind: false` beside a 503.
  -- The gap itself no longer reddens `/ready` — see `readyVerdict` — but the two must still agree
  -- about what "way behind" means, because the body and the verdict are read together.
  maxLagSlots <- readyMaxLagSlotsFromEnv

  initialTip <- getLocalTip pool

  now <- getCurrentTime
  metricsVar <-
    newMVar
      SyncMetrics
        { smLocalTip = ck_slot_no initialTip,
          smBlockchainTip = ck_slot_no initialTip,
          smLastSyncTime = now,
          -- PLACEHOLDERS, and no longer the answer: every probe measures these two itself
          -- (`ChainsyncAPI.probeDatabase`) and overwrites them before serving. They used to be
          -- `True` here and that was the whole of the claim — a boot-time literal reported for the
          -- life of the process, which is how this service's probe reported a healthy database
          -- while the postmaster it needed had restarted underneath it. `False` because nothing has
          -- been measured yet at this point.
          smDbReady = False,
          smMigrationsComplete = False,
          smChainSyncState = Behind True -- by default we are way behind
        }

  -- Start probe server
  void $ forkIO $ startProbeServer corsCfg port pool maxLagSlots metricsVar

  let matchPattern = policyHexText <> ".*"
  putStrLn "Starting chain-sync ..."
  putStrLn "Kupo: configured"
  putStrLn ("Pattern: " <> T.unpack matchPattern)
  putStrLn ("Postgres: " <> redactConnStr connStr)
  -- Both jobs of the one number, because the boot line used to say "Ready when within N slots" and
  -- that is no longer what /ready decides: catching up is green, a silent Kupo is not.
  putStrLn
    ( "Way behind beyond: "
        <> show maxLagSlots
        <> " slots (reported); /ready red after "
        <> show maxLagSlots
        <> "s without an answer from Kupo (READY_MAX_LAG_SLOTS)"
    )

  forever $ do
    blockchainTip <- getBlockchainTip pool ourPolicy kupoUrl
    localTip <- getLocalTip pool
    -- `getBlockchainTip` has just returned, so Kupo answered: THIS is the moment the projector last
    -- had evidence about the chain, and `smLastSyncTime` is what `/ready` measures the tick's age
    -- against. It used to be written only per applied fetch window, which is why the field could
    -- not be used as a liveness signal: on preprod a block arrives about every twenty seconds, so
    -- an idle tick left it standing still while the service was perfectly healthy. Written here it
    -- advances every ten seconds whatever the chain is doing, and freezes exactly when Kupo stops
    -- answering — because then the retry loop above never returns and nothing below it runs.
    tickTime <- getCurrentTime
    let chainSyncState = evaluateChainSyncStateWith maxLagSlots localTip blockchainTip
    modifyMVar_ metricsVar $ \m -> pure m {smLocalTip = ck_slot_no localTip, smBlockchainTip = ck_slot_no blockchainTip, smLastSyncTime = tickTime, smChainSyncState = chainSyncState}
    liftIO $ putStrLn ("Local tip      : " <> show (ck_slot_no localTip))
    liftIO $ putStrLn ("Blockchain tip : " <> show (ck_slot_no blockchainTip))

    -- CS-02: ask whether our cursor's own block is still on the chain, BEFORE trusting the
    -- slot comparison. A short fork reads as plain `Behind` — local slot below the tip — and that
    -- path never looks at a header, so the orphaned block's projections stayed and a replacement
    -- block below our cursor was never fetched again.
    cursor <- verifyCursor kupoUrl localTip
    case cursor of
      CursorOrphaned ancestor -> do
        -- Kupo's ancestor is a point on the chain it is serving now, so it is a PRECISE target.
        -- The margin stays as the fallback for the case where Kupo knows nothing at or below our
        -- slot, which is the shape the old code always assumed.
        let target = maybe (max 0 (ck_slot_no blockchainTip - rollbackMargin)) ck_slot_no ancestor
        liftIO $
          putStrLn
            ( "FORK: the cursor's block is not on Kupo's chain; rolling back to "
                <> show target
                <> maybe " (margin fallback: Kupo has no point at or below the cursor)" (const " (Kupo's newest surviving point)") ancestor
            )
        runAttest pool (rollbackTo networkId ourPolicy target)
        updateLocalTip pool (fromMaybe (KupoCheckpoint target "") ancestor)
        reportSyncState pool ourPolicy "rolled_back" (fromMaybe (KupoCheckpoint target "") ancestor) (ck_slot_no blockchainTip) Nothing
        liftIO $ threadDelay 1000000
      CursorOnChain -> case chainSyncState of
        UpToDate -> do
          liftIO $ putStrLn "Chain is up to date"
          -- `following` is claimed HERE and nowhere else: the cursor equals Kupo's tip, which is the
          -- only state in which a reader may treat a projection as complete.
          reportSyncState pool ourPolicy "following" localTip (ck_slot_no blockchainTip) Nothing
          liftIO $ putStrLn "Sleeping for 10 seconds"
          liftIO $ threadDelay 10000000
        Behind _isWayBehind -> do
          liftIO $ putStrLn "Chain is behind"
          liftIO $ putStrLn "Fetching matches"
          -- Before the fetch, so the row says `syncing` for the whole of a pass that may run for
          -- hours. `fetchingMatches` then advances the slot per window.
          reportSyncState pool ourPolicy "syncing" localTip (ck_slot_no blockchainTip) Nothing
          fetchingMatches metricsVar kupoUrl matchPattern ourPolicy networkId pool (ck_slot_no localTip) (ck_slot_no blockchainTip) fetchBatchSize
          updateLocalTip pool blockchainTip
          reportSyncState pool ourPolicy "following" blockchainTip (ck_slot_no blockchainTip) Nothing
        Ahead -> do
          liftIO $ putStrLn "Chain is ahead"
          let rollbackSlot = max 0 (ck_slot_no blockchainTip - rollbackMargin)
          runAttest pool (rollbackTo networkId ourPolicy rollbackSlot)
          updateLocalTip pool (KupoCheckpoint rollbackSlot "")
          reportSyncState pool ourPolicy "rolled_back" (KupoCheckpoint rollbackSlot "") (ck_slot_no blockchainTip) Nothing
          liftIO $ putStrLn ("Rolled back to slot " <> show rollbackSlot <> "; will re-sync forward")
        UpToDateButDifferentBlockHash -> do
          liftIO $ putStrLn "Same slot, different block hash; rolling back with margin"
          let rollbackSlot = max 0 (ck_slot_no blockchainTip - rollbackMargin)
          runAttest pool (rollbackTo networkId ourPolicy rollbackSlot)
          updateLocalTip pool (KupoCheckpoint rollbackSlot "")
          reportSyncState pool ourPolicy "rolled_back" (KupoCheckpoint rollbackSlot "") (ck_slot_no blockchainTip) Nothing
