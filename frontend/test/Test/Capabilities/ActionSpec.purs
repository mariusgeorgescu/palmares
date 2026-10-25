-- | Testele acțiunilor de guvernanță: lista, detaliul, și cele două locuri unde un număr corect ar
-- | putea fi prezentat ca un verdict pe care nu-l susține.
module Test.Capabilities.ActionSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures (govActionDetailFixture, govActionListFixture)
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types
  ( ActionAnchor(..)
  , ChainPoint(..)
  , GovActionDetail(..)
  , GovActionPage(..)
  , GovActionSummary(..)
  , Lifecycle(..)
  , Proposer(..)
  , Tally(..)
  , Withdrawal(..)
  )
import Components.Explorer.ActionDetail (lifecyclePath, tallyVerdict)
import Components.Explorer.ActionList (actionStates, actionTypes)
import Data.Array (head, length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isNothing)
import Data.String as String
import Effect.Aff (Aff)
import Route as R
import Route.Codec (parseRoute, printRoute)
import Route.GovQueries (actionDetailHrefFor, emptyGovActionFilters, renderGovActionFilters)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

withList :: (GovActionPage -> Aff Unit) -> Aff Unit
withList k = case (decodeFixture govActionListFixture :: Either ApiError GovActionPage) of
  Left e -> fail ("list fixture did not decode: " <> show e)
  Right p -> k p

withDetail :: (GovActionDetail -> Aff Unit) -> Aff Unit
withDetail k = case (decodeFixture govActionDetailFixture :: Either ApiError GovActionDetail) of
  Left e -> fail ("detail fixture did not decode: " <> show e)
  Right p -> k p

-- | O numărătoare în care puterea de ambele părți e zero, deci raportul nu există. Măsurată pe o
-- | acțiune reală cu 43 de voturi exprimate — adică un ecran care ar scrie „0%" ar spune că
-- | propunerea a fost respinsă, când de fapt nu se poate calcula nimic.
nullRatioTally :: String
nullRatioTally =
  """
  { "role": "drep", "epoch": 321
  , "yes_power": 0, "no_power": 0, "abstain_power": 0
  , "yes_count": 1, "no_count": 0, "abstain_count": 42
  , "ratio": null, "threshold": 0.67
  , "threshold_param": "dvt_p_p_economic_group"
  , "basis": "cast_votes_only", "formula_id": "tally_cast_votes_v1"
  }
  """

