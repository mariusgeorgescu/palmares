-- | Decodarea celor două ecrane M1b care nu depind de nicio altă pagină: lista de SPO-uri și
-- | comitetul.
-- |
-- | Cazul care contează pe lista de SPO-uri nu e un rând plin, ci unul în care DOUĂ coloane sînt
-- | goale — pentru că așa sînt toate cele 511 de pe preprod. Dacă cineva întoarce `.:?` în `.:`
-- | pentru `ticker` sau `participation_rate`, ecranul nu se mai randează deloc, iar asta se vede
-- | aici și nu pe deploy.
module Test.Capabilities.SpoCommitteeSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures (committeeFixture, spoListFixture)
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types (ChainPoint(..), CommitteeMember(..), CommitteeState(..), SpoPage(..), SpoRow(..))
import Data.Array (head, length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isNothing)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = do
  describe "SpoPage decoding" do
    it "decodes the measured payload, empty columns and all" do
      case (decodeFixture spoListFixture :: Either ApiError SpoPage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (SpoPage p) -> do
          p.total `shouldEqual` 511
          length p.items `shouldEqual` 5
          case head p.items of
            Nothing -> fail "expected a pool"
            Just (SpoRow r) -> do
              r.votingPower `shouldEqual` 488729208474515.0
              r.votingPowerEpoch `shouldEqual` 321
              r.delegatorCount `shouldEqual` 5
              r.votesCast `shouldEqual` 8
              -- Cele două care sînt goale pe toată rețeaua. Vezi antetul modulului.
              isNothing r.ticker `shouldEqual` true
              isNothing r.participationRate `shouldEqual` true

  describe "CommitteeState decoding" do
    it "carries the quorum, which is the question the screen exists to answer" do
      case (decodeFixture committeeFixture :: Either ApiError CommitteeState) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (CommitteeState c) -> do
          c.quorumNumerator `shouldEqual` 2
          c.quorumDenominator `shouldEqual` 3
          c.epoch `shouldEqual` 321
          length c.members `shouldEqual` 3
          case head c.members of
            Nothing -> fail "expected a member"
            Just (CommitteeMember m) -> do
              m.expirationEpoch `shouldEqual` 372
              m.status `shouldEqual` "active"
              m.votesCast `shouldEqual` 6
              -- Autorizat și nedemisionat: cazul obișnuit, în care `resigned_at` lipsă e normalul.
              isNothing m.resignedAt `shouldEqual` true
              case m.authorizedAt of
                Nothing -> fail "expected an authorization point"
                Just (ChainPoint at) -> at.epoch `shouldEqual` 228
