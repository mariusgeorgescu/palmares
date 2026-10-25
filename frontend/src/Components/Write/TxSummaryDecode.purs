-- | Pasul CBOR → JSON, singurul care are nevoie de `cardano-serialization-lib`.
-- |
-- | O linie de cod și un import, separate de `Components.Write.TxSummary` dintr-un motiv măsurat:
-- | `Csl` trage după el un modul wasm pe care Node nu-l poate rezolva, iar cît timp cele două
-- | stăteau în același modul întreaga suită de teste murea la import. Extragerea din JSON — care e
-- | codul nostru și unde pot fi greșeli — rămâne pură și testată dincolo.
module Components.Write.TxSummaryDecode
  ( summarise
  ) where

import Prelude

import Components.Write.TxSummary (TxSummary, summariseJson)
import Csl as Csl
import Data.Maybe (Maybe)

-- | Din CBOR hex, sumarul. `Nothing` înseamnă „nu s-a putut decoda" — iar ecranul trebuie să
-- | REFUZE semnarea atunci, nu să treacă mai departe cu CBOR-ul la vedere: o tranzacție pe care
-- | n-o putem citi e exact cazul pe care R8 îl interzice.
summarise :: String -> Maybe TxSummary
summarise hex = do
  tx <- Csl.tx.fromHex hex
  summariseJson (Csl.txBody.toJson (Csl.tx.body tx))
