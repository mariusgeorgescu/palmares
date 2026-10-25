-- | Formatarea cifrelor pentru ecran. Un singur loc, pentru că aici stau două reguli de produs, nu
-- | doar cosmetică:
-- |
-- |   * o metrică absentă se randează __„n/a"__, niciodată „0%". `rationale_rate` e `null` când
-- |     nimic n-a putut fi evaluat (lipsea la 172 din 200 de DRep-i măsurați), iar „0%" ar fi o
-- |     acuzație la adresa autorului în loc de o constatare despre date;
-- |   * lovelace se afișează ca ADA, cu separatori, pentru că o cifră de 15 caractere fără
-- |     separatori nu e citibilă — iar sub 1000 de ADA se arată două zecimale, ca o sumă mică să nu
-- |     fie rotunjită la zero.
module Format
  ( formatAda
  , formatInt
  , formatAdaOnly
  , formatDay
  , formatHours
  , formatPercent
  , groupDigits
  , humanize
  , matchLine
  , pluralize
  , roleLabel
  ) where

import Prelude

import Capabilities.Query.Gov.Types (Lovelace)
import Data.Maybe (Maybe(..))
import Data.Number.Format (fixed, toStringWith)
import Data.String as String
import Data.String.CodeUnits as CU

-- | Grupează cifrele din trei în trei, de la dreapta. Semnul minus rămâne lipit de prima grupă,
-- | pentru că recursia taie mereu ultimele trei caractere și se oprește la cel mult trei rămase.
groupDigits :: String -> String
groupDigits s
  | String.length s <= 3 = s
  | otherwise =
      let
        { before, after } = CU.splitAt (String.length s - 3) s
      in
        groupDigits before <> "," <> after

formatInt :: Int -> String
formatInt = groupDigits <<< show

-- | Suma în ADA, fără unitate. Unitatea se lipește în `formatAda`; cine o declară o singură dată pe
-- | ecran (titlul unei coloane, al unui bloc de filtre) folosește varianta asta și nu o repetă pe
-- | fiecare rând.
-- |
-- | Pragul e la 1 ADA, nu la 1000: cu pragul vechi aceeași coloană amesteca „1,000,000 ADA",
-- | „42.00 ADA" și „0.00 ADA", iar într-o coloană monospace aliniată la dreapta zecimalele nu se
-- | aliniau cu nimic. Zero are cazul lui, pentru că „0.00" se citește ca o sumă măruntă rotunjită,
-- | când de fapt nu există nicio sumă.
formatAdaOnly :: Lovelace -> String
formatAdaOnly lovelace =
  let
    ada = lovelace / 1000000.0
  in
    if ada == 0.0 then "0"
    else if ada >= 1.0 || ada <= -1.0 then groupDigits (toStringWith (fixed 0) ada)
    else toStringWith (fixed 2) ada

formatAda :: Lovelace -> String
formatAda lovelace = formatAdaOnly lovelace <> " ADA"

-- | Data unui eveniment, fără ora. ISO-8601 e fix-width, deci primele zece caractere sunt exact
-- | `YYYY-MM-DD` — nicio parsare de dată și nicio dependență nouă. Ora exactă rămâne în `title`
-- | acolo unde contează: pentru cineva care alege cui deleagă, secundele sunt zgomot.
formatDay :: String -> String
formatDay = CU.take 10

-- | Cât a durat, în unitatea pe care o citește un om. Peste două zile, orele cer o împărțire în
-- | cap: „346.6 h" e „paisprezece zile". Pragul e la 48 și nu la 24, ca „30 h" să nu devină „1.3 d",
-- | care e mai greu de citit decât orele.
formatHours :: Number -> String
formatHours h =
  if h < 48.0 then toStringWith (fixed 1) h <> " h"
  else toStringWith (fixed 1) (h / 24.0) <> " d"

-- | O rată din răspuns (0..1) ca procent cu o zecimală. `Nothing` e „n/a", nu zero.
formatPercent :: Maybe Number -> String
formatPercent = case _ of
  Nothing -> "n/a"
  Just r -> toStringWith (fixed 1) (r * 100.0) <> "%"

-- | `1 vote`, `0 votes`. Textul e public și în engleză, deci „1 votes" e o greșeală vizibilă.
pluralize :: Int -> String -> String
pluralize n word = formatInt n <> " " <> word <> (if n == 1 then "" else "s")

-- | Linia de deasupra unui tabel de rezultate. Zero potriviri nu promite un interval: „showing
-- | 1–0" e o propoziție care nu înseamnă nimic, iar un tabel gol sub ea arată ca un defect.
matchLine :: Int -> Int -> Int -> String -> String
matchLine total offset shown noun =
  if total == 0 || shown == 0 then "No " <> noun <> "s match these filters."
  else
    pluralize total noun <> " match, showing "
      <> formatInt (offset + 1)
      <> "–"
      <> formatInt (offset + shown)

-- | Rolurile de votant au majuscule proprii: `humanize` ar da „Drep" și „Spo", care pe un site
-- | public arată ca o greșeală, nu ca o abreviere.
roleLabel :: String -> String
roleLabel = case _ of
  "drep" -> "DRep"
  "spo" -> "SPO"
  "constitutional_committee" -> "Constitutional committee"
  "committee_member" -> "Committee member"
  other -> humanize other

-- | `treasury_withdrawals` → `Treasury withdrawals`. Serverul publică enum-urile în snake_case;
-- | ecranul le arată ca text, iar maparea e mecanică — deci nu există o listă de etichete de
-- | întreținut care s-ar putea dezacorda de la enum.
humanize :: String -> String
humanize s = case String.uncons spaced of
  Nothing -> spaced
  Just { head, tail } -> String.toUpper (String.singleton head) <> tail
  where
  spaced = String.replaceAll (String.Pattern "_") (String.Replacement " ") s
