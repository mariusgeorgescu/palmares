-- | Testele paginii de DRep și ale randării unui document străin.
module Test.Capabilities.DRepDetailSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures (drepDetailFixture)
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types
  ( AnchorContent(..)
  , AnchorRef(..)
  , DRepDetail(..)
  , DRepMetrics(..)
  , DRepSummary(..)
  , Delegator(..)
  , DelegatorStats(..)
  , FinalVotes(..)
  , VoteTypeStats(..)
  )
import Components.Explorer.DRepDetail (latencyLabel, rationaleBreakdown)
import Components.Shared.Anchor (clampText, safeHref, statusExplanation)
import Data.Array (head, last, length, replicate)
import Data.Either (Either(..))
import Data.Foldable (lookup)
import Data.Maybe (Maybe(..), isJust, isNothing)
import Data.String as String
import Data.Tuple (fst)
import Effect.Aff (Aff)
import Route as R
import Route (section)
import Route.Codec (parseRoute, printRoute, routeCodec)
import Routing.Duplex (parse)
import Route.GovQueries (drepDetailHrefFor, emptyDRepFilters, emptyGovActionFilters, emptyRegistryFilters)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

withDetail :: (DRepDetail -> Aff Unit) -> Aff Unit
withDetail k = case (decodeFixture drepDetailFixture :: Either ApiError DRepDetail) of
  Left e -> fail ("fixture did not decode: " <> show e)
  Right p -> k p

