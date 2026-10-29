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

import Capabilities.Wallet.Governance (GateVerdict)
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
-- |
-- | __Wallet-ul stă AICI, și e singura stare de wallet din aplicație.__ Înainte erau două: bara de
-- | sus ținea conexiunea în componenta de wallet, iar ecranul de scriere își conecta una a lui,
-- | cu `getAvailableWallets` direct. Cele două nu se vedeau între ele, deci un om care conecta în
-- | bară găsea „Connect a wallet" pe „Actions", iar unul care conecta pe „Actions" vedea bara
-- | neconectată. Nu era o scăpare de sincronizare, erau două surse de adevăr.
-- |
-- | Ce se ține e VERDICTUL, nu doar API-ul: poarta de guvernanță cere extensiile la `enable`
-- | (CIP-95/142), deci se poate constata o singură dată, la conectare, și nu la fiecare intrare pe
-- | ecranul de scriere. Un `Api` fără extensii nu e bun de scris, iar unul cu ele nu trebuie
-- | re-negociat.
type Store =
  { wallet :: Maybe GateVerdict
  , user :: Maybe Username
  -- Crește o dată per scriere CONFIRMATĂ pe lanț. Ecranele care arată ce schimbă o scriere se
  -- abonează la ea și reinterogează.
  --
  -- De ce un contor și nu un eveniment per tip de obiect: o tranzacție poate atinge un profil, o
  -- atestare ȘI o dispută (acceptarea unei atestări contestate), iar proiecțiile din spate se
  -- actualizează împreună, cu ~45s de întârziere măsurată. Un ecran care ar reinteroga doar la
  -- „s-a schimbat un profil" ar rata exact cazurile compuse, iar unul care ar reinteroga la fiecare
  -- schimbare de `Store` ar bate la ușă și la conectarea wallet-ului.
  , refreshKey :: Int
  }

initialStore :: Store
initialStore =
  { wallet: Nothing
  , user: Nothing
  , refreshKey: 0
  }

-- | Store actions. Add more cases as your dApp grows.
data Action
  = Connect GateVerdict
  | Disconnect
  | SetUser Username
  | ClearUser
  -- | O scriere s-a confirmat pe lanț. Ridicat de înveliș, citit de ecrane.
  | Refresh

-- | Pure reducer for store actions.
reduce :: Store -> Action -> Store
reduce store = case _ of
  Connect verdict -> store { wallet = Just verdict }
  Refresh -> store { refreshKey = store.refreshKey + 1 }
  Disconnect -> store { wallet = Nothing, user = Nothing }
  SetUser name -> store { user = Just name }
  ClearUser -> store { user = Nothing }
