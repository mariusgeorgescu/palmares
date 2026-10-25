-- | Read-only application environment. Mutable state belongs in `Store`.
module AppEnv
  ( Env
  , NetworkId(..)
  , unNetworkId
  , defaultEnv
  ) where

import Prelude

-- | Cardano network identifier (e.g. 0 = Testnet/Preprod, 1 = Mainnet, 2 = Preview).
newtype NetworkId = NetworkId Int

derive instance Eq NetworkId
derive newtype instance Show NetworkId

unNetworkId :: NetworkId -> Int
unNetworkId (NetworkId n) = n

-- | Application configuration: API base URL the BFF exposes and the allowed
-- | Cardano network for connected wallets. Extend with explorer URLs, feature
-- | flags, etc. as your dApp grows. Build-time values can be wired via an
-- | `AppEnv.js` FFI module reading `import.meta.env.VITE_*`.
type Env =
  { apiBaseUrl :: String
  , allowedNetworkId :: NetworkId
  }

defaultEnv :: Env
defaultEnv =
  { apiBaseUrl: "/api/api"
  , allowedNetworkId: NetworkId 0
  }
