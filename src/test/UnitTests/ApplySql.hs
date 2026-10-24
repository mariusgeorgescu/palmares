{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | The statement splitter, the two files it has to split, and the check that the index file
-- actually landed.
--
-- __Why this is tested at all.__ @CREATE INDEX CONCURRENTLY@ cannot run inside a transaction, so
-- the index and role files cannot be sent as one multi-statement query and must be split. Splitting
-- SQL on semicolons is the kind of thing that works on the file it was written against and breaks
-- on the next line somebody adds — and the failure mode is a half-sent @DO@ block reporting a
-- syntax error that points at the wrong place. So the splitter is pinned here, including against
-- the real files.
--
-- The last case needs a real PostgreSQL, because 'assertIndexesValid' is a question about
-- @pg_class@ and @pg_index@ and there is nothing in it to test without them.
module UnitTests.ApplySql (tests) where

import Data.Char (isAlphaNum)
import Data.List (isInfixOf, nub)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Database.Persist.Sql (rawExecute)
import Palmares.Admin.ApplySql (applyIndexes, assertIndexesValid, declaredIndexes, indexesSql, rolesSql, splitStatements)
import Test.Pg (runPg, withScratchDb)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "SQL statement splitting and the index check"
    [ testCase "plain statements split on the semicolon, and the trailing one is not an empty query" $
        splitStatements "SELECT 1; SELECT 2;" @?= ["SELECT 1", "SELECT 2"],
      -- Every statement in both files is preceded by prose, and that prose has semicolons in it.
      -- A splitter that counted them would send a comment as a statement.
      --
      -- The comment is also DROPPED, not carried into the statement, and that is on purpose: both
      -- files are mostly prose — the index file is 32 lines of reasoning around two statements — so
      -- a failure that echoed "the statement was" would echo the essay. What is sent is the SQL.
      testCase "a semicolon inside a line comment splits nothing, and the comment is dropped" $
        splitStatements "-- first; second; third\nSELECT 1;" @?= ["SELECT 1"],
      testCase "a comment-only tail is dropped rather than sent as an empty query" $
        splitStatements "SELECT 1;\n-- trailing note\n" @?= ["SELECT 1"],
      testCase "a semicolon inside a string literal is not a split" $
        splitStatements "SELECT 'a;b'; SELECT 2;" @?= ["SELECT 'a;b'", "SELECT 2"],
      -- '' is an escaped quote, not close-then-open. Getting this wrong inverts the quoting state
      -- for the rest of the file, so one apostrophe would silently merge every later statement.
      testCase "a doubled quote inside a literal does not end it" $
        splitStatements "SELECT 'it''s; fine'; SELECT 2;" @?= ["SELECT 'it''s; fine'", "SELECT 2"],
      -- Both files guard their CREATE ROLE and their grants in DO blocks, which are full of
      -- semicolons.
      testCase "a dollar-quoted body keeps its semicolons" $
        splitStatements "DO $$ BEGIN a; b; END $$; SELECT 2;"
          @?= ["DO $$ BEGIN a; b; END $$", "SELECT 2"],
      testCase "a TAGGED dollar quote must match its own tag to close" $
        splitStatements "DO $pw$ BEGIN x; $$ y; END $pw$; SELECT 2;"
          @?= ["DO $pw$ BEGIN x; $$ y; END $pw$", "SELECT 2"],
      testCase "an empty input and a semicolon-only input produce no statements" $
        (splitStatements "", splitStatements ";;;", splitStatements "   \n  ") @?= ([], [], []),
      -- ---------------------------------------------------------------------------------------
      -- The real files. These are the cases that matter: the unit cases above are the reasoning,
      -- these are the thing being shipped.
      testCase "the index file splits into statements that are all CREATE INDEX CONCURRENTLY" $ do
        let ss = splitStatements (TE.decodeUtf8 indexesSql)
            creates = filter (T.isInfixOf "CREATE INDEX" . T.toUpper) ss
        assertBool "there is more than one index" (length creates > 1)
        length ss @?= length creates
        -- CONCURRENTLY on every one of them, because these land on db-sync's tables while db-sync
        -- is writing to them and a plain CREATE INDEX takes a lock that stalls the sync.
        filter (not . T.isInfixOf "CONCURRENTLY" . T.toUpper) creates @?= []
        -- IF NOT EXISTS on every one, which is what makes a retried Job converge.
        filter (not . T.isInfixOf "IF NOT EXISTS" . T.toUpper) creates @?= [],
      -- `declaredIndexes` is what `assertIndexesValid` checks, so a statement whose name it cannot
      -- read is an index that silently stops being checked. The first version of that function used
      -- `relname LIKE 'palmares_idx_%'` instead and matched FOUR indexes — none of them from this
      -- file, which names its own `gov_idx_*` and re-creates two of db-sync's `idx_*`. It reported
      -- "all valid" over a set that excluded every index it existed for.
      testCase "every statement in the index file yields a name, so none escapes the validity check" $ do
        let ss = splitStatements (TE.decodeUtf8 indexesSql)
        length declaredIndexes @?= length ss
        assertBool "there are at least 20 indexes" (length declaredIndexes >= 20)
        -- No duplicates: two statements under one name would mean one of them never runs.
        length (nub declaredIndexes) @?= length declaredIndexes
        -- And every name is a bare identifier — no stray punctuation from the word-splitting.
        filter (not . T.all (\c -> c == '_' || isAlphaNum c)) declaredIndexes @?= [],
      -- Over the STATEMENTS, not the raw file: the file's prose says the word (it explains why
      -- 000_schema.sql must never drop an index in `public`), and the comments never reach the
      -- server. Asserting on the raw bytes would make a reasonable comment fail the build.
      testCase "no statement in the index file drops anything, so re-applying cannot lose an index" $
        filter (T.isInfixOf "DROP" . T.toUpper) (splitStatements (TE.decodeUtf8 indexesSql)) @?= [],
      testCase "the roles file splits, and every DO block survives whole" $ do
        let ss = splitStatements (TE.decodeUtf8 rolesSql)
            dos = filter (T.isInfixOf "DO $$" ) ss
        assertBool "the roles file has statements" (length ss > 5)
        -- A DO block that was split would have an unbalanced $$ count.
        mapM_ (\d -> assertEqual (T.unpack (T.take 60 d)) 2 (T.count "$$" d)) dos,
      -- The one thing this file must never contain. The passwords are set by applyRoles, bound as
      -- parameters and quoted server-side; a literal here would be a secret in the repository.
      testCase "the roles file contains no password literal" $
        assertBool
          "no PASSWORD ' in the roles file"
          (not ("PASSWORD '" `isInfixOf` map toUpperC (T.unpack (TE.decodeUtf8 rolesSql)))),
      -- Both roles must be denied CREATE in public: that schema is db-sync's, and a migration of
      -- ours landing there would be a schema change to somebody else's table.
      testCase "the roles file revokes CREATE on public from both roles" $
        let up = map toUpperC (T.unpack (TE.decodeUtf8 rolesSql))
         in ( "REVOKE CREATE ON SCHEMA PUBLIC FROM PALMARES_RO" `isInfixOf` up,
              "REVOKE CREATE ON SCHEMA PUBLIC FROM PALMARES_OWNER" `isInfixOf` up
            )
              @?= (True, True),
      -- A db-sync migration that adds a table must not need a re-GRANT, or a view over that table
      -- fails at read time with a permission error that reads like a bug in the view.
      --
      -- And it must carry NO `FOR ROLE`, which means the current role. A default privilege is scoped
      -- to the role that CREATES the object, and db-sync's role is `dbsync` in the cluster and
      -- `postgres` in experiments/dbsync-preprod — naming either is wrong in the other place, in the
      -- silent direction: every statement succeeds and the privilege covers nothing. (Measured: the
      -- first version named `dbsync` and the file could not be applied to the experiment at all.)
      --
      -- `palmares_attest` is the opposite case and names its role on purpose: attest-sync creates
      -- those tables as `palmares_owner`, a role this file itself creates, so there is nothing to
      -- drift against.
      testCase "the roles file sets default privileges for later tables, under the CURRENT role" $
        let up = map toUpperC (T.unpack (TE.decodeUtf8 rolesSql))
         in ( "ALTER DEFAULT PRIVILEGES IN SCHEMA PUBLIC" `isInfixOf` up,
              "ALTER DEFAULT PRIVILEGES FOR ROLE DBSYNC" `isInfixOf` up,
              "ALTER DEFAULT PRIVILEGES FOR ROLE PALMARES_OWNER IN SCHEMA PALMARES_ATTEST" `isInfixOf` up
            )
              @?= (True, False, True),
      -- Which is only safe because the file refuses to run as anything but that role.
      testCase "the roles file asserts it is running as db-sync's own table owner" $
        let up = map toUpperC (T.unpack (TE.decodeUtf8 rolesSql))
         in ( "PG_GET_USERBYID(RELOWNER)" `isInfixOf` up,
              "CURRENT_USER" `isInfixOf` up,
              "RAISE EXCEPTION" `isInfixOf` up
            )
              @?= (True, True, True),
      -- ---------------------------------------------------------------------------------------
      -- `assertIndexesValid`, in both directions. @GV-17@: it only ever asked PostgreSQL for
      -- INVALID indexes, so on a database holding none of the declared ones it returned `[]` and
      -- `admin apply-indexes` printed "all 23 declared indexes are valid" — a claim about 23
      -- indexes it had never counted, true of the empty set.
      testCase "the index check names a declared index that is absent, and one that is invalid" $
        withScratchDb $ \pool -> do
          -- The file applies to the db-sync skeleton as it stands: 23 statements, 23 indexes.
          -- Against `length declaredIndexes` rather than a literal, so the two cannot disagree.
          applyIndexes pool >>= either assertFailure (@?= length declaredIndexes)
          -- The clean case FIRST. Without it the two assertions below could both pass on a function
          -- that always returns every declared name, and the old function passed this one too — it
          -- is the only case it could pass honestly.
          assertIndexesValid pool >>= (@?= [])
          -- MISSING: the direction that did not exist. Reachable two ways — an operator who read an
          -- INVALID line, dropped the index as instructed and stopped there; and a db-sync migration
          -- that recreates one of its own `public` tables, taking our index with it, with nothing in
          -- this repository re-applying the file afterwards.
          runPg pool $ rawExecute "DROP INDEX public.gov_idx_voting_procedure_tx" []
          -- INVALID: what an interrupted CREATE INDEX CONCURRENTLY leaves behind. A concurrent build
          -- cannot be interrupted on demand, so the catalogue row is falsified directly. The only
          -- write to `pg_index` in this suite, and it lives in a database that is dropped when the
          -- case ends.
          runPg pool $
            rawExecute "UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'public.gov_idx_ocvd_anchor'::regclass" []
          -- And an invalid index that is NOT ours, which must stay db-sync's business to report.
          -- This is what makes the count below an assertion rather than an artefact of the skeleton
          -- happening to carry no other index.
          runPg pool $ rawExecute "CREATE INDEX not_a_declared_index ON public.block (block_no)" []
          runPg pool $
            rawExecute "UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'public.not_a_declared_index'::regclass" []
          problems <- assertIndexesValid pool
          assertBool
            ("the dropped index must be reported MISSING: " <> show problems)
            (any (\p -> T.isInfixOf "gov_idx_voting_procedure_tx" p && T.isInfixOf "MISSING" p) problems)
          assertBool
            ("the falsified index must be reported INVALID: " <> show problems)
            (any (\p -> T.isInfixOf "gov_idx_ocvd_anchor" p && T.isInfixOf "INVALID" p) problems)
          -- Those two and nothing else: `not_a_declared_index` is invalid and must not be reported,
          -- and the other 22 declared indexes are fine. Asserted last so the two messages above
          -- name what went wrong before this one reduces it to a number.
          length problems @?= 2
    ]
  where
    toUpperC c = if c >= 'a' && c <= 'z' then toEnum (fromEnum c - 32) else c
