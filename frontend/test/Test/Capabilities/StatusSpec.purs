-- | Testele pentru `/status`: pragurile chip-ului și decodarea payload-ului măsurat.
module Test.Capabilities.StatusSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Fixtures (statusFixture)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types (AttestSync(..), ChipState(..), GovStatus(..), GovSync(..), chipState, chipStateFor)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isJust, isNothing)
import Effect.Aff (Aff)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

withStatus :: String -> (GovStatus -> Aff Unit) -> Aff Unit
withStatus fixture k = case (decodeFixture fixture :: Either ApiError GovStatus) of
  Left e -> fail ("fixture did not decode: " <> show e)
  Right s -> k s

-- | Același payload, fără blocul de atestări — un deploy doar-guvernanță.
governanceOnlyFixture :: String
governanceOnlyFixture =
  """
  { "network": "preprod"
  , "governance":
      { "epoch": 321, "slot": 137140009, "block_time": "2026-10-24T06:26:49Z"
      , "lag_seconds": 43, "is_ready": true, "source": "cardano-db-sync" }
  , "drep_distr_epoch": 320
  , "amber_lag_seconds": 120
  , "ready_max_lag_seconds": 300
  , "metrics_as_of_epoch": 321
  }
  """

spec :: Spec Unit
spec = do
  describe "chipState" do
    it "is Green below the amber threshold" do
      chipState 10 120 300 `shouldEqual` Green

    it "is Amber AT the amber threshold" do
      -- Pragul e inclusiv: la exact 120 s datele sunt deja atât de vechi cât serverul a spus că e
      -- demn de un avertisment.
      chipState 120 120 300 `shouldEqual` Amber

    it "is Red at the ready threshold" do
      chipState 300 120 300 `shouldEqual` Red

    it "is Red above the ready threshold" do
      chipState 5000 120 300 `shouldEqual` Red

  describe "GovStatus decoding" do
    it "decodes the measured preprod payload" do
      withStatus statusFixture \(GovStatus s) -> do
        s.network `shouldEqual` "preprod"
        s.metricsAsOfEpoch `shouldEqual` 321
        s.amberLagSeconds `shouldEqual` 120
        s.readyMaxLagSeconds `shouldEqual` 300
        case s.governance of
          GovSync g -> do
            g.epoch `shouldEqual` 321
            g.lagSeconds `shouldEqual` 43
            g.source `shouldEqual` "cardano-db-sync"

    it "decodes the attestation block, with last_error null" do
      withStatus statusFixture \(GovStatus s) -> case s.attestation of
        Nothing -> fail "expected an attestation block in the full fixture"
        Just (AttestSync a) -> do
          a.state `shouldEqual` "following"
          a.lagSeconds `shouldEqual` 0
          a.policyId `shouldEqual` "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3"
          isNothing a.lastError `shouldEqual` true
          isJust a.lastSyncAt `shouldEqual` true

    it "decodes a governance-only deployment without failing" do
      -- `attestation` absent e o configurație validă, nu o eroare. Decodorul care ar cere cheia ar
      -- face un deploy legitim să arate un ecran rupt.
      withStatus governanceOnlyFixture \(GovStatus s) -> do
        isNothing s.attestation `shouldEqual` true
        isNothing s.attestLagSeconds `shouldEqual` true

    it "keeps drep_distr_epoch separate from the chain epoch" do
      -- Ledgerul scrie distribuția de stake cu o epocă în urmă față de tip, deci cifrele de putere
      -- se etichetează cu ea. Un singur câmp pentru amândouă ar pune o etichetă greșită pe un număr
      -- corect, care e cea mai greu de observat formă de greșeală.
      withStatus governanceOnlyFixture \(GovStatus s) -> do
        s.drepDistrEpoch `shouldEqual` 320
        case s.governance of
          GovSync g -> g.epoch `shouldEqual` 321

  describe "chipStateFor" do
    it "takes the worst lag of the two sources" do
      -- 43 s de guvernanță, 0 s de atestări, prag ambar 120 → verde.
      withStatus statusFixture \s -> chipStateFor s `shouldEqual` Green

    it "ignores the attestation lag when there is no projector" do
      withStatus governanceOnlyFixture \s -> chipStateFor s `shouldEqual` Green
