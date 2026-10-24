{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

-- | Applying the SQL that the service's boot DDL cannot: indexes and roles.
--
-- __Why this is not @Query.Views.applySchemaSql@.__ That one wraps every file in ONE transaction,
-- which is exactly right for the views — a syntax error in the last file leaves the previous schema
-- serving. These two files cannot be applied that way:
--
--   * __@CREATE INDEX CONCURRENTLY@ cannot run inside a transaction block.__ PostgreSQL refuses it
--     with 25001, and a multi-statement simple query is implicitly a transaction, so the file
--     cannot even be sent in one go. Concurrently is not optional here: these indexes land on
--     db-sync's own tables while db-sync is writing to them, and a plain @CREATE INDEX@ takes a
--     lock that stalls the sync.
--   * __roles need the superuser db-sync owns__, which the service deliberately does not have, and
--     they are applied once per database rather than once per boot.
--
-- So the files are split into statements and sent one at a time, in autocommit. A failure part way
-- through leaves the statements before it applied — which is the right shape for both files, since
-- both are written to be re-runnable (@IF NOT EXISTS@ throughout) and a retried Job must converge.
module Palmares.Admin.ApplySql
  ( -- * The files
    indexesSql,
    rolesSql,

    -- * Applying them
    splitStatements,
    applySqlAutocommit,
    applyIndexes,
    declaredIndexes,
    assertIndexesValid,
    indexProblems,
    applyRoles,
  )
where

import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import Data.Char (isAlphaNum, isSpace)
import Data.FileEmbed (embedFile, makeRelativeToProject)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Database.Persist.Sql
  ( ConnectionPool,
    Single (..),
    SqlPersistT,
    rawExecute,
    rawSql,
    runSqlPoolNoTransaction,
    toPersistValue,
  )

-- | @sql\/indexes\/001_gov_indexes.sql@, embedded.
--
-- Embedded rather than read from disk for the same reason the view files are: the admin image has
-- no repository checkout, and an index set that lives next to the binary cannot drift from it.
indexesSql :: ByteString
indexesSql = $(makeRelativeToProject "sql/indexes/001_gov_indexes.sql" >>= embedFile)

-- | @sql\/050_roles.sql@, embedded.
rolesSql :: ByteString
rolesSql = $(makeRelativeToProject "sql/050_roles.sql" >>= embedFile)

-- ---------------------------------------------------------------------------------------------

-- | Split a SQL file into statements on top-level semicolons.
--
-- __Not @T.splitOn \";\"@__, which both files would break. They contain semicolons inside
-- @DO $$ … $$@ bodies and inside string literals, and a splitter that ignored those would send
-- half a @DO@ block and report a syntax error pointing at the wrong line.
--
-- So the state tracked is the minimum that makes the split correct for these files and for any SQL
-- a person is likely to add to them:
--
--   * a single-quoted literal, where @''@ is an escaped quote and not a close-then-open;
--   * a dollar-quoted body, @$$ … $$@ or @$tag$ … $tag$@, where the tag must match to close;
--   * a @--@ line comment, which runs to the newline — and which matters because every statement in
--     these files is preceded by prose containing semicolons.
--
-- Block comments (@\/* … *\/@) are NOT handled, deliberately: neither file uses them, and a
-- half-implemented nesting rule is worse than a stated limitation. Empty statements are dropped,
-- so a trailing semicolon or a comment-only tail does not produce an empty query.
splitStatements :: Text -> [Text]
splitStatements = filter (not . isBlank) . map T.strip . go "" Normal
  where
    isBlank t = T.null t || T.all isSpace t || T.isPrefixOf "--" (T.strip t) && not (T.isInfixOf "\n" t)

    go acc st rest = case T.uncons rest of
      Nothing -> [acc]
      Just (c, more) -> case st of
        Normal
          | c == ';' -> acc : go "" Normal more
          | c == '\'' -> go (T.snoc acc c) InQuote more
          | c == '-', Just ('-', _) <- T.uncons more -> go acc InComment more
          | c == '$', Just (tag, afterTag) <- dollarTag rest -> go (acc <> tag) (InDollar tag) afterTag
          | otherwise -> go (T.snoc acc c) Normal more
        InQuote
          | c == '\'', Just ('\'', m2) <- T.uncons more -> go (acc <> "''") InQuote m2
          | c == '\'' -> go (T.snoc acc c) Normal more
          | otherwise -> go (T.snoc acc c) InQuote more
        InComment
          | c == '\n' -> go (T.snoc acc c) Normal more
          | otherwise -> go acc InComment more
        InDollar tag
          | T.isPrefixOf tag rest -> go (acc <> tag) Normal (T.drop (T.length tag) rest)
          | otherwise -> go (T.snoc acc c) (InDollar tag) more

    -- `$$` or `$tag$`, returning the delimiter and what follows it.
    dollarTag t = case T.uncons t of
      Just ('$', r) ->
        let (tag, r') = T.span (\ch -> ch /= '$' && (ch == '_' || ch `notElem` (" \t\n(),;'\"" :: String))) r
         in case T.uncons r' of
              Just ('$', r'') -> Just ("$" <> tag <> "$", r'')
              _ -> Nothing
      _ -> Nothing

-- | The splitter's state.
data SplitState = Normal | InQuote | InComment | InDollar Text

-- ---------------------------------------------------------------------------------------------

-- | Send each statement of a file on its own, in autocommit, stopping at the first failure.
--
-- @runSqlPoolNoTransaction@ and not @runSqlPool@: the latter opens a transaction, which is the one
-- thing @CONCURRENTLY@ cannot be inside.
--
-- Stopping at the first failure rather than carrying on is deliberate. Both files are ordered —
-- roles before the grants that name them, the schema before its default privileges — so a statement
-- that failed usually makes the ones after it meaningless, and a Job that reports the first error
-- is a Job whose log names the problem instead of burying it in twenty more.
applySqlAutocommit :: ConnectionPool -> Text -> ByteString -> IO (Either String Int)
applySqlAutocommit pool label sql = go 0 (splitStatements (TE.decodeUtf8 sql))
  where
    go n [] = pure (Right n)
    go n (s : ss) = do
      r <- try (runSqlPoolNoTransaction (rawExecute s []) pool Nothing)
      case r of
        Left (e :: SomeException) ->
          pure . Left $
            T.unpack label
              <> ": statement "
              <> show (n + 1)
              <> " failed: "
              <> show e
              <> "\n--- the statement was ---\n"
              <> T.unpack (T.take 400 s)
        Right () -> go (n + 1) ss

-- | Apply @sql\/indexes\/001_gov_indexes.sql@.
--
-- Every statement in it is @CREATE INDEX CONCURRENTLY IF NOT EXISTS@, so applying it to a database
-- that already has the indexes is a no-op that costs one catalogue lookup each. That is what makes
-- it safe for a Job to re-run, and it is why the file carries no @DROP@.
applyIndexes :: ConnectionPool -> IO (Either String Int)
applyIndexes pool = applySqlAutocommit pool "sql/indexes/001_gov_indexes.sql" indexesSql

-- | The index names @sql\/indexes\/001_gov_indexes.sql@ declares, read out of the file itself.
--
-- __Derived, not a prefix.__ The obvious spelling of the check below is @relname LIKE 'gov_idx_%'@,
-- and it would be wrong twice: the file also (re-)creates two indexes under db-sync's own
-- @idx_@ names, and a prefix is a second place that has to agree with the file. Taking the word
-- after @IF NOT EXISTS@ cannot drift, because there is nothing to keep in step.
--
-- Every statement in the file is a @CREATE INDEX CONCURRENTLY IF NOT EXISTS@ — pinned by
-- @UnitTests.ApplySql@ — so a statement that yields no name here means the file grew a shape this
-- does not understand, and that is what the unit test on the count catches.
declaredIndexes :: [Text]
declaredIndexes = mapMaybe nameOf (splitStatements (TE.decodeUtf8 indexesSql))
  where
    nameOf s = case dropWhile ((/= "EXISTS") . T.toUpper) (T.words s) of
      (_ : n : _) -> Just (T.takeWhile (\c -> c == '_' || isAlphaNum c) n)
      _ -> Nothing

-- | Everything wrong with the declared index set, one line per index; @[]@ means every index in
-- 'declaredIndexes' is present and usable. Same shape, and for the same reason, as
-- 'Palmares.TxBuilding.Operations.deployedScriptsProblems'.
--
-- __Both directions, because @CREATE INDEX CONCURRENTLY@ has two silent failures and this used to
-- cover one__ (@GV-17@). The old version asked PostgreSQL for invalid indexes and intersected the
-- answer with 'declaredIndexes', so on a database holding NONE of them it returned @[]@ and
-- @apply-indexes@ printed \"all 23 declared indexes are valid\" — a claim about 23 indexes it had
-- never counted. It was a property of the empty set.
--
--   * __INVALID.__ Concurrently builds in two passes with a commit between them; interrupt it — a
--     cancelled Job, a deadlock, a killed pod — and the index is left behind with
--     @indisvalid = false@. The planner then ignores it, and @IF NOT EXISTS@ sees the name and does
--     nothing, so every later run reports success while the query the index was built for stays on
--     a sequential scan. Nothing raises an error, ever.
--   * __MISSING.__ Recovering from the above means @DROP INDEX@ and re-create, which is two steps
--     and a human — so the failure this check itself creates is an operator who read the INVALID
--     line, dropped the index as instructed, and did not re-run @apply-indexes@. The old check then
--     went green on a database with the index simply gone. The other way in is a @DROP INDEX@ this
--     repository does not perform: these indexes live in @public@, which is db-sync's, so a db-sync
--     migration that recreates one of its own tables takes our index with it and nothing re-applies
--     the file. Absence is not a subtle regression — the file records 2.03 s to 0.89 s on one page
--     of the activity feed, and a CC-vote arm that \"simply never finishes\" without
--     @gov_idx_committee_reg_hot@.
--
-- __Still intersected in Haskell rather than filtered in SQL__, which the missing half needs anyway:
-- answering \"which declared name is absent\" requires the set of names that ARE there, so the query
-- fetches @public@'s index catalogue — a few hundred rows on db-sync — and the comparison happens
-- here. That keeps the declared names out of a spliced @IN@ list, and it keeps the declared set
-- coming from the SQL file and nowhere else. An invalid index that is NOT ours stays db-sync's
-- business to report.
assertIndexesValid :: ConnectionPool -> IO [Text]
assertIndexesValid pool = map explain <$> indexProblems pool
  where
    explain (n, "missing") =
      n
        <> ": MISSING — no index of that name exists in schema public. Re-run `admin apply-indexes`; \
           \every statement is CREATE INDEX CONCURRENTLY IF NOT EXISTS, so the ones already there cost a \
           \catalogue lookup each."
    explain (n, _) =
      n
        <> ": INVALID — the index exists, the planner ignores it, and IF NOT EXISTS will skip it \
           \for ever. DROP INDEX CONCURRENTLY it and then re-run `admin apply-indexes` — a retry on \
           \its own will not fix it, and dropping without re-running leaves it MISSING."

-- | The same comparison as 'assertIndexesValid', as data: each declared index that is absent or
-- unusable, paired with @\"missing\"@ or @\"invalid\"@.
--
-- Separate from the prose because two callers want two shapes. @admin apply-indexes@ wants the
-- sentence that says what to DO about each one and then dies; @GET \/status@ wants the names, so a
-- reader can see that a db-sync re-sync from genesis dropped the index set — @public@ is db-sync's
-- schema, so its own migrations take our indexes with them and nothing in this repository re-applies
-- the file (`GV-17`, ADR 0001). Without @gov_idx_committee_reg_hot@ the CC arm of @palmares.vote@
-- never finishes, and query-api boots perfectly and answers every committee query with a 30 s 503.
--
-- The read is a catalogue scan of @public@ and needs no privilege a reader lacks: @pg_class@ and
-- @pg_index@ are world-readable, which is why the probe can run as @palmares_ro@.
indexProblems :: ConnectionPool -> IO [(Text, Text)]
indexProblems pool = do
  rows <-
    runSqlPoolNoTransaction
      ( rawSql @(Single Text, Single Bool)
          "SELECT c.relname, i.indisvalid FROM pg_class c \
          \JOIN pg_index i ON i.indexrelid = c.oid \
          \JOIN pg_namespace n ON n.oid = c.relnamespace \
          \WHERE n.nspname = 'public' \
          \ORDER BY c.relname"
          []
      )
      pool
      Nothing
  let present = [(unSingle n, unSingle v) | (n, v) <- rows]
  return $
    [(n, "missing") | n <- declaredIndexes, n `notElem` map fst present]
      <> [(n, "invalid") | (n, False) <- present, n `elem` declaredIndexes]

-- | Apply @sql\/050_roles.sql@, then set the two passwords.
--
-- __The passwords travel as BOUND parameters and are quoted server-side.__ DDL takes no parameters,
-- so the obvious shape — splicing the password into @ALTER ROLE … PASSWORD '…'@ — would be a client
-- building DDL out of a secret, which is the one injection this path could have. Instead the value
-- is bound to @set_config@ and a @DO@ block reads it back through @format('%L')@, which does the
-- quoting with PostgreSQL's own rules.
--
-- The setting is cleared afterwards. It is session-local either way (@set_config(…, false)@ outside
-- a transaction lasts for the session, and this pool's connections are reused), so leaving a
-- password in a session variable would be a password readable by the next query on that connection.
applyRoles :: ConnectionPool -> Text -> Text -> IO (Either String Int)
applyRoles pool ownerPassword roPassword = do
  r <- applySqlAutocommit pool "sql/050_roles.sql" rolesSql
  case r of
    Left e -> pure (Left e)
    Right n -> do
      p <- try (runSqlPoolNoTransaction (mapM_ setPassword pairs) pool Nothing)
      pure $ case p of
        Left (e :: SomeException) -> Left ("sql/050_roles.sql: setting a role password failed: " <> show e)
        Right () -> Right (n + 2)
  where
    pairs = [("palmares_owner", ownerPassword), ("palmares_ro", roPassword)]

    -- 'rawSql' and not 'rawExecute' for the two @set_config@ calls: @set_config@ is a function and
    -- the statement is a SELECT, which @rawExecute@ rejects outright ("execute resulted in
    -- Col 1-column result"). The result is the value that was set, and is discarded.
    setPassword :: (Text, Text) -> SqlPersistT IO ()
    setPassword (role, pw) = do
      _ <- rawSql @(Single Text) "SELECT set_config('palmares.tmp_pw', ?, false)" [toPersistValue pw]
      rawExecute
        ( "DO $pw$ BEGIN EXECUTE format('ALTER ROLE "
            <> role
            <> " PASSWORD %L', current_setting('palmares.tmp_pw')); END $pw$"
        )
        []
      _ <- rawSql @(Single Text) "SELECT set_config('palmares.tmp_pw', '', false)" []
      pure ()