spec :: Spec Unit
spec = do
  describe "DRepDetail decoding" do
    it "decodes the identity block as the same row type the list uses" do
      withDetail \(DRepDetail d) -> case d.drep of
        DRepSummary s -> do
          s.id `shouldEqual` "drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z"
          s.hasScript `shouldEqual` true
          s.givenName `shouldEqual` Just "Logical Mechanism dRep"
          s.anchorStatus `shouldEqual` Just "valid"

    it "decodes the metrics, including the two latency figures and the sample behind them" do
      withDetail \(DRepDetail d) -> case d.metrics of
        DRepMetrics m -> do
          m.asOfEpoch `shouldEqual` 321
          m.eligibleActions `shouldEqual` 120
          m.votesCast `shouldEqual` 1
          m.openActionsUnvoted `shouldEqual` 7
          m.rationaleAbsent `shouldEqual` 1
          m.rationaleVerified `shouldEqual` 0
          -- 0.0 nu e `null`: aici serverul a putut evalua și a găsit zero raționamente.
          m.rationaleRate `shouldEqual` Just 0.0
          m.voteLatencySample `shouldEqual` 1
          isJust m.voteLatencyMedianHours `shouldEqual` true
          length m.formulaIds `shouldEqual` 6

    it "keeps the final vote counts separate from the per-kind ones" do
      withDetail \(DRepDetail d) -> case d.metrics of
        DRepMetrics m -> do
          case m.finalVotes of
            FinalVotes v -> do
              v.yes `shouldEqual` 1
              v.no `shouldEqual` 0
              v.abstain `shouldEqual` 0
          length m.votesByType `shouldEqual` 7

    it "measures each kind of action against its own denominator" do
      -- Numitorul pentru retragerile de trezorerie e 81, nu 120: un DRep care n-a votat niciuna
      -- are 0% la acel tip, iar faptul că are 120 de acțiuni eligibile în total nu schimbă asta.
      withDetail \(DRepDetail d) -> case d.metrics of
        DRepMetrics m -> case lookup "treasury_withdrawals" m.votesByType of
          Nothing -> fail "expected treasury_withdrawals in votes_by_type"
          Just (VoteTypeStats v) -> do
            v.eligibleActions `shouldEqual` 81
            v.votesCast `shouldEqual` 0
            v.participationRate `shouldEqual` Just 0.0

    it "decodes the delegator window, with the previous count to compare against" do
      withDetail \(DRepDetail d) -> case d.delegatorStats of
        DelegatorStats s -> do
          s.delegatorCount `shouldEqual` 5
          s.delegatorCountPrev `shouldEqual` 5
          s.delegatorsJoined `shouldEqual` 0
          s.delegatorsLeft `shouldEqual` 0
          s.delegatorRetentionRate `shouldEqual` Just 1.0
          s.windowEpochs `shouldEqual` 10

    it "decodes the series, the delegators and the registration history" do
      withDetail \(DRepDetail d) -> do
        length d.powerByEpoch `shouldEqual` 20
        length d.topDelegators `shouldEqual` 5
        length d.updates `shouldEqual` 2
        case head d.topDelegators of
          Nothing -> fail "expected a delegator"
          Just (Delegator t) -> do
            t.isCurrent `shouldEqual` true
            t.lovelace `shouldEqual` Just 5912487235860.0

    it "survives a delegator whose stake the epoch does not record" do
      -- Măsurat pe serverul care rulează: al cincilea delegator avea `lovelace: null`, pentru că
      -- suma se citește din `epoch_stake` și epoca poate să n-aibă încă rândul. Decodorul care
      -- cerea un număr a rupt tot ecranul pentru un rând incomplet — fixtura nu l-a prins fiindcă
      -- îl tăiase.
      withDetail \(DRepDetail d) -> case last d.topDelegators of
        Nothing -> fail "expected five delegators"
        Just (Delegator t) -> do
          isNothing t.lovelace `shouldEqual` true
          t.isCurrent `shouldEqual` true

    it "decodes the metadata document and its references" do
      withDetail \(DRepDetail d) -> case d.anchorContent of
        Nothing -> fail "expected anchor content on a DRep whose anchor is valid"
        Just (AnchorContent a) -> do
          a.givenName `shouldEqual` Just "Logical Mechanism dRep"
          isJust a.objectives `shouldEqual` true
          length a.references `shouldEqual` 2
          case head a.references of
            Nothing -> fail "expected a reference"
            Just (AnchorRef r) -> do
              r.label `shouldEqual` Just "The Logical Mechanism Website"
              r.uri `shouldEqual` Just "https://www.logicalmechanism.io/"

  describe "rationaleBreakdown" do
    it "keeps the five states apart instead of folding them into one number" do
      withDetail \(DRepDetail d) -> do
        length (rationaleBreakdown d.metrics) `shouldEqual` 6
        lookup "None published" (rationaleBreakdown d.metrics) `shouldEqual` Just 1
        lookup "Verified" (rationaleBreakdown d.metrics) `shouldEqual` Just 0
        map fst (rationaleBreakdown d.metrics) `shouldEqual`
          [ "Verified"
          , "Inline in the transaction"
          , "Could not be verified"
          , "Not checked yet"
          , "None published"
          , "Valid CIP-100 document"
          ]

  describe "latencyLabel" do
    it "says n/a when there is no measurement" do
      latencyLabel Nothing 0 `shouldEqual` "n/a"

    it "carries the sample size, because a median of two votes is not a median" do
      latencyLabel (Just 44.55208333333333) 10 `shouldEqual` "44.6 h (10 votes)"
      latencyLabel (Just 0.05444444444444444) 1 `shouldEqual` "0.1 h (1 vote)"
      latencyLabel (Just 1.0) 1 `shouldEqual` "1.0 h (1 vote)"

  describe "the DRep detail route" do
    it "wins over the list route, which would otherwise swallow the id" do
      -- `Routing.Duplex.parse` acceptă o potrivire care lasă segmente neconsumate, deci ordinea
      -- constructorilor din `Route` e singurul lucru care ține ruta asta în viață.
      parseRoute "/dreps/drep1abc" `shouldEqual` R.DRepDetail "drep1abc"
      parseRoute "/dreps" `shouldEqual` R.DRepList emptyDRepFilters

    it "prints what it parses" do
      printRoute (R.DRepDetail "drep1abc") `shouldEqual` "/dreps/drep1abc"
      drepDetailHrefFor "drep1abc" `shouldEqual` "/dreps/drep1abc"

    it "does not turn a trailing slash into a detail route with an empty id" do
      -- `segment` din routing-duplex reușește pe un segment GOL, iar detaliul e declarat înaintea
      -- listei — deci `/profiles/` se parsa ca `ProfileDetail ""`, ecranul cerea `/profiles/` de la
      -- API, primea o pagină de listă și randa alerta de decodare. Garda e `nonEmptySegment`, într-un
      -- singur loc pentru toate cele cinci rute cu segment; testul e aici fiindcă defectul nu se
      -- vedea în niciuna din cele cinci suite.
      parseRoute "/profiles/" `shouldEqual` R.ProfileList emptyRegistryFilters
      parseRoute "/attestations/" `shouldEqual` R.AttestationList emptyRegistryFilters
      parseRoute "/disputes/" `shouldEqual` R.DisputeList emptyRegistryFilters
      parseRoute "/dreps/" `shouldEqual` R.DRepList emptyDRepFilters
      parseRoute "/gov-actions/" `shouldEqual` R.ActionList emptyGovActionFilters

    it "but the codec itself still refuses it, which is why Main normalises before the router" do
      -- Aserțiunea de deasupra trece prin `parseRoute`, care NU e pe drumul de rulare:
      -- `AppBase.purs` cheamă `mkRouter routeCodec`, deci routerul parsează cu CODECUL. Prima
      -- variantă a reparației a pus normalizarea numai în `parseRoute`, testul a trecut, și
      -- `/profiles/` dădea tot „Not found" în browser — verificat pe bundle-ul de producție.
      -- Reparația vie e `normaliseTrailingSlash` din `App.SpaLinkInterceptor`, chemată din `Main`.
      -- Testul ăsta fixează motivul: dacă vreodată codecul începe să accepte segmentul gol, cade
      -- singur, și atunci FFI-ul poate dispărea.
      case parse routeCodec "/profiles/" of
        Left _ -> pure unit
        Right _ -> fail "the codec accepted a trailing slash, so Main's normalisation is now dead code"

    it "puts every detail route in its list's section, and ignores the filters" do
      -- `sameSection` exista în DOUĂ locuri — `NavBar` pe șiruri, `Sidebar` pe perechi — și
      -- amândouă au trebuit editate pentru fiecare din cele trei rute de detaliu adăugate
      -- săptămâna asta. Acum există un singur `Route.section`, iar astea sunt cele două invariante
      -- pe care barele se sprijină. Testul cade dacă următoarea rută de detaliu primește o secțiune
      -- proprie — adică exact cazul în care o bară ar lumina și cealaltă nu.
      section (R.DRepDetail "x") `shouldEqual` section (R.DRepList emptyDRepFilters)
      section (R.ActionDetail "x") `shouldEqual` section (R.ActionList emptyGovActionFilters)
      section (R.ProfileDetail "x") `shouldEqual` section (R.ProfileList emptyRegistryFilters)
      section (R.AttestationDetail "x") `shouldEqual` section (R.AttestationList emptyRegistryFilters)
      section (R.DisputeDetail "x") `shouldEqual` section (R.DisputeList emptyRegistryFilters)

      -- Filtrele nu schimbă secțiunea: altfel `/profiles?kind=auditor` ar stinge „Profiles", ceea
      -- ce comentariul din `Sidebar` numea „exact pe dos".
      section (R.ProfileList (emptyRegistryFilters { kind = Just "auditor" }))
        `shouldEqual` section (R.ProfileList emptyRegistryFilters)
      section (R.AttestationList (emptyRegistryFilters { kind = Just "credential_claim" }))
        `shouldEqual` section (R.AttestationList emptyRegistryFilters)

    it "percent-encodes an id that would otherwise cut the request short" do
      -- Un ID de acțiune de guvernanță conține `#` prin construcție; același codor îl deservește.
      drepDetailHrefFor "abc#0" `shouldEqual` "/dreps/abc%230"

  describe "safeHref" do
    it "accepts the two schemes a browser can open without running code" do
      safeHref "https://example.org/x" `shouldEqual` Just "https://example.org/x"
      safeHref "http://example.org" `shouldEqual` Just "http://example.org"
      safeHref "HTTPS://EXAMPLE.ORG" `shouldEqual` Just "HTTPS://EXAMPLE.ORG"
      safeHref "  https://example.org  " `shouldEqual` Just "https://example.org"

    it "refuses a scheme that executes" do
      -- Halogen scrie `href` prin proprietatea DOM, deci un `javascript:` de aici s-ar executa la
      -- clic. Textul ancorei e scris de oricine.
      isNothing (safeHref "javascript:alert(1)") `shouldEqual` true
      isNothing (safeHref "  javascript:alert(1)") `shouldEqual` true
      isNothing (safeHref "JavaScript:alert(1)") `shouldEqual` true
      isNothing (safeHref "data:text/html;base64,PHNjcmlwdD4=") `shouldEqual` true
      isNothing (safeHref "file:///etc/passwd") `shouldEqual` true
      isNothing (safeHref "/relative/path") `shouldEqual` true
      isNothing (safeHref "") `shouldEqual` true
      isNothing (safeHref "https:/example.org") `shouldEqual` true

  describe "clampText" do
    it "leaves a short text alone and cuts a long one" do
      clampText 10 "short" `shouldEqual` "short"
      clampText 4 "abcdefgh" `shouldEqual` "abcd…"
      String.length (clampText 2000 (String.joinWith "" (replicate 5000 "x"))) `shouldEqual` 2001

  describe "statusExplanation" do
    it "explains each state in words, and says which it cannot explain" do
      statusExplanation Nothing `shouldEqual` "This DRep registered without a metadata document."
      (statusExplanation (Just "hash_mismatch") == statusExplanation (Just "invalid_schema"))
        `shouldEqual` false
      String.contains (String.Pattern "does not match the hash")
        (statusExplanation (Just "hash_mismatch")) `shouldEqual` true
      String.contains (String.Pattern "something_new")
        (statusExplanation (Just "something_new")) `shouldEqual` true
