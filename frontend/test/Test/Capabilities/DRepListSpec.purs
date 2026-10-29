-- | Testele listei de DRep-i. Jumătate sunt despre decodare, jumătate despre singura parte a
-- | ecranului care poate minți cu numere corecte: facetele.
module Test.Capabilities.DRepListSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures (drepExplorerFixture)
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types (DRepExplorerPage(..), PowerBucket(..))
import Components.Explorer.DRepList (bucketLabel, facetLabel, sortToggle)
import Data.Array (last, length)
import Data.Either (Either(..))
import Data.Foldable (sum)
import Data.Maybe (Maybe(..), isNothing)
import Data.Tuple (snd)
import Effect.Aff (Aff)
import Route (Route(..))
import Route.Codec (parseRoute, printRoute)
import Data.Array (sort) as Array
import Data.String as String
import Route.GovQueries
  ( attestationListHrefFor
  , disputeListHrefFor
  , emptyDRepFilters
  , emptyRegistryFilters
  , profileListHrefFor
  , renderDRepFilters
  , toggleIn
  )
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

withExplorer :: (DRepExplorerPage -> Aff Unit) -> Aff Unit
withExplorer k = case (decodeFixture drepExplorerFixture :: Either ApiError DRepExplorerPage) of
  Left e -> fail ("fixture did not decode: " <> show e)
  Right p -> k p

