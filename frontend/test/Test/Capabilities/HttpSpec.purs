-- | Testele părții pure a transportului. Fiecare caz e un răspuns pe care serviciul care rulează
-- | chiar îl produce, nu unul inventat — sursele sunt `docs/usecases/api-screen-map.md` §3.4 și
-- | `Query/Gov.hs:638-664`.
-- |
-- | Aserțiunile nu compară niciodată direct un `Either ApiError Json`: `Json` nu are instanță de
-- | `Show`, deci `shouldEqual` pe el nici nu compilează. Cele două ajutoare de mai jos despică
-- | întâi cazul, apoi compară ce se poate afișa.
module Test.Capabilities.HttpSpec (spec) where

import Prelude

import Affjax.ResponseHeader (ResponseHeader(..))
import Capabilities.Query.Gov.Http (ApiError(..), classifyResponse, errorCodeForStatus, isRetryable, lookupHeader, readFreshness)
import Data.Argonaut.Core (Json)
import Data.Argonaut.Decode (decodeJson)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

-- | „Clasificarea a reușit ȘI corpul se decodează în ce aștept", într-o singură aserțiune. Pe
-- | valoarea decodată, nu pe `Json`-ul intermediar: un test care compară cu `jsonParser` al
-- | aceluiași corp ar fi doar o oglindă a implementării.
shouldDecodeTo :: Either ApiError Json -> { total :: Int } -> Aff Unit
shouldDecodeTo actual expected = case actual of
  Left e -> fail ("expected a classified 2xx body, got " <> show e)
  Right json -> decodeJson json `shouldEqual` Right expected

shouldFailWith :: Either ApiError Json -> ApiError -> Aff Unit
shouldFailWith actual expected = case actual of
  Right _ -> fail ("expected " <> show expected <> ", got a classified body")
  Left e -> e `shouldEqual` expected

shouldFailToParse :: Either ApiError Json -> Aff Unit
shouldFailToParse actual = case actual of
  Right _ -> fail "expected a parse failure on a 2xx body that is not JSON"
  Left (Decode _) -> pure unit
  Left e -> fail ("expected Decode, got " <> show e)

spec :: Spec Unit
spec = do
  describe "classifyResponse" do
    it "decodes a 2xx body" do
      shouldDecodeTo (classifyResponse 200 """{"total":3}""") { total: 3 }

    it "classifies 2xx by range, not by equality with 200" do
      shouldDecodeTo (classifyResponse 204 """{"total":0}""") { total: 0 }

    it "surfaces {code,message} from a 4xx instead of a decode error" do
      -- Măsurat: `GET /drep/garbage` → 400 cu exact corpul ăsta.
      shouldFailWith
        (classifyResponse 400 """{"code":"invalid_drep_id","message":"Not a DRep identifier"}""")
        (Api { code: "invalid_drep_id", message: "Not a DRep identifier" })

    it "survives an EMPTY body on 403" do
      -- Credențiale greșite pe interaction-api dau 403, nu 401, și corpul e gol. Varianta cu
      -- `ResponseFormat.json` eșua aici cu o eroare despre JSON în loc de una despre credențiale.
      shouldFailWith (classifyResponse 403 "")
        (Api { code: "forbidden", message: "The service answered 403 with an empty body." })

    it "survives a non-JSON body on 503" do
      -- `attest-sync` întoarce la 503 un `show` de Haskell (`ChainsyncAPI.hs:63`).
      shouldFailWith (classifyResponse 503 "ServiceUnavailable")
        (Api { code: "db_unavailable", message: "ServiceUnavailable" })

    it "keeps a 503 that DOES carry the contract" do
      shouldFailWith
        (classifyResponse 503 """{"code":"db_unavailable","message":"Service temporarily unavailable"}""")
        (Api { code: "db_unavailable", message: "Service temporarily unavailable" })

    it "reports a parse failure on a 200 that is not JSON" do
      -- Un proxy care se pune în fața serviciului poate răspunde 200 cu o pagină HTML.
      shouldFailToParse (classifyResponse 200 "<html>502 Bad Gateway</html>")

  describe "errorCodeForStatus" do
    it "names the statuses this API actually returns" do
      errorCodeForStatus 400 `shouldEqual` "bad_request"
      errorCodeForStatus 403 `shouldEqual` "forbidden"
      errorCodeForStatus 406 `shouldEqual` "not_acceptable"
      errorCodeForStatus 503 `shouldEqual` "db_unavailable"

    it "falls back to the status for anything else" do
      errorCodeForStatus 418 `shouldEqual` "http_418"

  describe "isRetryable" do
    it "retries a transport failure" do
      isRetryable (Transport "timeout") `shouldEqual` true

    it "NEVER retries db_unavailable" do
      -- Măsurat: /drep/{id} dădea 503 la 30,3 s în timp ce /dreps răspundea în 0,69 s. Query-ul
      -- abandonat macină mai departe în Postgres, deci o reîncercare compune sarcina care a produs
      -- timeout-ul.
      isRetryable (Api { code: "db_unavailable", message: "x" }) `shouldEqual` false

  describe "readFreshness" do
    it "reads all eight headers when they are present" do
      let
        f = readFreshness
          [ ResponseHeader "X-Chain-Epoch" "321"
          , ResponseHeader "X-Chain-Slot" "137140009"
          , ResponseHeader "X-Chain-Block-Time" "2026-10-24T06:26:49Z"
          , ResponseHeader "X-Data-Lag-Seconds" "43"
          , ResponseHeader "X-Data-Source" "cardano-db-sync"
          , ResponseHeader "X-Attest-Slot" "137140009"
          , ResponseHeader "X-Attest-Lag-Seconds" "0"
          , ResponseHeader "X-Attest-State" "following"
          ]
      f.chainEpoch `shouldEqual` Just 321
      f.chainSlot `shouldEqual` Just 137140009
      f.chainBlockTime `shouldEqual` Just "2026-10-24T06:26:49Z"
      f.dataLagSeconds `shouldEqual` Just 43
      f.dataSource `shouldEqual` Just "cardano-db-sync"
      f.attestSlot `shouldEqual` Just 137140009
      f.attestLagSeconds `shouldEqual` Just 0
      f.attestState `shouldEqual` Just "following"

    it "yields Nothing for every field when the headers are absent" do
      -- Un deploy doar-guvernanță nu are proiector, deci cele trei `X-Attest-*` lipsesc cu totul.
      let f = readFreshness []
      f.chainEpoch `shouldEqual` Nothing
      f.attestState `shouldEqual` Nothing
      f.dataSource `shouldEqual` Nothing

    it "matches header names case-insensitively" do
      -- Browserele dau numele minuscule; o comparație exactă ar găsi zero headere în browser și
      -- toate în teste, care e cel mai prost fel de bug.
      let f = readFreshness [ ResponseHeader "x-chain-epoch" "321" ]
      f.chainEpoch `shouldEqual` Just 321

    it "treats an unparseable numeric header as absent, not as zero" do
      let f = readFreshness [ ResponseHeader "X-Chain-Epoch" "soon" ]
      f.chainEpoch `shouldEqual` Nothing

  describe "lookupHeader" do
    it "returns Nothing for a header that is not there" do
      lookupHeader "X-Nope" [ ResponseHeader "X-Chain-Epoch" "321" ] `shouldEqual` Nothing
