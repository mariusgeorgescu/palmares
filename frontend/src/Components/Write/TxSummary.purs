-- | Ce FACE tranzacția, citit din tranzacție — nu din ce a cerut utilizatorul.
-- |
-- | Regula R8 („fără blind-signing", check 14) cere un sumar DECODAT, iar designul e explicit de ce
-- | ecoul câmpurilor din formular nu ajunge: „nu dovedește ce s-a construit, doar ce s-a cerut".
-- | Serverul întoarce un singur string de CBOR hex și nimic altceva, deci singura cale către ce
-- | conține e să-l decodăm.
-- |
-- | Decodarea merge prin `cardano-serialization-lib`, care e deja în `package.json` și deja folosit
-- | pentru soldul portofelului — zero dependențe noi. Nu încalcă anti-goal-ul care interzice CSL
-- | pentru ce face deja backendul: un decode PENTRU AFIȘARE nu e oferit de nicio rută.
-- |
-- | __Modulul ăsta nu importă CSL.__ Pasul CBOR→JSON stă în `TxSummary.Decode`, singur, pentru că
-- | `Csl` trage după el un modul wasm pe care Node nu-l poate rezolva: cît timp cele două stăteau
-- | împreună, ÎNTREAGA suită de teste murea la import, din cauza unui pas de o linie pe care niciun
-- | test nu-l exersează. Partea de aici — extragerea din JSON — e codul nostru, și e testabilă.
-- |
-- | Forma JSON-ului e luată din `cardano_serialization_lib.d.ts` al versiunii pinate
-- | (`TransactionBodyJSON`, 11.5.0), nu ghicită: `fee` e string, `mint` e o listă de perechi
-- | `[policy, { assetName: quantity }]`, iar `amount.coin` e string și el. Toate sunt string-uri
-- | pentru că sunt numere de 64 de biți, iar `Int` din JavaScript n-are 64 de biți.
module Components.Write.TxSummary
  ( TxSummary
  , OutputSummary
  , MintSummary
  , summariseJson
  ) where

import Prelude

import Capabilities.Query.Gov.Types (Lovelace)
import Data.Argonaut.Core (Json, caseJsonObject, caseJsonString, toArray, toObject, toString)
import Data.Argonaut.Parser (jsonParser)
import Data.Array (concat, index, length, mapMaybe)
import Data.Either (Either(..), hush)
import Data.Foldable (sum)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Tuple (Tuple(..))
import Data.Number as Number
import Foreign.Object as Object

type OutputSummary =
  { address :: String
  , lovelace :: Lovelace
  , otherAssets :: Int
  }

type MintSummary =
  { policy :: String
  , assetName :: String
  , quantity :: String
  }

type TxSummary =
  { fee :: Lovelace
  , outputs :: Array OutputSummary
  , mints :: Array MintSummary
  , certificates :: Int
  , requiredSigners :: Int
  }

-- | Partea pură și testabilă: din JSON-ul lui CSL, sumarul.
-- |
-- | Separată de decodarea CBOR ca să poată fi testată fără wasm: forma JSON-ului e contractul
-- | bibliotecii, iar extragerea din el e codul nostru.
summariseJson :: String -> Maybe TxSummary
summariseJson raw = do
  json <- hush (jsonParser raw)
  obj <- toObject json
  fee <- lovelaceAt obj "fee"
  pure
    { fee
    , outputs: maybe [] outputsOf (Object.lookup "outputs" obj)
    , mints: maybe [] mintsOf (Object.lookup "mint" obj)
    , certificates: countOf (Object.lookup "certs" obj)
    , requiredSigners: countOf (Object.lookup "required_signers" obj)
    }

-- | Numerele de 64 de biți vin ca string, deci se citesc ca `Number`, nu ca `Int`: un depozit de
-- | 5.000.000 de lovelace încape într-un Int, dar un output de 505 bilioane nu.
lovelaceAt :: Object.Object Json -> String -> Maybe Lovelace
lovelaceAt obj key = Object.lookup key obj >>= numberOf

numberOf :: Json -> Maybe Number
numberOf j = caseJsonString Nothing Number.fromString j

countOf :: Maybe Json -> Int
countOf = maybe 0 (\j -> maybe 0 length (toArray j))

outputsOf :: Json -> Array OutputSummary
outputsOf j = maybe [] (mapMaybe outputOf) (toArray j)
  where
  outputOf o = do
    obj <- toObject o
    address <- Object.lookup "address" obj >>= toString
    amount <- Object.lookup "amount" obj >>= toObject
    lovelace <- lovelaceAt amount "coin"
    pure
      { address
      , lovelace
      -- Câte feluri de token în plus față de ada. Numărul lor contează — „mai e ceva acolo" — iar
      -- numele fiecăruia ar face sumarul mai lung decât tranzacția.
      , otherAssets: maybe 0 countAssets (Object.lookup "multiasset" amount)
      }

  countAssets ma =
    caseJsonObject 0
      (\policies -> sum (map (\p -> maybe 0 Object.size (toObject p)) (Object.values policies)))
      ma

-- | `mint` e o listă de perechi `[policy, { assetName: quantity }]`, nu un obiect — vezi
-- | `MintJSON` din typings. Un `Object.lookup` pe ea n-ar găsi nimic.
mintsOf :: Json -> Array MintSummary
mintsOf j = maybe [] (\pairs -> concat (map pairOf pairs)) (toArray j)
  where
  pairOf pair = fromMaybe [] do
    arr <- toArray pair
    policy <- index arr 0 >>= toString
    assets <- index arr 1 >>= toObject
    pure
      ( map
          (\(Tuple name qty) -> { policy, assetName: name, quantity: fromMaybe "?" (toString qty) })
          (Object.toUnfoldable assets)
      )
