-- | Testele formatării. Două dintre ele sunt reguli de produs, nu cosmetică: o metrică absentă e
-- | „n/a", și ID-ul unui DRep apare lângă nume chiar când numele există.
module Test.FormatSpec (spec) where

import Prelude

import Components.Shared.DRepIdentity (identityText, shortId)
import Components.Shared.OnchainId (IdKind(..), explorerUrl)
import Data.Array (replicate)
import Data.Maybe (Maybe(..))
import Data.String as String
import Format (formatAda, formatInt, formatLag, formatPercent, groupDigits, humanize, matchLine, pluralize, roleLabel)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

longName :: String
longName = String.joinWith "" (replicate 100 "ab")

spec :: Spec Unit
spec = do
  describe "groupDigits" do
    it "leaves three digits or fewer alone" do
      groupDigits "7" `shouldEqual` "7"
      groupDigits "294" `shouldEqual` "294"

    it "groups from the right" do
      groupDigits "1000" `shouldEqual` "1,000"
      groupDigits "505754377" `shouldEqual` "505,754,377"

    it "keeps a minus sign attached to the first group" do
      groupDigits "-1234" `shouldEqual` "-1,234"

  describe "formatAda" do
    it "renders a large figure as whole ADA with separators" do
      formatAda 505754377083269.0 `shouldEqual` "505,754,377 ADA"

    it "keeps two decimals only below one ADA, so a column of sums aligns" do
      -- Pragul vechi era la 1000, deci aceeași coloană amesteca „1,000,000 ADA", „42.00 ADA" și
      -- „0.00 ADA", iar zecimalele nu se aliniau cu nimic. Sub 1 ADA zecimalele rămân, fiindcă
      -- acolo rotunjirea ar transforma o sumă reală în zero.
      formatAda 42000000.0 `shouldEqual` "42 ADA"
      formatAda 500000.0 `shouldEqual` "0.50 ADA"

    it "says plain zero instead of a rounded-looking 0.00" do
      formatAda 0.0 `shouldEqual` "0 ADA"

    it "renders exactly a thousand ADA with separators" do
      formatAda 1000000000.0 `shouldEqual` "1,000 ADA"

  describe "matchLine" do
    it "says nothing when there is nothing, because the empty card says it better" do
      -- Masurat pe deployul de preprod: linia si cardul de sub ea scriau aceeasi propozitie, una
      -- sub alta, si asta era tot ce se vedea pe ecran.
      matchLine 0 0 0 "DRep" `shouldEqual` ""
      matchLine 12 0 0 "DRep" `shouldEqual` ""

    it "counts the whole set and names the page inside it" do
      matchLine 294 20 20 "DRep" `shouldEqual` "294 DReps match, showing 21–40"

  describe "formatPercent" do
    it "says n/a for an absent metric, never 0%" do
      -- `rationale_rate` e null când nimic n-a putut fi evaluat (172 din 200 de DRep-i măsurați).
      -- „0%" ar fi o acuzație la adresa autorului, nu o constatare despre date.
      formatPercent Nothing `shouldEqual` "n/a"

    it "renders a rate with one decimal" do
      formatPercent (Just 0.09523809523809523) `shouldEqual` "9.5%"
      formatPercent (Just 0.0) `shouldEqual` "0.0%"
      formatPercent (Just 1.0) `shouldEqual` "100.0%"

  describe "formatInt" do
    it "groups counts" do
      formatInt 294 `shouldEqual` "294"
      formatInt 137243408 `shouldEqual` "137,243,408"

  describe "pluralize" do
    it "keeps the singular at one and pluralizes everything else" do
      pluralize 1 "vote" `shouldEqual` "1 vote"
      pluralize 0 "vote" `shouldEqual` "0 votes"
      pluralize 1234 "vote" `shouldEqual` "1,234 votes"

  describe "formatLag" do
    it "writes a two-year lag in days, not in seconds" do
      -- Masurat pe deploy, cu db-sync refacind istoria: banda scria „58155804s behind". E corect
      -- si inutilizabil — nimeni nu imparte 58 de milioane la 86400 in cap.
      formatLag 58155804 `shouldEqual` "673.1 d behind"

    it "keeps seconds where seconds are the unit of the question" do
      formatLag 0 `shouldEqual` "live"
      formatLag 43 `shouldEqual` "43s behind"
      formatLag 600 `shouldEqual` "10 min behind"
      formatLag 7200 `shouldEqual` "2.0 h behind"

  describe "humanize" do
    it "turns a server enum into a label" do
      humanize "treasury_withdrawals" `shouldEqual` "Treasury withdrawals"
      humanize "info_action" `shouldEqual` "Info action"
      humanize "proposed" `shouldEqual` "Proposed"

    it "writes the two acronyms the way the ecosystem writes them" do
      -- Maparea mecanica din snake_case da „Drep registered", care pe un site public arata ca o
      -- greseala de scriere. Apare pe fiecare pastila de filtru din fluxul de activitate.
      humanize "drep_registered" `shouldEqual` "DRep registered"
      humanize "delegation_changed" `shouldEqual` "Delegation changed"

  describe "roleLabel" do
    it "keeps the abbreviations the ecosystem writes" do
      roleLabel "drep" `shouldEqual` "DRep"
      roleLabel "spo" `shouldEqual` "SPO"
      roleLabel "constitutional_committee" `shouldEqual` "Constitutional committee"
      roleLabel "something_else" `shouldEqual` "Something else"

  describe "shortId" do
    it "keeps the prefix and the tail of a bech32 id" do
      shortId "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm"
        `shouldEqual` "drep1ygzlzlzj8…z9rwhm"

    it "leaves a short id alone" do
      shortId "drep1abc" `shouldEqual` "drep1abc"

  describe "identityText" do
    it "shows the id even when the DRep has a name" do
      -- R3. Amenințarea e impersonarea, nu injecția: două profiluri pot revendica „Intersect" în
      -- același timp, deci numele singur nu identifică nimic.
      let
        t = identityText
          { givenName: Just "Intersect"
          , drepId: "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm"
          , hasScript: false
          }
      t.name `shouldEqual` "Intersect"
      t.named `shouldEqual` true
      t.id `shouldEqual` "drep1ygzlzlzj8…z9rwhm"

    it "falls back to a label when there is no name, and still shows the id" do
      let t = identityText { givenName: Nothing, drepId: "drep1abcdefghijklmnop", hasScript: true }
      t.name `shouldEqual` "Unnamed DRep"
      t.named `shouldEqual` false
      t.id `shouldEqual` "drep1abcdefghijklmnop"

    it "treats a blank name as no name" do
      let t = identityText { givenName: Just "   ", drepId: "drep1abc", hasScript: false }
      t.name `shouldEqual` "Unnamed DRep"

    it "clamps a name at render time, not in CSS" do
      -- R2. Un nume de 200 de caractere vine dintr-un document pe care îl scrie oricine.
      let t = identityText { givenName: Just longName, drepId: "drep1abc", hasScript: false }
      String.length t.name `shouldEqual` 81

  -- Adresele din explorer. Fiecare a fost deschisă într-un browser pe `preprod.cexplorer.io`
  -- înainte de a fi scrisă, iar testul le fixează — o cale greșită nu dă eroare, dă pagina de
  -- pornire a explorerului, ceea ce arată ca „nu există" și nu ca „am greșit linkul".
  describe "explorer links" do
    it "an asset keeps the dot between policy and name" do
      -- MĂSURAT: `/asset/<policy>.<name>` se rezolvă și explorerul afișează `asset1…`; fără punct
      -- cade pe pagina de pornire. De aceea id-ul nu se curăță, se trimite cum e.
      explorerUrl "https://preprod.cexplorer.io" Asset "aa.bb"
        `shouldEqual` "https://preprod.cexplorer.io/asset/aa.bb"

    it "a transaction goes to /tx" do
      explorerUrl "https://preprod.cexplorer.io" Tx "deadbeef"
        `shouldEqual` "https://preprod.cexplorer.io/tx/deadbeef"

    it "a DRep goes to /drep, bech32 as-is" do
      explorerUrl "https://preprod.cexplorer.io" DRep "drep1abc"
        `shouldEqual` "https://preprod.cexplorer.io/drep/drep1abc"

    it "a policy goes to /policy" do
      explorerUrl "https://preprod.cexplorer.io" Policy "aa"
        `shouldEqual` "https://preprod.cexplorer.io/policy/aa"
