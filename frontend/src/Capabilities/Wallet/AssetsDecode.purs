-- | Pasul CBOR → JSON pentru balanța portofelului, singurul care are nevoie de
-- | `cardano-serialization-lib`.
-- |
-- | Separat de `Capabilities.Wallet.Assets` din exact același motiv măsurat ca la
-- | `Components.Write.TxSummaryDecode`: `Csl` trage după el un modul wasm pe care Node nu-l poate
-- | rezolva, iar cît timp codul pur stă în același modul, suita de teste moare la IMPORT.
module Capabilities.Wallet.AssetsDecode
  ( balanceJson
  ) where

import Prelude

import Csl as Csl
import Data.Maybe (Maybe)

-- | Din CBOR-ul întors de `getBalance`, JSON-ul valorii. `Nothing` cînd nu se poate decoda — iar
-- | atunci ecranul spune că nu poate citi activele, nu că portofelul nu deține niciun profil.
balanceJson :: String -> Maybe String
balanceJson hex = Csl.value.toJson <$> Csl.value.fromHex hex
