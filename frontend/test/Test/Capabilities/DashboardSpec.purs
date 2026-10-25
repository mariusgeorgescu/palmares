-- | Testele ecranului de pornire: decodarea payload-ului măsurat, și cele două locuri în care o
-- | cifră corectă ar putea fi etichetată greșit.
module Test.Capabilities.DashboardSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures (dashboardFixture)
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types (DRepSummary(..), DashboardPage(..), EpochPoint(..), GovActionSummary(..))
import Components.Explorer.Dashboard (activeInactive, drepListHref, participationSeries)
import Data.Array (head, length)
import Data.Either (Either(..))
import Data.Foldable (lookup)
import Data.Maybe (Maybe(..), isNothing)
import Data.String as String
import Effect.Aff (Aff)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

withDashboard :: (DashboardPage -> Aff Unit) -> Aff Unit
withDashboard k = case (decodeFixture dashboardFixture :: Either ApiError DashboardPage) of
  Left e -> fail ("fixture did not decode: " <> show e)
  Right p -> k p

spec :: Spec Unit
spec = do
  describe "DashboardPage decoding" do
    it "decodes the measured preprod payload" do
      withDashboard \(DashboardPage p) -> do
        p.epoch `shouldEqual` 321
        p.totalDreps `shouldEqual` 294
        p.activeDreps `shouldEqual` 17
        p.inactiveDreps `shouldEqual` 187
        p.unknownDreps `shouldEqual` 90
        p.retiredDreps `shouldEqual` 526
        p.powerEpoch `shouldEqual` Just 321
        p.totalActions `shouldEqual` 131
        p.actionsInFlight `shouldEqual` 7
        length p.actionsByType `shouldEqual` 7
        length p.actionsByState `shouldEqual` 5
        length p.participationByEpoch `shouldEqual` 20

    it "decodes the pairs the server sends as two-element arrays" do
      -- `actions_by_type` e `[["treasury_withdrawals", 82], …]`, nu un obiect. Un decodor de obiect
      -- ar trece testul de lungime și ar cădea pe conținut.
      withDashboard \(DashboardPage p) -> do
        lookup "treasury_withdrawals" p.actionsByType `shouldEqual` Just 82
        lookup "info_action" p.actionsByType `shouldEqual` Just 17
        lookup "expired" p.actionsByState `shouldEqual` Just 107
        lookup "ratified" p.actionsByState `shouldEqual` Just 0

    it "keeps the treasury as two numbers" do
      -- Cerut 656.466.092 ADA, adoptat 0. Un singur număr ar spune exact pe dos.
      withDashboard \(DashboardPage p) -> do
        p.treasuryRequestedLovelace `shouldEqual` 656466092110010.0
        p.treasuryEnactedLovelace `shouldEqual` 0.0

    it "decodes the DRep rows nested in the dashboard" do
      withDashboard \(DashboardPage p) -> case head p.topDrepsByPower of
        Nothing -> fail "expected top DReps in the fixture"
        Just (DRepSummary d) -> do
          d.id `shouldEqual` "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm"
          d.hasScript `shouldEqual` false
          d.status `shouldEqual` "active"
          d.votingPower `shouldEqual` 400644627419166.0
          d.votingPowerEpoch `shouldEqual` Just 321
          d.delegatorCount `shouldEqual` 19
          d.participationRate `shouldEqual` Just 0.09523809523809523
          -- Măsurat: 154 din 200 de DRep-i n-au nume. Cazul fără nume e cazul obișnuit.
          isNothing d.givenName `shouldEqual` true

    it "decodes an action with a null title and a null treasury amount" do
      withDashboard \(DashboardPage p) -> case head p.closingSoon of
        Nothing -> fail "expected closing_soon in the fixture"
        Just (GovActionSummary a) -> do
          a.type_ `shouldEqual` "no_confidence"
          isNothing a.title `shouldEqual` true
          isNothing a.treasuryAmount `shouldEqual` true
          a.expiresEpoch `shouldEqual` Just 324
          a.lastVotableEpoch `shouldEqual` Just 323

  describe "activeInactive" do
    it "counts active plus inactive, which is not total_dreps" do
      -- 17 + 187 = 204, iar `total_dreps` e 294. Diferența de 90 sunt cei cu status `unknown`.
      -- Dacă vreodată cele două devin egale, linkul cu filtru nu mai are rost — și testul cade.
      withDashboard \page@(DashboardPage p) -> do
        activeInactive page `shouldEqual` 204
        (activeInactive page == p.totalDreps) `shouldEqual` false

  describe "drepListHref" do
    it "repeats status instead of joining it with a comma" do
      -- API-ul citește parametrii repetabili ca listă. `status=active,inactive` ar fi un status
      -- necunoscut, pe care serverul îl ignoră în silenție — deci filtrul ar da fail deschis.
      String.contains (String.Pattern "status=active&status=inactive") drepListHref `shouldEqual` true
      String.contains (String.Pattern "status=active,inactive") drepListHref `shouldEqual` false

  describe "participationSeries" do
    it "makes one point per epoch, labelled with the epoch" do
      withDashboard \page@(DashboardPage p) -> do
        length (participationSeries page) `shouldEqual` 20
        case head (participationSeries page), head p.participationByEpoch of
          Just point, Just (EpochPoint e) -> do
            point.label `shouldEqual` ("epoch " <> show e.epoch)
            point.value `shouldEqual` 0.20710059171597633
            String.contains (String.Pattern "20.7%") point.hint `shouldEqual` true
          _, _ -> fail "expected a first point in both the series and the payload"
