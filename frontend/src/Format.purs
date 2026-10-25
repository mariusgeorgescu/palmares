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
  , formatPercent
  , groupDigits
  , humanize
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

formatAda :: Lovelace -> String
formatAda lovelace =
  let
    ada = lovelace / 1000000.0
  in
    if ada >= 1000.0 || ada <= -1000.0 then groupDigits (toStringWith (fixed 0) ada) <> " ADA"
    else toStringWith (fixed 2) ada <> " ADA"

-- | O rată din răspuns (0..1) ca procent cu o zecimală. `Nothing` e „n/a", nu zero.
formatPercent :: Maybe Number -> String
formatPercent = case _ of
  Nothing -> "n/a"
  Just r -> toStringWith (fixed 1) (r * 100.0) <> "%"

-- | `1 vote`, `0 votes`. Textul e public și în engleză, deci „1 votes" e o greșeală vizibilă.
pluralize :: Int -> String -> String
pluralize n word = formatInt n <> " " <> word <> (if n == 1 then "" else "s")

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
