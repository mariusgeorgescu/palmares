-- | Configurația read-only. Starea mutabilă stă în `Store`.
-- |
-- | Valorile vin din `import.meta.env.VITE_*` prin `AppEnv.js`, înlocuite de Vite la build. Nimic
-- | de aici nu e secret, prin construcție: orice `VITE_*` ajunge în JavaScript-ul livrat
-- | browserului. Credențialele de scriere stau în BFF, server-side.
module AppEnv
  ( NetworkMagic(..)
  , unNetworkMagic
  , preprodMagic
  , previewMagic
  , mainnetMagic
  , Env
  , defaultEnv
  , explorerBaseFor
  , explorerBase
  ) where

import Prelude

import Data.Int as Int
import Data.Maybe (fromMaybe)

-- | Magic-ul de rețea din CIP-142, nu `networkId` din CIP-30.
-- |
-- | `getNetworkId()` întoarce **0 pentru toate testnet-urile**, deci nu poate distinge preprod de
-- | preview — govtool#4038 s-a închis ca „design flaw in CIP30". Un produs care trăiește pe preprod
-- | și semnează pe preview ar construi tranzacții valide pe rețeaua greșită. Magic-ul distinge.
newtype NetworkMagic = NetworkMagic Int

derive instance Eq NetworkMagic
derive newtype instance Show NetworkMagic

unNetworkMagic :: NetworkMagic -> Int
unNetworkMagic (NetworkMagic n) = n

preprodMagic :: NetworkMagic
preprodMagic = NetworkMagic 1

previewMagic :: NetworkMagic
previewMagic = NetworkMagic 2

mainnetMagic :: NetworkMagic
mainnetMagic = NetworkMagic 764824073

-- | Cele două prefixe sunt separate pentru că serviciile din spate sunt separate și au contracte de
-- | auth diferite: query-api e public prin contract de boot, interaction-api e sub BasicAuth. BFF-ul
-- | le expune la `/api/query` și `/api/interaction`.
type Env =
  { queryBaseUrl :: String
  , interactionBaseUrl :: String
  , allowedNetworkMagic :: NetworkMagic
  }

-- | Baza explorerului pentru rețeaua pe care rulăm, derivată din magic-ul pe care `Env` îl are deja.
-- |
-- | O funcție pură, nu o variabilă `VITE_*`: adresa unui explorer public e o constantă per rețea, iar
-- | o variabilă de mediu pentru o constantă e un loc în plus unde deployul poate să mintă.
-- |
-- | `cexplorer`, nu `cardanoscan`, și e o alegere măsurată: cardanoscan întoarce 403 chiar și la un
-- | Chromium headless, deci nicio cale a lui nu se poate verifica automat. Pe cexplorer fiecare cale
-- | folosită a fost deschisă într-un browser — vezi `Components.Shared.OnchainId.explorerUrl`.
explorerBaseFor :: NetworkMagic -> String
explorerBaseFor magic
  | magic == mainnetMagic = "https://cexplorer.io"
  | magic == previewMagic = "https://preview.cexplorer.io"
  | otherwise = "https://preprod.cexplorer.io"

foreign import queryBaseUrlImpl :: String
foreign import interactionBaseUrlImpl :: String
foreign import networkMagicImpl :: String

-- | Magic-ul se importă ca `String` și se parsează aici, nu se coerce în FFI: `Number("abc")` dă
-- | `NaN`, care ar trece drept `Int` la runtime și ar strica orice comparație fără să arunce.
defaultEnv :: Env
defaultEnv =
  { queryBaseUrl: queryBaseUrlImpl
  , interactionBaseUrl: interactionBaseUrlImpl
  , allowedNetworkMagic: NetworkMagic (fromMaybe (unNetworkMagic preprodMagic) (Int.fromString networkMagicImpl))
  }

-- | Baza explorerului pentru ACEST build, ca valoare pură.
-- |
-- | `defaultEnv` e construit din constante înlocuite de Vite la build, deci nu e un efect — iar asta
-- | înseamnă că un chip de identificator nu trebuie să primească mediul prin parametru sau prin
-- | `MonadAsk`. Fără ea, fiecare loc care arată un id ar fi trebuit să devină componentă sau să
-- | capete un argument în plus, în vreo zece fișiere.
explorerBase :: String
explorerBase = explorerBaseFor defaultEnv.allowedNetworkMagic
