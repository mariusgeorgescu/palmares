-- | Testele explorerului de voturi. Două dintre ele apără ecranul de un număr pe care serverul îl
-- | dă greșit, și de o treaptă de performanță măsurată.
module Test.Capabilities.VoteSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures (votesListFixture)
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types (ChainPoint(..), VoteAnchor(..), VotePage(..), VoteRow(..))
import Components.Explorer.VoteList (effectiveFilters, verdictClass, verdicts, voterRoles)
import Data.Array (head, length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isJust, isNothing)
import Data.String as String
import Effect.Aff (Aff)
import Query.Page (nextOffset, offsetCeiling, votesOffsetCeiling)
import Route as R
import Route.Codec (parseRoute, printRoute)
import Route.GovQueries
  ( defaultVoteFilters
  , emptyVoteFilters
  , renderVoteFilters
  , votesForActionHref
  , votesForDRepHref
  )
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

withVotes :: (VotePage -> Aff Unit) -> Aff Unit
withVotes k = case (decodeFixture votesListFixture :: Either ApiError VotePage) of
  Left e -> fail ("fixture did not decode: " <> show e)
  Right p -> k p

spec :: Spec Unit
spec = do
  describe "VotePage decoding" do
    it "decodes the measured payload" do
      withVotes \(VotePage p) -> do
        p.total `shouldEqual` 8
        p.limit `shouldEqual` 4
        length p.items `shouldEqual` 4

    it "decodes a superseded vote without hiding that it was replaced" do
      -- Primul rând măsurat are `is_final: false` și `revote_count: 3`: un vot care a fost
      -- înlocuit. Un ecran care nu face diferența numără același votant de trei ori.
      withVotes \(VotePage p) -> case head p.items of
        Nothing -> fail "expected a row"
        Just (VoteRow v) -> do
          v.isFinal `shouldEqual` false
          v.isFirst `shouldEqual` true
          v.revoteCount `shouldEqual` 3
          v.verdict `shouldEqual` "yes"
          v.voterRole `shouldEqual` "drep"
          isJust v.latencyHours `shouldEqual` true
          -- Măsurat `null` pe toate rândurile verificate: puterea de vot nu e înregistrată per vot.
          isNothing v.votingPower `shouldEqual` true
          case v.castAt of
            ChainPoint at -> (at.epoch > 0) `shouldEqual` true

    it "decodes the rationale anchor, keeping valid and CIP-100 apart" do
      -- „Ancoră validă" înseamnă că documentul se potrivește cu hash-ul. „CIP-100 valid" înseamnă
      -- că și respectă schema. Serverul le raportează separat, deci nu se topesc într-un bifat.
      withVotes \(VotePage p) -> case head p.items of
        Nothing -> fail "expected a row"
        Just (VoteRow v) -> case v.anchor of
          Nothing -> fail "expected an anchor on a vote filtered by anchor_status=valid"
          Just (VoteAnchor a) -> do
            a.status `shouldEqual` Just "valid"
            a.cip100Valid `shouldEqual` Just true
            case a.url of
              Nothing -> fail "expected an anchor url"
              Just u -> String.contains (String.Pattern "https://") u `shouldEqual` true

  describe "effectiveFilters" do
    it "never asks the server for an unfiltered count" do
      -- Măsurat: `/votes` fără filtre raportează 3.244.726 pe o rețea cu ~900 de voturi reale.
      -- Orice filtru îl repară. Deci ecranul nu cere niciodată nefiltrat.
      (effectiveFilters emptyVoteFilters).is_final `shouldEqual` Just "true"

    it "leaves a filtered request exactly as it was asked for" do
      let asked = emptyVoteFilters { verdict = [ "no" ] }
      effectiveFilters asked `shouldEqual` asked
      -- Inclusiv când filtrul e „arată-mi voturile înlocuite", care n-are `is_final=true`.
      let superseded = emptyVoteFilters { is_final = Just "false" }
      effectiveFilters superseded `shouldEqual` superseded

  describe "the votes pager" do
    it "stops at 600, well before the server's own ceiling" do
      -- Măsurat: 1,1 s la offset 600, 12,15 s la 800. ADR 0009 decide că nu se repară, deci
      -- ecranul oferă filtrare în loc de adâncime.
      nextOffset votesOffsetCeiling 50 600 100000 `shouldEqual` Nothing
      nextOffset offsetCeiling 50 600 100000 `shouldEqual` Just 650
      nextOffset votesOffsetCeiling 50 500 100000 `shouldEqual` Just 550

  describe "the votes route" do
    it "round-trips its filters" do
      let
        filters = emptyVoteFilters
          { verdict = [ "yes", "abstain" ]
          , voter_role = [ "drep" ]
          , is_final = Just "true"
          , order_by = Just "cast_at"
          , sort_order = Just "desc"
          }
      parseRoute (printRoute (R.VoteList filters)) `shouldEqual` R.VoteList filters

    it "links from a DRep and from an action, each with the right filter" do
      votesForDRepHref "drep1abc" `shouldEqual` "/votes?voter_id=drep1abc"
      -- `#` din ID-ul acțiunii se codează și în valoarea parametrului, nu doar în cale.
      votesForActionHref "abc#0" `shouldEqual` "/votes?gov_action_id=abc%230"

    it "sends the default filter in the URL, so the number on screen is reproducible" do
      renderVoteFilters defaultVoteFilters `shouldEqual` "?is_final=true"

  describe "the filter values" do
    it "offers the three verdicts and the three voter roles" do
      verdicts `shouldEqual` [ "yes", "no", "abstain" ]
      length voterRoles `shouldEqual` 3
      verdictClass "yes" `shouldEqual` "badge-success"
      verdictClass "no" `shouldEqual` "badge-error"
