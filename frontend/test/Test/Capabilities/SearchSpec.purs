-- | Testele căutării unificate și ale paginii de metodologie.
module Test.Capabilities.SearchSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures (formulasFixture, searchFixture)
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types (Formula(..), SearchGroup(..), SearchHit(..), SearchResults(..))
import Components.Layout.SearchBox (debounceMs, hrefForHit)
import Data.Array (head, length, nub)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isNothing)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Effect.Aff (Aff)
import Route as R
import Route.Codec (parseRoute, printRoute)
import Route.GovQueries (emptyMethodologyFilters, methodologyHrefFor)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

withSearch :: (SearchResults -> Aff Unit) -> Aff Unit
withSearch k = case (decodeFixture searchFixture :: Either ApiError SearchResults) of
  Left e -> fail ("search fixture did not decode: " <> show e)
  Right r -> k r

withFormulas :: (Array Formula -> Aff Unit) -> Aff Unit
withFormulas k = case (decodeFixture formulasFixture :: Either ApiError (Array Formula)) of
  Left e -> fail ("formulas fixture did not decode: " <> show e)
  Right fs -> k fs

hit :: String -> String -> SearchHit
hit kind id = SearchHit
  { id
  , title: Nothing
  , subtitle: Nothing
  , badges: []
  , status: Nothing
  , targetKind: kind
  , targetId: id
  }

spec :: Spec Unit
spec = do
  describe "SearchResults decoding" do
    it "decodes the six groups, including the empty ones" do
      withSearch \(SearchResults r) -> do
        r.query `shouldEqual` "logical"
        r.total `shouldEqual` 3
        case r.dreps of
          SearchGroup g -> do
            g.total `shouldEqual` 3
            length g.items `shouldEqual` 3
        case r.govActions of
          SearchGroup g -> do
            g.total `shouldEqual` 0
            length g.items `shouldEqual` 0

    it "decodes a hit with its badges and its target" do
      withSearch \(SearchResults r) -> case r.dreps of
        SearchGroup g -> case head g.items of
          Nothing -> fail "expected a hit"
          Just (SearchHit h) -> do
            h.title `shouldEqual` Just "Logical Mechanism dRep"
            h.badges `shouldEqual` [ "script" ]
            h.status `shouldEqual` Just "retired"
            h.targetKind `shouldEqual` "drep"
            h.targetId `shouldEqual` "drep1yvv7culkq0nqlgs6gtmkryuwp3lq49k5rhu6c7y2n2psu8g08rvmk"

    it "returns three different DReps with the same name, which is the whole reason for R3" do
      -- Nu e un caz construit: căutarea „logical" pe preprod întoarce __trei__ credențiale
      -- distincte, toate intitulate „Logical Mechanism dRep", toate cu insigna `script`, cu stări
      -- diferite. Numele nu identifică nimic; de aceea ID-ul merge lângă el oriunde apare.
      withSearch \(SearchResults r) -> case r.dreps of
        SearchGroup g -> do
          map (\(SearchHit h) -> h.title) g.items `shouldEqual`
            [ Just "Logical Mechanism dRep", Just "Logical Mechanism dRep", Just "Logical Mechanism dRep" ]
          length (nub (map (\(SearchHit h) -> h.targetId) g.items)) `shouldEqual` 3
          map (\(SearchHit h) -> h.status) g.items `shouldEqual`
            [ Just "retired", Just "unknown", Just "inactive" ]

  describe "hrefForHit" do
    it "routes the two kinds that have a screen" do
      hrefForHit (hit "drep" "drep1abc") `shouldEqual` Just "/dreps/drep1abc"
      -- Același codor de segment: un ID de acțiune poartă `#`.
      hrefForHit (hit "gov_action" "abc#0") `shouldEqual` Just "/gov-actions/abc%230"

    it "refuses to link a kind with no screen, instead of pointing at not-found" do
      isNothing (hrefForHit (hit "spo" "pool1abc")) `shouldEqual` true
      isNothing (hrefForHit (hit "profile" "p1")) `shouldEqual` true
      isNothing (hrefForHit (hit "attestation" "a1")) `shouldEqual` true

  describe "debounce" do
    it "waits a quarter of a second, not a keystroke" do
      debounceMs `shouldEqual` Milliseconds 250.0

  describe "Formula decoding" do
    it "decodes a bare array, not an envelope" do
      withFormulas \fs -> length fs `shouldEqual` 2

    it "keeps the rule that decides n/a versus 0%" do
      withFormulas \fs -> case head fs of
        Nothing -> fail "expected a formula"
        Just (Formula f) -> do
          f.formulaId `shouldEqual` "participation_rate_v1"
          f.name `shouldEqual` "Participation rate"
          f.field `shouldEqual` Just "participation_rate"
          f.nullWhen `shouldEqual` Just "eligible_actions = 0"
          f.version `shouldEqual` Just 1
          length f.inputs `shouldEqual` 4
          length f.params `shouldEqual` 2
          (length f.edgeCases > 0) `shouldEqual` true

    it "carries the whole query, because that is the product" do
      withFormulas \fs -> case head fs of
        Nothing -> fail "expected a formula"
        Just (Formula f) -> case f.sql of
          Nothing -> fail "expected SQL"
          Just sql -> do
            String.contains (String.Pattern "WITH p AS") sql `shouldEqual` true
            -- Fixtura nu e ciuntită: SQL-ul se termină cu punct și virgulă, ca cel real.
            String.contains (String.Pattern "open_actions_unvoted;") sql `shouldEqual` true

  describe "the methodology route" do
    it "points at a formula with a parameter, not a fragment" do
      -- Interceptorul de linkuri face `pushState`, iar `pushState` nu derulează la ancoră: un
      -- `#id` ar arăta ca un link care nu face nimic.
      methodologyHrefFor "participation_rate_v1"
        `shouldEqual` "/methodology?focus=participation_rate_v1"

    it "round-trips" do
      parseRoute "/methodology?focus=rationale_rate_v1"
        `shouldEqual` R.Methodology { focus: Just "rationale_rate_v1" }
      parseRoute "/methodology" `shouldEqual` R.Methodology emptyMethodologyFilters
      printRoute (R.Methodology { focus: Just "x" }) `shouldEqual` "/methodology?focus=x"
