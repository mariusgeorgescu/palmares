{-# LANGUAGE OverloadedStrings #-}

-- | @\/status@'s epoch parameters, against a database that has not reached Conway.
--
-- db-sync writes an @epoch_param@ row for every epoch from Byron forward, and every column
-- 'epochParamsQuery' selects is a Conway parameter — so on a pre-Conway epoch the latest row
-- exists with all of them NULL. @Query.Gov.queryJson1@ fails loud on a view/DTO disagreement, and
-- that @error@ fires inside the response body: the socket closes with zero bytes written, which no
-- client can tell from a crashed server. Measured on preprod while db-sync replayed epoch 78 of
-- 321 — the whole site was down on its first request for the hours that replay took.
--
-- So the predicate that makes a row usable rather than merely present is pinned here.
module UnitTests.EpochParams (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Database.Persist.Sql (rawExecute)
import Palmares.DomainTypes.Transfer.QueryResponses (EpochParamsSummary (..))
import Query.Gov (epochParamsQuery)
import Query.Views (applyPalmaresSchema)
import Test.Pg (runPg, withScratchDb)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "epoch params (/status)"
    [ testCase "a pre-Conway row is absent, not a closed socket" $ withScratchDb $ \pool -> do
        applyPalmaresSchema pool
        runPg pool $ rawExecute (insertEpochParam 1 78 Nothing) []
        got <- runPg pool epochParamsQuery
        fmap epochParamsEpoch got @?= Nothing,
      testCase "the latest row that HAS governance parameters is the one served" $
        withScratchDb $ \pool -> do
          applyPalmaresSchema pool
          runPg pool $ rawExecute (insertEpochParam 1 77 Nothing) []
          runPg pool $ rawExecute (insertEpochParam 2 78 (Just 6)) []
          runPg pool $ rawExecute (insertEpochParam 3 79 Nothing) []
          got <- runPg pool epochParamsQuery
          -- Epoch 79 is the latest row and 78 the latest usable one. A node never un-forks, so
          -- this ordering is not something preprod can show us; it is here because the clause
          -- lives in the WHERE rather than outside a @LIMIT 1@, and this case is the difference.
          fmap epochParamsEpoch got @?= Just 78
          fmap epochParamsGovActionLifetime got @?= Just 6
          -- All fifteen thresholds decode as pairs of 'Double', so one NULL among them would fail
          -- exactly the way @gov_action_lifetime@ did.
          fmap (length . epochParamsDrepThresholds) got @?= Just 10
          fmap (length . epochParamsPoolThresholds) got @?= Just 5
    ]

-- | One @epoch_param@ row. The nineteen NOT NULL columns are filled with zeroes — nothing here
-- reads them — and the governance columns are all set or all NULL together, which is how the
-- ledger writes them: they arrive with the Conway protocol parameters or not at all.
insertEpochParam :: Int -> Int -> Maybe Int -> Text
insertEpochParam rowId epoch govLifetime =
  "INSERT INTO public.epoch_param \
  \ (id, epoch_no, min_fee_a, min_fee_b, max_block_size, max_tx_size, max_bh_size, key_deposit, \
  \  pool_deposit, max_epoch, optimal_pool_count, influence, monetary_expand_rate, \
  \  treasury_growth_rate, decentralisation, protocol_major, protocol_minor, min_utxo_value, \
  \  min_pool_cost, block_id, \
  \  pvt_motion_no_confidence, pvt_committee_normal, pvt_committee_no_confidence, \
  \  pvt_hard_fork_initiation, pvtpp_security_group, \
  \  dvt_motion_no_confidence, dvt_committee_normal, dvt_committee_no_confidence, \
  \  dvt_update_to_constitution, dvt_hard_fork_initiation, dvt_p_p_network_group, \
  \  dvt_p_p_economic_group, dvt_p_p_technical_group, dvt_p_p_gov_group, dvt_treasury_withdrawal, \
  \  committee_min_size, committee_max_term_length, gov_action_lifetime, gov_action_deposit, \
  \  drep_deposit, drep_activity) \
  \ VALUES ("
    <> num rowId
    <> ","
    <> num epoch
    <> ",0,0,0,0,0,0,0,0,0,0,0,0,0,10,0,0,0,"
    <> num rowId
    <> ","
    <> gov
    <> ")"
  where
    num :: Int -> Text
    num = T.pack . show
    gov = case govLifetime of
      -- Pre-Conway: fifteen thresholds, two committee parameters and four action parameters, all
      -- absent.
      Nothing -> T.intercalate "," (replicate 21 "NULL")
      Just lifetime ->
        T.intercalate "," (replicate 15 "0.51" <> ["0", "73", num lifetime, "100000000000", "500000000", "20"])
