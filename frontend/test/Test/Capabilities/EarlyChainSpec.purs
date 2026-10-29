-- | Cîmpurile pe care API-ul le trimite `null` pe un lanț care încă se reface — și pe care
-- | fixturile, măsurate pe preprod SINCRONIZAT, le au mereu pline.
-- |
-- | Asta e aceeași greșeală de trei ori, și a treia oară a dărîmat ecranul de pornire pe deploy:
-- | `"power_epoch": null` pe un db-sync la epoca 95, iar decodorul cerea un număr. Nu s-a văzut în
-- | niciun test, pentru că fixtura are acolo 321. O fixtură trunchiată sau norocoasă minte despre
-- | FORMA datelor, nu doar despre conținutul lor.
-- |
-- | Deci aici fiecare payload real e luat și i se golesc cîmpurile pe care serverul are voie să le
-- | lase goale (`Maybe` în `QueryResponses.hs`). Testul nu verifică o valoare, ci că ecranul mai
-- | există: dacă cineva pune la loc un `.:` în locul unui `.:?`, cade aici și nu pe preprod.
module Test.Capabilities.EarlyChainSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures
  ( dashboardFixture
  , drepDetailFixture
  , govActionDetailFixture
  , statusFixture
  )
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types
  ( DRepDetail(..)
  , DRepSummary(..)
  , DashboardPage(..)
  , GovActionDetail(..)
  , GovActionSummary(..)
  , GovStatus(..)
  , PowerPoint(..)
  )
import Data.Array (head)
import Data.Either (Either(..))
import Data.Foldable (foldl)
import Data.Maybe (Maybe(..), isNothing)
import Data.String.Regex (Regex, regex, replace) as R
import Data.String.Regex.Flags (global) as RF
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

-- | Înlocuiește valoarea fiecărei chei date cu `null`, oriunde apare în payload.
-- |
-- | Tiparul se oprește la prima virgulă sau acoladă, deci acoperă exact valorile SCALARE — numere,
-- | șiruri fără virgulă, booleeni — care sînt singurele de care e vorba aici. O cheie care ține un
-- | obiect ar trebui golită altfel, și n-ar trece neobservată: payload-ul ar deveni nevalid.
nullOut :: Array String -> String -> String
nullOut keys s = foldl one s keys
  where
  one acc k = case R.regex ("\"" <> k <> "\": *[^,}\\]]+") RF.global of
    Left _ -> acc
    Right (re :: R.Regex) -> R.replace re ("\"" <> k <> "\": null") acc

spec :: Spec Unit
spec = describe "an early chain: every nullable field actually null" do
  it "the dashboard survives a chain with no power distribution yet" do
    let
      -- `power_epoch` lipsește pînă cînd ledgerul publică prima distribuție de putere;
      -- `registered_at`, `age_days` și `voting_power_epoch` sînt ale DRep-ilor din tabelul de jos,
      -- iar `expires_epoch` și `last_votable_epoch` ale acțiunilor care se închid curînd.
      payload = nullOut
        [ "power_epoch"
        , "registered_at"
        , "age_days"
        , "voting_power_epoch"
        , "expires_epoch"
        , "last_votable_epoch"
        ]
        dashboardFixture
    case (decodeFixture payload :: Either ApiError DashboardPage) of
      Left e -> fail ("the dashboard stopped decoding: " <> show e)
      Right (DashboardPage p) -> do
        isNothing p.powerEpoch `shouldEqual` true
        case head p.topDrepsByPower of
          Nothing -> fail "expected a DRep in the fixture"
          Just (DRepSummary d) -> do
            isNothing d.registeredAt `shouldEqual` true
            isNothing d.ageDays `shouldEqual` true
            isNothing d.votingPowerEpoch `shouldEqual` true
        case head p.closingSoon of
          Nothing -> fail "expected an action in the fixture"
          Just (GovActionSummary a) -> do
            isNothing a.expiresEpoch `shouldEqual` true
            isNothing a.lastVotableEpoch `shouldEqual` true

  it "the status band survives a database with no metrics and no distribution" do
    let payload = nullOut [ "metrics_as_of_epoch", "drep_distr_epoch" ] statusFixture
    case (decodeFixture payload :: Either ApiError GovStatus) of
      Left e -> fail ("the status stopped decoding: " <> show e)
      Right (GovStatus s) -> do
        isNothing s.metricsAsOfEpoch `shouldEqual` true
        isNothing s.drepDistrEpoch `shouldEqual` true

  it "a DRep page survives a DRep with no age and no registration date" do
    let
      -- NU și `delegator_count`: cheia apare în DOUĂ obiecte diferite ale aceluiași payload, iar
      -- în `drep` serverul nu are voie s-o lase goală. Cea din seria de putere, unde are voie, e
      -- testată separat mai jos.
      payload = nullOut [ "age_days", "registered_at", "voting_power_epoch" ] drepDetailFixture
    case (decodeFixture payload :: Either ApiError DRepDetail) of
      Left e -> fail ("the DRep page stopped decoding: " <> show e)
      Right (DRepDetail _) -> pure unit

  it "a power point survives an epoch with no delegator count" do
    let payload = """{ "epoch": 321, "lovelace": 400644627419166, "delegator_count": null }"""
    case (decodeFixture payload :: Either ApiError PowerPoint) of
      Left e -> fail ("the power series stopped decoding: " <> show e)
      Right (PowerPoint p) -> isNothing p.delegatorCount `shouldEqual` true

  it "an action page survives a withdrawal with no payment heuristic and no tx" do
    let payload = nullOut [ "paid_heuristic", "tx_hash" ] govActionDetailFixture
    case (decodeFixture payload :: Either ApiError GovActionDetail) of
      Left e -> fail ("the action page stopped decoding: " <> show e)
      Right (GovActionDetail _) -> pure unit
