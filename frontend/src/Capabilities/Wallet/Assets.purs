-- | Ce profiluri deține wallet-ul conectat, citite din propriile lui active.
-- |
-- | Un profil e un token CIP-68 în două jumătăți: REFERINȚA (`000643b0…`), blocată la validator cu
-- | datumul, și jumătatea de UTILIZATOR (`000de140…`), care ajunge în portofelul proprietarului.
-- | Diferă doar prin cele patru octeți de etichetă CIP-67. Deci întrebarea „ce profiluri sînt ale
-- | mele" se răspunde fără niciun server: se citesc activele portofelului și se păstrează cele cu
-- | eticheta de utilizator, sub politica registrului.
-- |
-- | Derivarea user→referință NU se face aici, și e o decizie a serverului: ruta
-- | `/profiles/by-user-token/{asset-class}` o face, iar documentația ei spune de ce — „protocol
-- | knowledge no frontend should carry". Noi trimitem clasa de activ așa cum vine din portofel.
-- |
-- | Partea asta e pură ca să poată fi testată: decodarea CBOR→JSON trage după ea un modul wasm pe
-- | care Node nu-l poate încărca, iar cît timp cele două stau în același modul suita de teste moare
-- | la import. Aceeași separare ca la `Components.Write.TxSummaryDecode`.
module Capabilities.Wallet.Assets
  ( userTokenLabel
  , userTokenAssetClasses
  ) where

import Prelude

import Data.Argonaut.Core (Json, toObject)
import Data.Argonaut.Parser (jsonParser)
import Data.Array (filter, sort)
import Data.Either (hush)
import Data.Maybe (Maybe, fromMaybe)
import Data.String as String
import Foreign.Object as Object

-- | Eticheta CIP-67 a jumătății de utilizator, în hex. Tot ce nu începe cu ea nu e un token de
-- | proprietate: referința (`000643b0`) stă la validator, iar atestările și disputele folosesc
-- | etichete de uz privat.
userTokenLabel :: String
userTokenLabel = "000de140"

-- | Clasele de activ ale profilurilor pe care le deține portofelul, din JSON-ul unui `Value` CSL.
-- |
-- | Forma așteptată e cea pe care o produce `Value.to_json`:
-- | `{"coin":"…","multiasset":{"<policy>":{"<name>":"1"}}}`. `multiasset` lipsește cu totul la un
-- | portofel care n-are decît ADA — nu e un caz de eroare, e cazul obișnuit.
-- |
-- | Rezultatul e sortat: ordinea cheilor unui obiect JSON nu e un contract, iar un ecran care își
-- | schimbă ordinea listei la fiecare citire arată rupt.
userTokenAssetClasses :: String -> String -> Array String
userTokenAssetClasses policyId valueJson =
  sort (map (\name -> policyId <> "." <> name) names)
  where
  names =
    filter (\n -> String.take (String.length userTokenLabel) n == userTokenLabel)
      (fromMaybe [] (assetNames =<< hush (jsonParser valueJson)))

  assetNames :: Json -> Maybe (Array String)
  assetNames json = do
    obj <- toObject json
    multiasset <- toObject =<< Object.lookup "multiasset" obj
    under <- toObject =<< Object.lookup policyId multiasset
    -- Cantitatea nu se citește: un token de profil e unic prin construcție, iar un portofel care
    -- l-ar avea în cantitate zero nu l-ar avea deloc în `multiasset`.
    pure (Object.keys under)