spec :: Spec Unit
spec = do
  describe "GovActionPage decoding" do
    it "decodes the measured list envelope" do
      withList \(GovActionPage p) -> do
        p.total `shouldEqual` 131
        p.limit `shouldEqual` 4
        p.offset `shouldEqual` 0
        length p.items `shouldEqual` 4

    it "decodes a row with no title, which is the common case" do
      withList \(GovActionPage p) -> case head p.items of
        Nothing -> fail "expected a row"
        Just (GovActionSummary a) -> do
          a.type_ `shouldEqual` "parameter_change"
          isNothing a.title `shouldEqual` true
          a.votesCast `shouldEqual` 43
          a.deposit `shouldEqual` Just 1000000000.0
          isNothing a.treasuryAmount `shouldEqual` true
          case a.proposedAt of
            ChainPoint at -> at.epoch `shouldEqual` 319
          case a.lifecycle of
            Lifecycle lc -> do
              lc.state `shouldEqual` "proposed"
              isNothing lc.ratifiedEpoch `shouldEqual` true
              lc.formulaId `shouldEqual` Just "gov_action_state_v1"

  describe "GovActionDetail decoding" do
    it "decodes the action, its tally, its withdrawal and its proposer in one payload" do
      withDetail \(GovActionDetail d) -> do
        case d.action of
          GovActionSummary a -> do
            a.type_ `shouldEqual` "treasury_withdrawals"
            a.treasuryAmount `shouldEqual` Just 1000000000000.0
            a.votesCast `shouldEqual` 58
            a.anchorStatus `shouldEqual` Just "valid"
        length d.tallies `shouldEqual` 1
        length d.withdrawals `shouldEqual` 1
        length d.paramChanges `shouldEqual` 0
        case d.proposer of
          Nothing -> fail "expected a proposer"
          Just (Proposer p) -> p.actionsCount `shouldEqual` 2

    it "keeps both lifecycle epochs when an action expired and was then dropped" do
      -- Starea e un cuvânt — „expired" — dar drumul are doi pași, în două epoci diferite. Un model
      -- cu un singur câmp ar pierde unul dintre ele.
      withDetail \(GovActionDetail d) -> case d.action of
        GovActionSummary a -> case a.lifecycle of
          Lifecycle lc -> do
            lc.state `shouldEqual` "expired"
            lc.expiredEpoch `shouldEqual` Just 304
            lc.droppedEpoch `shouldEqual` Just 305
            length (lifecyclePath a.lifecycle) `shouldEqual` 2

    it "decodes a withdrawal that was never paid, and says whether payment was inferred" do
      withDetail \(GovActionDetail d) -> case head d.withdrawals of
        Nothing -> fail "expected a withdrawal"
        Just (Withdrawal w) -> do
          w.amount `shouldEqual` 1000000000000.0
          isNothing w.enactedAt `shouldEqual` true
          w.paidHeuristic `shouldEqual` false

    it "decodes the CIP-108 document, duplicate references and all" do
      -- Documentul real conține același link de două ori. Se randează așa cum e: e documentul lor,
      -- iar un deduplicator ar ascunde ce au scris.
      withDetail \(GovActionDetail d) -> case d.anchorContent of
        Nothing -> fail "expected a document on an action whose anchor is valid"
        Just (ActionAnchor a) -> do
          a.title `shouldEqual` Just "Rename the Chang 2 Hard Fork to the Plomin Hard Fork"
          length a.references `shouldEqual` 4
          case a.rationale of
            Nothing -> fail "expected a rationale"
            Just r -> (String.length r > 2000) `shouldEqual` true

    it "decodes a tally whose ratio cannot be computed" do
      case (decodeFixture nullRatioTally :: Either ApiError Tally) of
        Left e -> fail ("tally did not decode: " <> show e)
        Right (Tally t) -> do
          isNothing t.ratio `shouldEqual` true
          t.threshold `shouldEqual` Just 0.67
          t.abstainCount `shouldEqual` 42

  describe "tallyVerdict" do
    it "refuses to turn a missing ratio into a verdict" do
      case (decodeFixture nullRatioTally :: Either ApiError Tally) of
        Left e -> fail ("tally did not decode: " <> show e)
        Right t -> tallyVerdict t `shouldEqual` "ratio not computable"

    it "says met or not met, and shows the comparison it used" do
      let
        withRatio r th = Tally
          { role: "drep"
          , epoch: 321
          , yesPower: 0.0
          , noPower: 0.0
          , abstainPower: 0.0
          , yesCount: 0
          , noCount: 0
          , abstainCount: 0
          , ratio: Just r
          , threshold: Just th
          , thresholdParam: Nothing
          , basis: Nothing
          , formulaId: Nothing
          }
      tallyVerdict (withRatio 0.7 0.67) `shouldEqual`
        "70.0% in favour against a 67.0% threshold — met"
      tallyVerdict (withRatio 0.5 0.67) `shouldEqual`
        "50.0% in favour against a 67.0% threshold — not met"

  describe "the governance action routes" do
    it "carries an id with a # through the URL and back" do
      -- Un identificator e `<txhash>#<index>`. Netratat, `#` taie cererea la fragment: s-ar cere
      -- lista în loc de acțiune, și nimeni n-ar vedea o eroare.
      actionDetailHrefFor "abc#0" `shouldEqual` "/gov-actions/abc%230"
      parseRoute "/gov-actions/abc%230" `shouldEqual` R.ActionDetail "abc#0"
      printRoute (R.ActionDetail "abc#0") `shouldEqual` "/gov-actions/abc%230"

    it "does not let the list route swallow a detail path" do
      parseRoute "/gov-actions" `shouldEqual` R.ActionList emptyGovActionFilters

    it "round-trips its filters" do
      let
        filters = emptyGovActionFilters
          { type_ = [ "treasury_withdrawals", "info_action" ]
          , state = [ "proposed" ]
          , order_by = Just "votes_cast"
          , sort_order = Just "desc"
          }
      parseRoute (printRoute (R.ActionList filters)) `shouldEqual` R.ActionList filters

    it "sends the repeated parameter the API reads as a list" do
      renderGovActionFilters (emptyGovActionFilters { type_ = [ "info_action", "no_confidence" ] })
        `shouldEqual` "?type=info_action&type=no_confidence"

  describe "the filter values" do
    it "offers exactly the ledger's own enumerations" do
      length actionTypes `shouldEqual` 7
      length actionStates `shouldEqual` 5
