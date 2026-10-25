-- | Testele pentru regulile de paginare. Fiecare număr de aici e un clamp măsurat pe serviciul care
-- | rulează, nu unul citit din swagger — swagger-ul declară intervalul Int64 pentru `limit` și
-- | `offset` și nu publică niciunul dintre plafoanele reale.
module Test.Query.PageSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset, votesOffsetCeiling)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "clampLimit" do
    it "clamps above the maximum" do
      clampLimit listLimitMax 100000 `shouldEqual` 200

    it "clamps zero to one" do
      -- Serverul clampează oricum, dar un `limit=0` trimis randează o pagină goală ca „nu există
      -- date", care e o minciună despre 294 de DRep-i.
      clampLimit listLimitMax 0 `shouldEqual` 1

    it "clamps negatives to one" do
      clampLimit listLimitMax (-5) `shouldEqual` 1

    it "leaves a legal limit alone" do
      clampLimit listLimitMax 50 `shouldEqual` 50

  describe "nextOffset" do
    it "advances inside the result set" do
      nextOffset offsetCeiling 50 0 120 `shouldEqual` Just 50

    it "stops at the end of the result set" do
      nextOffset offsetCeiling 50 100 120 `shouldEqual` Nothing

    it "stops before the hard offset ceiling" do
      -- offset=10000 răspunde, offset=10001 dă 400 offset_too_large. Un pager care trimite orbește
      -- pierde pagina și arată o eroare în loc de capătul listei.
      nextOffset offsetCeiling 50 9980 50000 `shouldEqual` Nothing

    it "allows the last legal page" do
      nextOffset offsetCeiling 50 9950 50000 `shouldEqual` Just 10000

    it "stops at the votes ceiling, well below the server's" do
      -- 1,1 s la 600, 12,15 s la 800. ADR 0009: nu se repară, deci ne oprim înaintea treptei.
      nextOffset votesOffsetCeiling 50 600 50000 `shouldEqual` Nothing
      nextOffset votesOffsetCeiling 50 550 50000 `shouldEqual` Just 600

  describe "prevOffset" do
    it "has no previous page at the start" do
      prevOffset 50 0 `shouldEqual` Nothing

    it "steps back a page" do
      prevOffset 50 100 `shouldEqual` Just 50

    it "clamps a partial step back to zero rather than going negative" do
      prevOffset 50 20 `shouldEqual` Just 0