spec :: Spec Unit
spec = do
  describe "DRepExplorerPage decoding" do
    it "decodes the measured payload" do
      withExplorer \(DRepExplorerPage p) -> do
        p.total `shouldEqual` 294
        p.limit `shouldEqual` 4
        p.offset `shouldEqual` 0
        p.epoch `shouldEqual` 321
        length p.items `shouldEqual` 4
        length p.statusFacets `shouldEqual` 4
        length p.anchorFacets `shouldEqual` 4
        length p.languageFacets `shouldEqual` 2
        length p.powerBuckets `shouldEqual` 6

    it "does NOT let the facets add up to the total" do
      -- 17+187+526+90 = 820 pe un total de 294. Fiecare facet se numără cu propriul predicat scos,
      -- deci orice procent calculat dintr-un facet ar fi un număr inventat. Testul fixează faptul
      -- ca să nu-l „repare" cineva mai târziu.
      withExplorer \(DRepExplorerPage p) -> do
        sum (map snd p.statusFacets) `shouldEqual` 820
        (sum (map snd p.statusFacets) == p.total) `shouldEqual` false
        -- Ancorele însumează mai puțin: un DRep fără ancoră nu intră în nicio categorie.
        sum (map snd p.anchorFacets) `shouldEqual` 131

    it "DOES let the power buckets add up to the total" do
      -- Singura desfășurare din care un procent are sens: fiecare DRep cade în exact un interval.
      withExplorer \(DRepExplorerPage p) ->
        sum (map (\(PowerBucket b) -> b.count) p.powerBuckets) `shouldEqual` p.total

    it "leaves the top bucket open-ended" do
      withExplorer \(DRepExplorerPage p) -> case last p.powerBuckets of
        Nothing -> fail "expected power buckets"
        Just (PowerBucket b) -> do
          isNothing b.hi `shouldEqual` true
          b.lo `shouldEqual` 1000000000000.0

  describe "renderDRepFilters" do
    it "repeats a multi-valued parameter" do
      renderDRepFilters (emptyDRepFilters { status = [ "active", "inactive" ] })
        `shouldEqual` "?status=active&status=inactive"

    it "never emits order_by without sort_order" do
      -- `order_by` singur înseamnă `asc` pe server, deci „sortează după putere" ar arăta cei mai
      -- slabi primii — și URL-ul dat mai departe n-ar spune de ce.
      renderDRepFilters (emptyDRepFilters { order_by = Just "voting_power" })
        `shouldEqual` "?order_by=voting_power&sort_order=asc"
      renderDRepFilters (emptyDRepFilters { order_by = Just "voting_power", sort_order = Just "desc" })
        `shouldEqual` "?order_by=voting_power&sort_order=desc"

    it "drops a lone sort_order, which the server would ignore anyway" do
      renderDRepFilters (emptyDRepFilters { sort_order = Just "desc" }) `shouldEqual` ""

    it "percent-encodes a search term" do
      renderDRepFilters (emptyDRepFilters { q = Just "a&b c#d" })
        `shouldEqual` "?q=a%26b%20c%23d"

  -- Testul care lipsea când a plecat defectul, și singurul care îl prinde structural.
  --
  -- `RegistryFilters` are DOUĂ consumatori care trebuie să spună același lucru: codecul rutei, care
  -- produce adresa din browser, și `registryPairs`, care produce interogarea trimisă serverului.
  -- `kind` fusese adăugat numai în primul: URL-ul îl purta, titlul paginii se schimba corect, și
  -- cererea pleca NEFILTRATĂ — un titlu „Verified credentials" peste toate cele 22 de rânduri.
  --
  -- Aserțiunile pe câmpuri individuale n-ar fi prins-o, fiindcă un câmp nou n-ar avea aserțiune.
  -- Comparația dintre cele două ieșiri o prinde: dacă un câmp intră în codec și nu în
  -- `registryPairs`, mulțimile de parametri diverg și testul cade singur.
  describe "the registry filters reach BOTH the URL and the request" do
    let
      -- Parametrii, ca mulțime sortată: ordinea lor nu e un contract, prezența lor este.
      paramsOf href = case String.indexOf (String.Pattern "?") href of
        Nothing -> []
        Just i -> Array.sort (String.split (String.Pattern "&") (String.drop (i + 1) href))

      allSet =
        emptyRegistryFilters
          { order_by = Just "date"
          , sort_order = Just "desc"
          , limit = Just "25"
          , offset = Just "50"
          , kind = Just "credential_claim"
          , subject = Just "abc.def"
          , issuer = Just "ghi.jkl"
          }

    it "the route codec and the query builder agree on every field" do
      paramsOf (printRoute (AttestationList allSet)) `shouldEqual` paramsOf (attestationListHrefFor allSet)
      paramsOf (printRoute (ProfileList allSet)) `shouldEqual` paramsOf (profileListHrefFor allSet)
      paramsOf (printRoute (DisputeList allSet)) `shouldEqual` paramsOf (disputeListHrefFor allSet)

    it "and what they agree on is all seven fields, not an agreed silence" do
      -- Fără asta, două constructori care amândoi uită un câmp ar trece testul de deasupra.
      paramsOf (attestationListHrefFor allSet)
        `shouldEqual`
          [ "issuer=ghi.jkl"
          , "kind=credential_claim"
          , "limit=25"
          , "offset=50"
          , "order_by=date"
          , "sort_order=desc"
          , "subject=abc.def"
          ]

    it "emits nothing when nothing is set" do
      attestationListHrefFor emptyRegistryFilters `shouldEqual` "/attestations"

    it "emits nothing at all when nothing is filtered" do
      renderDRepFilters emptyDRepFilters `shouldEqual` ""

  describe "the DRep list route" do
    it "survives a round trip through the URL" do
      let
        filters = emptyDRepFilters
          { status = [ "active", "inactive" ]
          , language = [ "en-us" ]
          , order_by = Just "voting_power"
          , sort_order = Just "desc"
          , offset = Just "50"
          }
      parseRoute (printRoute (DRepList filters)) `shouldEqual` DRepList filters

    it "reads a hand-written URL with a repeated parameter" do
      parseRoute "/dreps?status=active&status=inactive"
        `shouldEqual` DRepList (emptyDRepFilters { status = [ "active", "inactive" ] })

    it "maps an unknown path to NotFound" do
      parseRoute "/nope" `shouldEqual` NotFound

  describe "sortToggle" do
    it "starts a new column descending" do
      -- Cine dă clic pe „putere de vot" întreabă cine are cea mai multă, nu cea mai puțină.
      let f = sortToggle "voting_power" emptyDRepFilters
      f.order_by `shouldEqual` Just "voting_power"
      f.sort_order `shouldEqual` Just "desc"

    it "flips the direction on the same column" do
      let f = sortToggle "voting_power" (sortToggle "voting_power" emptyDRepFilters)
      f.sort_order `shouldEqual` Just "asc"

    it "sends the reader back to the first page" do
      -- Sortarea schimbă ce e pe pagina 1; rămas pe offset 200, cineva ar vedea un gol fără motiv.
      let f = sortToggle "voting_power" (emptyDRepFilters { offset = Just "200" })
      isNothing f.offset `shouldEqual` true

  describe "toggleIn" do
    it "adds a value that is absent and removes one that is present" do
      toggleIn "active" [] `shouldEqual` [ "active" ]
      toggleIn "active" [ "active" ] `shouldEqual` []

    it "keeps the order values were added in, so the URL does not rewrite itself" do
      toggleIn "inactive" [ "active" ] `shouldEqual` [ "active", "inactive" ]
      toggleIn "active" [ "active", "inactive" ] `shouldEqual` [ "inactive" ]

  describe "facet and bucket labels" do
    it "names the empty language for what it is" do
      -- Măsurat: patru DRep-i au limba scrisă ca șir gol. Nu e același lucru cu „n-a declarat".
      facetLabel "language" "" `shouldEqual` "declared, but empty"
      facetLabel "status" "hash_mismatch" `shouldEqual` "Hash mismatch"

    it "leaves a language tag alone instead of capitalising it into something that does not exist" do
      -- `humanize` scotea „En-us", care nu e nici limbă, nici tag BCP-47.
      facetLabel "language" "en-us" `shouldEqual` "en-us"

    it "says a top bucket is open-ended instead of inventing a ceiling" do
      -- Unitatea stă o singură dată, în titlul blocului de filtre, nu pe fiecare etichetă.
      bucketLabel 1000000000000.0 Nothing `shouldEqual` "1,000,000 and up"
      -- `hi` e exclusiv, deci primul interval măsurat (0 → 1 lovelace) e „exact zero".
      bucketLabel 0.0 (Just 1.0) `shouldEqual` "No voting power"
      bucketLabel 1000000000.0 (Just 10000000000.0) `shouldEqual` "1,000 – 10,000"
