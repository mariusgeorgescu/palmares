-- | Global mutable state (halogen-store). Wallet connection and user identity
-- | live here; read-only config lives in `AppEnv`.
module Store
  ( Store
  , Username(..)
  , unUsername
  , Action(..)
  , initialStore
  , reduce
  ) where

import Prelude

import Cardano.Wallet.Cip30 (Api)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype)

newtype Username = Username String

derive instance Eq Username
derive instance Newtype Username _
derive newtype instance Show Username

unUsername :: Username -> String
unUsername (Username s) = s

-- | Global application store. Add fields as your dApp grows — e.g.
-- | active profile, pending transactions, network mismatch, refresh keys.
type Store =
  { walletApi :: Maybe Api
  , user :: Maybe Username
  }

initialStore :: Store
initialStore =
  { walletApi: Nothing
  , user: Nothing
  }

-- | Store actions. Add more cases as your dApp grows.
data Action
  = Connect Api
  | Disconnect
  | SetUser Username
  | ClearUser

-- | Pure reducer for store actions.
reduce :: Store -> Action -> Store
reduce store = case _ of
  Connect api -> store { walletApi = Just api }
  Disconnect -> store { walletApi = Nothing, user = Nothing }
  SetUser name -> store { user = Just name }
  ClearUser -> store { user = Nothing }
