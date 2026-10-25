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
