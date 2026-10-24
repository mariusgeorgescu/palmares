{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- | Which schema attest-sync's projection tables live in.
--
-- __The failure this exists for.__ Every entity in @Palmares.Storage@'s @persistLowerCase@ block is
-- declared unqualified, so @migrateAll@'s @CREATE TABLE@ lands wherever the connection's
-- @search_path@ resolves first. Nothing in the service used to set that path, and
-- @sql/050_roles.sql@ gives @palmares_owner@ @search_path = palmares, palmares_attest, public@ — so
-- the tables landed in @palmares@, the schema @sql/000_schema.sql@ __drops CASCADE on every
-- query-api boot__. One restart of the read API would have deleted the chain-sync state and cost a
-- full Kupo re-sync, with no error anywhere.
--
-- So the assertion is not "the tables exist" but __"the tables survive the drop"__, which is the
-- thing that was actually broken.
module UnitTests.AttestSchema (tests) where

import ChainSyncLogic (SchemaDecision (..), parseReadyMaxLagSlots, readyMaxLagSlotsDefault, schemaDecision)
import ChainsyncAPI (ChainSyncState (..), SyncMetrics (..), probeDatabase, readyVerdict)
import Data.List (sort)
import Data.Text qualified as T
import Database.Persist.Sql (ConnectionPool, Entity (..), Filter, Single (..), rawExecute, rawSql, selectList, toPersistValue)
import Palmares.WebAPI.Envelope (ErrorCode (..))
import Palmares.DomainTypes.Core.Types
  ( attestationClaimedPeriod,
    attestationId,
    attestationIssuerProfileId,
    attestationKind,
    attestationSubjectProfileId,
  )
import Palmares.Storage
  ( AttestSyncState (..),
    AttestationProjection (..),
    attestSchema,
    attestSyncStateRow,
    chainSyncTableNames,
    currentSchemaVersion,
    ensureAttestSchema,
    parsePolicyHistory,
    putAttestSyncState,
    putStoredPolicyHistory,
    readSchemaProbe,
    putAttestationProjection,
    runAttest,
    runMigrations,
  )
import UnitTests.Conversions (sampleAttestation)
import Test.Pg (runPg, withScratchDb)
import Test.Tasty hiding (after) -- see UnitTests.Projections: `after` here is a snapshot, not tasty's
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "attest-sync schema ownership"
    [ testCase "the projections are created in palmares_attest, not in palmares and not in public" $
        withScratchDb $ \pool -> do
          -- The adversarial setup: `palmares` exists AND comes first on the search_path, exactly as
          -- `sql/050_roles.sql` leaves it for `palmares_owner`. Without the pin, this is the
          -- configuration in which the tables go to the wrong place.
          runPg pool $ do
            rawExecute "CREATE SCHEMA IF NOT EXISTS palmares" []
            rawExecute "SET search_path TO palmares, palmares_attest, public" []
          runPg pool ensureAttestSchema
          runAttest pool runMigrations

          attest <- tablesIn pool attestSchema
          assertEqual "every projection table is in palmares_attest" (length chainSyncTableNames) (length attest)
          -- Intersected, not compared to empty: `public` legitimately holds db-sync's own tables
          -- (Test.Pg applies its skeleton there), and `palmares` holds the governance views in a
          -- real deployment. What must be empty is OUR names appearing in either.
          ours <- pure (map T.toLower chainSyncTableNames)
          palmares <- tablesIn pool "palmares"
          public <- tablesIn pool "public"
          assertEqual "none leaked into palmares" [] (filter (`elem` ours) palmares)
          assertEqual "none leaked into public" [] (filter (`elem` ours) public),
      -- The old behaviour, pinned — because `src/test/CLAUDE.md` asks every inherited fix for a test
      -- that fails on it, and here the fix is one `SET LOCAL`, so the only way to show it is
      -- load-bearing is to run the migration WITHOUT it and watch the tables land in the wrong
      -- place. This is what the service did before `runAttest` existed.
      testCase "without the pin the tables land in palmares — which is why runAttest exists" $
        withScratchDb $ \pool -> do
          runPg pool $ do
            rawExecute "CREATE SCHEMA IF NOT EXISTS palmares" []
            rawExecute "SET search_path TO palmares, palmares_attest, public" []
          runPg pool ensureAttestSchema
          -- runPg, not runAttest: no SET LOCAL, so `palmares` is still first on the path.
          runPg pool runMigrations
          wrong <- tablesIn pool "palmares"
          right <- tablesIn pool attestSchema
          assertEqual "every projection table went to palmares" (length chainSyncTableNames) (length wrong)
          assertEqual "and none to palmares_attest" [] right,
      -- The consequence, asserted directly rather than inferred from the schema name.
      testCase "the projections survive DROP SCHEMA palmares CASCADE — a query-api boot" $
        withScratchDb $ \pool -> do
          runPg pool $ rawExecute "CREATE SCHEMA IF NOT EXISTS palmares" []
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          before <- tablesIn pool attestSchema
          assertBool "there are tables to lose" (not (null before))
          -- Verbatim what sql/000_schema.sql's first statement does, on every boot of the read API.
          runPg pool $ rawExecute "DROP SCHEMA IF EXISTS palmares CASCADE" []
          after <- tablesIn pool attestSchema
          assertEqual "every projection table is still there" before after,
      -- runAttest is the only thing standing between the entities and the wrong schema, so what it
      -- sets is worth pinning. SET LOCAL, not SET: the pool reuses connections, and a path left
      -- behind would follow whatever ran next on that connection.
      -- ADR 0007, stance (a) of `OC-09`. These four are about the sentence "a redeploy is a new
      -- registry and the old records remain readable", which was FALSE in the one place that could
      -- falsify it: `attest-sync` wiped every chain-sync table when the stored policy differed.
      --
      -- Pure first, because the column's new meaning is a parse and nothing else.
      testCase "a pre-ADR-0007 row holding ONE policy id parses as a one-element history" $
        parsePolicyHistory "beef" @?= ["beef"],
      testCase "a history parses newest-first, and whitespace is not a policy" $
        parsePolicyHistory " cafe , beef ,, " @?= ["cafe", "beef"],
      -- The round trip, because the history is written by one function and read by another through
      -- raw SQL — the two agreeing is the whole contract, and a comma is all that is between them.
      testCase "a written history reads back in order, through readSchemaProbe's raw SQL" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          runAttest pool (putStoredPolicyHistory ["cafe", "beef"])
          probe <- runAttest pool readSchemaProbe
          case probe of
            Nothing -> assertFailure "the config row should exist after a migration and a write"
            Just (version, stored) -> do
              version @?= currentSchemaVersion
              parsePolicyHistory stored @?= ["cafe", "beef"],
      -- And the behaviour the stance is about: writing a DIFFERENT policy must not cost the rows of
      -- the previous one. `attest-sync` decides whether to wipe from the schema VERSION alone now,
      -- so this pins that a second policy is an addition.
      testCase "a second policy appends to the history and keeps the first" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          runAttest pool (putStoredPolicyHistory ["beef"])
          Just (_, firstStored) <- runAttest pool readSchemaProbe
          -- What Main.hs computes: the new policy at the head, the old ones after it, no duplicates.
          let older = parsePolicyHistory firstStored
              nextHistory = "cafe" : filter (/= "cafe") older
          runAttest pool (putStoredPolicyHistory nextHistory)
          Just (_, secondStored) <- runAttest pool readSchemaProbe
          parsePolicyHistory secondStored @?= ["cafe", "beef"],
            testCase "runAttest pins search_path to palmares_attest, and only for its own transaction" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          [Single (inside :: T.Text)] <- runAttest pool (rawSql "SELECT current_schema()::text" [])
          inside @?= attestSchema
          -- A later transaction on the same pool must not inherit it.
          [Single (outside :: T.Text)] <- runPg pool (rawSql "SELECT current_schema()::text" [])
          assertBool "the path did not leak onto the pooled connection" (outside /= attestSchema),
      -- chainSyncTableNames drives wipeChainSyncTablesRaw, so a name missing from it is a table the
      -- version-bump wipe silently leaves behind for migrateAll to trip over.
      testCase "chainSyncTableNames lists exactly the tables the migration creates" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          created <- tablesIn pool attestSchema
          created @?= sort (map T.toLower chainSyncTableNames),
      -- `CS-07`. The row the projector writes on every tick, and the reason the table has to be in
      -- `chainSyncTableNames`: the wipe drops by that list, so a table missing from it survives a
      -- version bump and `migrateAll` then meets a table it did not create.
      testCase "the projector's liveness row has its own table, with the fields a probe reads" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          cols <- columnsIn pool attestSchema "attest_sync_state"
          let shown = show cols
          mapM_
            (\c -> assertBool (T.unpack c <> " missing: " <> shown) (c `elem` cols))
            ["cursor_slot", "cursor_hash", "kupo_tip_slot", "state", "last_sync_at", "policy_hex_text", "schema_version", "service_version", "last_error"],
      -- And it reads back as what was written: the probe branches on `state`, so a round trip that
      -- lost it would make every readiness answer "following".
      testCase "the liveness row round-trips, and the singleton key keeps it to one row" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          let row st =
                AttestSyncState
                  { attestSyncStateSingleton = True,
                    attestSyncStateCursorSlot = 84233880,
                    attestSyncStateCursorHash = "0f0f",
                    attestSyncStateKupoTipSlot = 84233900,
                    attestSyncStateState = st,
                    attestSyncStateLastSyncAt = read "2026-10-19 08:14:00 UTC",
                    attestSyncStatePolicyHexText = "d9e5c3c0",
                    attestSyncStateSchemaVersion = currentSchemaVersion,
                    attestSyncStateServiceVersion = "0.1.0",
                    attestSyncStateLastError = Nothing
                  }
          runAttest pool (putAttestSyncState (row "syncing"))
          runAttest pool (putAttestSyncState (row "following"))
          got <- runAttest pool attestSyncStateRow
          fmap attestSyncStateState got @?= Just "following"
          -- AND through `runPg`, on the DEFAULT search_path — which is the one that matters, because
          -- it is what query-api's freshness poller runs on: `Query.Gov.runGovRead` pins a statement
          -- timeout and nothing else, and `palmares_attest` is not on that path. The read above
          -- cannot catch a missing schema qualification, since `runAttest` pins the path itself.
          --
          -- It did not catch one: `attestSyncStateRow` read through `getBy`, which persistent
          -- renders unqualified, so on preprod it raised `relation "attest_sync_state" does not
          -- exist`, the poller logged it and kept its previous value, and `/status.attestation`
          -- stayed null for ever beside a projector reporting `following`.
          unqualified <- runPg pool attestSyncStateRow
          fmap attestSyncStateState unqualified @?= Just "following"
          [Single (n :: Int)] <- runAttest pool (rawSql "SELECT count(*)::int FROM attest_sync_state" [])
          n @?= 1,
      -- The schema-version TRIPWIRE, and it is honest about being one rather than a proof.
      --
      -- `currentSchemaVersion` is what makes a deployed attest-sync wipe and re-sync, and a column
      -- added without bumping it leaves a running service migrating a new column onto rows that can
      -- never hold a value for it — the three columns below are read off the datum, so they cannot
      -- be backfilled from the database, only from the chain. Nothing in the suite noticed that
      -- before this test: the version is a bare constant and no assertion mentioned it.
      --
      -- So the count is deliberate. Adding a column fails HERE, next to the version it owes.
      --
      -- All three projection tables, not just the attestation one: v3 added @profile_credential@ to
      -- a table this case did not pin, which is exactly the hole the tripwire exists to close.
      testCase "the projection columns and currentSchemaVersion describe the same schema" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          cols <- columnsIn pool attestSchema "attestation_projection"
          let shown = show cols
          assertBool ("attestation_kind missing: " <> shown) ("attestation_kind" `elem` cols)
          assertBool ("claimed_period_from missing: " <> shown) ("claimed_period_from" `elem` cols)
          assertBool ("claimed_period_to missing: " <> shown) ("claimed_period_to" `elem` cols)
          assertBool ("attestation_credential missing: " <> shown) ("attestation_credential" `elem` cols)
          assertEqual
            ("attestation_projection column count changed — bump currentSchemaVersion with it: " <> shown)
            -- 18 since ADR 0003: `attestation_credential` is where a profile's binding lives now, and
            -- the schema version went 3 -> 4 with it, which is what forces the re-sync.
            18
            (length cols)

          profileCols <- columnsIn pool attestSchema "profile_projection"
          let shownProfile = show profileCols
          assertBool ("profile_credential missing: " <> shownProfile) ("profile_credential" `elem` profileCols)
          assertEqual
            ("profile_projection column count changed — bump currentSchemaVersion with it: " <> shownProfile)
            9
            (length profileCols)

          disputeCols <- columnsIn pool attestSchema "dispute_projection"
          let shownDispute = show disputeCols
          assertBool ("verdict missing: " <> shownDispute) ("verdict" `elem` disputeCols)
          assertBool ("target_attestation_id missing: " <> shownDispute) ("target_attestation_id" `elem` disputeCols)
          -- `stale_after` is asserted BY NAME and not only by the count: it is the dispute's own
          -- deadline, it is absolute (a later oracle reprice cannot move it), and before v6 it was
          -- in the datum and published nowhere — so a client could only compute
          -- `opened_at + the oracle's CURRENT timeout` and be wrong about every dispute opened
          -- before a retiming. A count alone would let it be swapped for something else.
          assertBool ("stale_after missing: " <> shownDispute) ("stale_after" `elem` disputeCols)
          assertEqual
            ("dispute_projection column count changed — bump currentSchemaVersion with it: " <> shownDispute)
            13
            (length disputeCols)

          -- v5 did not change any of the three column sets above: it ADDED a table,
          -- `attest_dead_letter` (CS-01 second half). The three counts therefore stand unchanged and
          -- the version moved, which is the one combination this tripwire has to allow — it pins
          -- "columns and version describe the same schema", not "the version only moves with a
          -- column".
          deadCols <- columnsIn pool attestSchema "attest_dead_letter"
          let shownDead = show deadCols
          assertBool ("last_error missing: " <> shownDead) ("last_error" `elem` deadCols)
          assertBool ("kupo_match missing: " <> shownDead) ("kupo_match" `elem` deadCols)
          assertEqual
            ("attest_dead_letter column count changed — bump currentSchemaVersion with it: " <> shownDead)
            7
            (length deadCols)

          -- v6 moved a column set, which is the other combination: `dispute_projection` gained
          -- `stale_after`, the dispute's own deadline, which was in the datum and published nowhere.
          -- The NOT NULL column is why the version had to move at all — existing rows have no value
          -- for it, so ADR 0007's wipe-and-re-index is the migration, and that same wipe is what
          -- re-reads the block holding the attestation the old authentication gate dropped.
          assertEqual "currentSchemaVersion is the version this column set belongs to" 6 currentSchemaVersion,
      -- The index that must NOT be unique. A credential may be claimed by two profiles (Review
      -- Focus item 2) and the read layer reports that as `contested`; a unique index here would
      -- make ingestion drop the second claim instead, which is the opposite behaviour and would
      -- pass every other test in this module.
      testCase "profile_credential is indexed but not unique, so two profiles may claim one credential" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          idx <- indexesOn pool attestSchema "profile_projection" "profile_credential"
          assertBool ("no index on profile_credential: " <> show idx) (not (null idx))
          assertEqual ("a UNIQUE index on profile_credential: " <> show idx) [] (filter snd idx),
      -- `CS-15`: that index above was the ONLY secondary index in the whole schema — verified on the
      -- live preprod database, where every other entry in `pg_indexes` was a primary key or a unique
      -- constraint. These three are the equality filters the read API and the projector actually run:
      -- `subject_profile_id` serves `GET /attestations?subject=`, the whole of
      -- `GET /profiles/{id}/attestations` AND `Storage.deriveProfileCredential`, which runs that
      -- predicate once per projected profile event; `issuer_profile_id` serves `issuer=`;
      -- `target_attestation_id` serves `disputesFor`, on every `GET /attestations/{id}`.
      --
      -- Asserted through `runMigrations` rather than by reading the SQL, because these are raw
      -- statements on UNQUALIFIED table names: the only thing that puts them in `palmares_attest` is
      -- `runAttest`'s pinned search_path, and a wrong name would surface as a boot-time error on a
      -- deployed service rather than as a compile error here.
      --
      -- NO SCHEMA-VERSION BUMP COMES WITH THEM, which is why they can land on an existing deployment
      -- at its next restart: an index adds no column, so `migrateAll` has nothing to ALTER, the
      -- tripwire above still describes the same schema, and nothing wipes.
      testCase "the three columns every read filters on by equality are indexed, not uniquely" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          let hasPlainIndex table column = do
                idx <- indexesOn pool attestSchema table column
                assertBool ("no index on " <> T.unpack column <> ": " <> show idx) (not (null idx))
                assertEqual ("a UNIQUE index on " <> T.unpack column <> ": " <> show idx) [] (filter snd idx)
          hasPlainIndex "attestation_projection" "subject_profile_id"
          hasPlainIndex "attestation_projection" "issuer_profile_id"
          hasPlainIndex "dispute_projection" "target_attestation_id",
      -- THE WRITE PATH, exercised rather than inspected. `putAttestationProjection` was a
      -- 13-argument positional application and is now 16 named fields — but a review pointed out that
      -- nothing in the suite CALLED it, so a transposition among the three GYAssetClass columns would
      -- have gone green either way, and the commit that made the change claimed otherwise. The
      -- fixture's three distinct asset classes only catch a swap if something actually writes a row.
      testCase "an attestation projection writes every field to its own column" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          runAttest pool (putAttestationProjection 42 "blockhash" "txid" 3 sampleAttestation)
          rows <- runAttest pool (selectList ([] :: [Filter AttestationProjection]) [])
          case rows of
            [Entity _ ap] -> do
              -- The three same-typed columns together, by value. Checked as one tuple so the failure
              -- message shows which pair was swapped rather than just the first mismatch.
              assertEqual
                "id / subject / issuer"
                ( attestationId sampleAttestation,
                  attestationSubjectProfileId sampleAttestation,
                  attestationIssuerProfileId sampleAttestation
                )
                ( attestationProjectionAttestationId ap,
                  attestationProjectionSubjectProfileId ap,
                  attestationProjectionIssuerProfileId ap
                )
              assertEqual "kind" (attestationKind sampleAttestation) (attestationProjectionAttestationKind ap)
              assertEqual
                "claimed period, both columns or neither"
                (fst <$> attestationClaimedPeriod sampleAttestation, snd <$> attestationClaimedPeriod sampleAttestation)
                (attestationProjectionClaimedPeriodFrom ap, attestationProjectionClaimedPeriodTo ap)
              -- The chain pointer, which is the other thing a positional call could have shuffled.
              assertEqual
                "chain pointer"
                (42, "blockhash", "txid", 3)
                ( attestationProjectionCreatedAtSlot ap,
                  attestationProjectionCreatedAtHash ap,
                  attestationProjectionCreatedTxId ap,
                  attestationProjectionCreatedOutputIndex ap
                )
            _ -> assertFailure ("expected exactly one row, got " <> show (length rows)),
      -- A period is both bounds or neither, and the writer is what guarantees it: it sets the two
      -- columns from one `Maybe` pair, so they cannot disagree.
      testCase "an attestation with no claimed period writes both columns null" $
        withScratchDb $ \pool -> do
          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          runAttest pool (putAttestationProjection 1 "h" "t" 0 sampleAttestation {attestationClaimedPeriod = Nothing})
          rows <- runAttest pool (selectList ([] :: [Filter AttestationProjection]) [])
          case rows of
            [Entity _ ap] ->
              (attestationProjectionClaimedPeriodFrom ap, attestationProjectionClaimedPeriodTo ap)
                @?= (Nothing, Nothing)
            _ -> assertFailure ("expected exactly one row, got " <> show (length rows)),
      -- THE READINESS THRESHOLD, pure. `READY_MAX_LAG_SLOTS` was a bare 1200 in `ChainSyncLogic`,
      -- so `/ready` reported green up to twenty minutes behind the chain (one preprod slot is one
      -- second) and a Kubernetes probe could not be tuned per environment. Three cases, because the
      -- parse is the whole of the new behaviour and the default is a published number.
      testCase "an unset READY_MAX_LAG_SLOTS keeps the measured default of 1200 slots" $ do
        parseReadyMaxLagSlots Nothing @?= 1200
        -- Pinned against the constant too, so a future change to the default has to come here and
        -- to the README row in the same commit rather than silently moving the probe.
        parseReadyMaxLagSlots Nothing @?= readyMaxLagSlotsDefault,
      testCase "a set READY_MAX_LAG_SLOTS overrides the default" $
        parseReadyMaxLagSlots (Just "60") @?= 60,
      -- Not fail-closed, unlike KUPO_URL and PG_CONN_STR beside it: this value decides the colour of
      -- a probe and nothing the projector reads or writes, so a typo leaves the documented default
      -- rather than refusing to boot. Zero and negatives are rejected for the same reason the
      -- function's comment gives — a healthy projector sits a slot behind the tip between blocks.
      testCase "a malformed, empty, zero or negative READY_MAX_LAG_SLOTS falls back to the default" $ do
        parseReadyMaxLagSlots (Just "twenty minutes") @?= readyMaxLagSlotsDefault
        parseReadyMaxLagSlots (Just "") @?= readyMaxLagSlotsDefault
        parseReadyMaxLagSlots (Just "1200 slots") @?= readyMaxLagSlotsDefault
        parseReadyMaxLagSlots (Just "0") @?= readyMaxLagSlotsDefault
        parseReadyMaxLagSlots (Just "-1") @?= readyMaxLagSlotsDefault,
      -- THE WIPE, `CS-06` / `TD-19`. `needWipe` was one comparison and nothing asked: a schema
      -- version bump dropped all eight chain-sync tables with `DROP TABLE … CASCADE`, and the only
      -- warning was a `putStrLn` already scrolling past in a container log. Pure, because the
      -- decision is two integer comparisons and a parse — no database can be made to produce these
      -- four cases on demand, which is the same reason query-api's `readyVerdict` is pure.
      testCase "a fresh database and a matching stored version both migrate, destroying nothing" $ do
        schemaDecision Nothing currentSchemaVersion Nothing @?= SchemaMigrate
        schemaDecision Nothing 6 (Just 6) @?= SchemaMigrate
        -- A confirmation left behind in a manifest changes neither, and that expiry is why the value
        -- is a VERSION and not `1` or `true`: it authorises the one projection it names, and once
        -- that wipe has run the stored version IS the current one, so the leftover value authorises
        -- nothing and the next bump has to ask again.
        schemaDecision (Just "6") 6 (Just 6) @?= SchemaMigrate,
      testCase "an older stored version refuses to wipe unless the confirmation names it" $ do
        schemaDecision Nothing 6 (Just 5) @?= SchemaRefuseWipe 5 6
        schemaDecision (Just "") 6 (Just 5) @?= SchemaRefuseWipe 5 6
        -- A boolean-shaped value is not a confirmation: nothing in it says WHICH projection the
        -- operator agreed to destroy, which is the whole property that makes a leftover value safe.
        schemaDecision (Just "1") 6 (Just 5) @?= SchemaRefuseWipe 5 6
        schemaDecision (Just "true") 6 (Just 5) @?= SchemaRefuseWipe 5 6
        -- Nor is the version this BINARY writes — the number an operator reads off an image tag. It
        -- names the schema that is not being destroyed.
        schemaDecision (Just "6") 6 (Just 5) @?= SchemaRefuseWipe 5 6
        -- The version being destroyed, which is the number the refusal prints.
        schemaDecision (Just "5") 6 (Just 5) @?= SchemaWipe,
      -- THE DOWNGRADE, which did not even reach the old comparison's true branch: `needWipe` tested
      -- `storedVersion < currentSchemaVersion` only, so a binary OLDER than its database fell
      -- through to `migrateAll` against a shape it does not know — ALTERing columns under rows a
      -- newer writer wrote. That is data corruption rather than a failed boot, so it is a refusal,
      -- and the wipe confirmation is deliberately not an override for it: authorising a wipe is not
      -- the same act as authorising a migration in the wrong direction.
      testCase "a newer stored version refuses outright, and the wipe confirmation is no override" $ do
        schemaDecision Nothing 5 (Just 6) @?= SchemaRefuseDowngrade 6 5
        schemaDecision (Just "6") 5 (Just 6) @?= SchemaRefuseDowngrade 6 5
        schemaDecision (Just "5") 5 (Just 6) @?= SchemaRefuseDowngrade 6 5,
      -- THE VERDICT, pure, one case per dependency this service has. Each row below is a shape in
      -- which the process is running perfectly and `/ready` used to answer 200.
      testCase "every dependency failure is a 503 with its own code, and catching up is not one" $ do
        let healthy =
              SyncMetrics
                { smLocalTip = 137170034,
                  smBlockchainTip = 137170034,
                  smLastSyncTime = read "2026-10-24 14:47:15 UTC",
                  smDbReady = True,
                  smMigrationsComplete = True,
                  smChainSyncState = UpToDate
                }
            -- 1200 slots and a tick five seconds old: a projector at the tip, mid-sleep.
            verdict = readyVerdict 1200 5
        assertEqual "at the tip" Nothing (verdict healthy)
        assertEqual
          "a slot or two behind between blocks stays green"
          Nothing
          (verdict healthy {smChainSyncState = Behind False, smLocalTip = 137170032})
        assertEqual
          "way behind, but ticking: catching up is the job, not a dependency failure"
          Nothing
          (verdict healthy {smChainSyncState = Behind True, smLocalTip = 137168000})
        assertEqual "the database did not answer" (Just DbUnavailable) (verdict healthy {smDbReady = False})
        assertEqual
          "the schema is not this binary's"
          (Just NotReady)
          (verdict healthy {smMigrationsComplete = False})
        assertEqual
          "Kupo's tip is below our cursor, so the index is the thing that is behind"
          (Just IndexerBehind)
          (verdict healthy {smChainSyncState = Ahead})
        assertEqual
          "our cursor names a block that is not on the chain"
          (Just NotReady)
          (verdict healthy {smChainSyncState = UpToDateButDifferentBlockHash}),
      -- THE POST-WIPE RE-SYNC, which is the shape `/ready` answered 503 on for its whole duration.
      -- `main` boots with `Behind True` and the cursor at slot 0 after a wipe, so this record is
      -- what every probe sees from the first tick until the backfill has closed a gap of a hundred
      -- million slots — hours. A Kubernetes rollout gated on this probe never completes, on exactly
      -- the deploy that bumped the schema version and caused the wipe. Measured: a bump wiped and
      -- re-indexed and `/ready` was red throughout.
      --
      -- Green now, because the projector is working; the gap is still published in the same
      -- response (`local_tip`, `blockchain_tip`, `is_way_behind`) and still reddens query-api's
      -- `/ready`, which is the probe in front of the data.
      testCase "a post-wipe re-sync is READY: the projector is catching up, which is the job" $ do
        let resyncing =
              SyncMetrics
                { smLocalTip = 0,
                  smBlockchainTip = 137182904,
                  smLastSyncTime = read "2026-10-24 14:47:15 UTC",
                  smDbReady = True,
                  smMigrationsComplete = True,
                  smChainSyncState = Behind True
                }
        -- A tick five seconds old: `fetchingMatches` writes `smLastSyncTime` after every applied
        -- window, so a running backfill keeps this fresh however far from the tip it is.
        assertEqual "mid-re-sync, ticking" Nothing (readyVerdict 1200 5 resyncing)
        -- And the one thing that must still be red in the middle of a re-sync: Kupo gone. The
        -- tick-age guard is what separates "catching up" from "stopped", and it is the only guard
        -- that can, because every slot number here is indistinguishable from the stalled case.
        assertEqual "mid-re-sync, and Kupo stopped answering" (Just IndexerBehind) (readyVerdict 1200 1801 resyncing)
        -- The two that stay red whatever the gap: both say the cursor itself is unanswerable.
        assertEqual
          "mid-re-sync, cursor above Kupo's tip"
          (Just IndexerBehind)
          (readyVerdict 1200 5 resyncing {smChainSyncState = Ahead})
        assertEqual
          "mid-re-sync, cursor on a fork"
          (Just NotReady)
          (readyVerdict 1200 5 resyncing {smChainSyncState = UpToDateButDifferentBlockHash}),
      -- THE KUPO CASE, and the reason the tick's age had to become a signal. `getBlockchainTip`
      -- retries inside the tick, so with Kupo unreachable nothing below it runs: the metrics MVar is
      -- never touched and `chain_sync_state`, `local_tip` and `blockchain_tip` all stand at their
      -- last good values. The record below is EXACTLY that shape — a perfect `UpToDate` at the tip —
      -- and it is the one the old handler answered 200 on for as long as Kupo stayed down.
      testCase "a frozen tick is red even though every number in it says UpToDate — Kupo is gone" $ do
        let frozen =
              SyncMetrics
                { smLocalTip = 137170034,
                  smBlockchainTip = 137170034,
                  smLastSyncTime = read "2026-10-24 14:47:15 UTC",
                  smDbReady = True,
                  smMigrationsComplete = True,
                  smChainSyncState = UpToDate
                }
        -- The loop sleeps ten seconds when up to date and ten more between Kupo retries, so 1800
        -- seconds is on the order of a hundred missed ticks.
        assertEqual "no word from Kupo for half an hour" (Just IndexerBehind) (readyVerdict 1200 1800 frozen)
        -- And the threshold governs it, so an operator who tightens the probe tightens this too.
        assertEqual "the same tick, under a 60-slot ceiling" (Just IndexerBehind) (readyVerdict 60 61 frozen)
        assertEqual "and inside it, still green" Nothing (readyVerdict 60 59 frozen),
      -- db_ready / migrations_complete, AGAINST A REAL DATABASE. They were `True` literals set in
      -- `main` before the loop started and reported for the life of the process, so the probe
      -- claimed a healthy database after the postmaster had restarted underneath it. The four
      -- answers below are the four a live check can give, and not one of them is reachable from a
      -- boot-time boolean.
      testCase "db_ready and migrations_complete are measured, not remembered" $
        withScratchDb $ \pool -> do
          -- No schema at all: the one query raises `relation does not exist`, which reads as
          -- unreachable. Documented on `probeDatabase` — separating "up but unmigrated" from "down"
          -- would cost a second round trip to change neither the verdict nor the remedy.
          absent <- probeDatabase pool
          assertEqual "nothing migrated yet" (False, False) absent

          runPg pool ensureAttestSchema
          runAttest pool runMigrations
          -- The table exists and `putStoredPolicyHistory` has not run: the database is up and the
          -- boot sequence did not finish.
          unmigrated <- probeDatabase pool
          assertEqual "tables but no config row" (True, False) unmigrated

          runAttest pool (putStoredPolicyHistory ["beef"])
          ready <- probeDatabase pool
          assertEqual "the schema this binary writes" (True, True) ready

          -- A database restored from an older dump under a running projector. This is the case the
          -- incident would have shown and the one a literal can never produce: the connection is
          -- fine, and the schema is not one this binary migrates to.
          runAttest pool (rawExecute "UPDATE chain_sync_config SET schema_version = 1" [])
          stale <- probeDatabase pool
          assertEqual "an older schema under a running projector" (True, False) stale
    ]
  where
    columnsIn :: ConnectionPool -> T.Text -> T.Text -> IO [T.Text]
    columnsIn pool schema table =
      map unSingle
        <$> runPg
          pool
          ( rawSql
              "SELECT column_name::text FROM information_schema.columns \
              \WHERE table_schema = ? AND table_name = ? ORDER BY column_name"
              [toPersistValue schema, toPersistValue table]
          )

    -- Indexes on @table@ whose definition mentions @column@, each paired with whether it is UNIQUE.
    -- Read off @pg_indexes@ rather than @pg_constraint@ because a unique CONSTRAINT and a unique
    -- INDEX both land here, and either one would be the bug.
    indexesOn :: ConnectionPool -> T.Text -> T.Text -> T.Text -> IO [(T.Text, Bool)]
    indexesOn pool schema table column =
      map (\(Single n, Single u) -> (n, u))
        <$> runPg
          pool
          ( rawSql
              "SELECT indexname::text, (indexdef LIKE '%UNIQUE%') FROM pg_indexes \
              \WHERE schemaname = ? AND tablename = ? AND indexdef LIKE '%' || ? || '%'"
              [toPersistValue schema, toPersistValue table, toPersistValue column]
          )

    tablesIn :: ConnectionPool -> T.Text -> IO [T.Text]
    tablesIn pool schema =
      map unSingle
        <$> runPg
          pool
          ( rawSql
              "SELECT table_name::text FROM information_schema.tables \
              \WHERE table_schema = ? AND table_type = 'BASE TABLE' ORDER BY table_name"
              [toPersistValue schema]
          )
