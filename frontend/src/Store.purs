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

import Capabilities.Query.Gov.Types (ProfileRow)
import Capabilities.Wallet.Governance (GateVerdict)
import Data.Array (head)
import Data.Maybe (Maybe(..))
import Network.RemoteData (RemoteData(..))
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
  -- Profilurile pe care le deține portofelul conectat, și cel cu care lucrezi ACUM.
  --
  -- Stau aici, nu în ecranul de scriere, fiindcă „cu ce identitate lucrez" nu e o întrebare a unui
  -- formular: pagina unui profil trebuie să știe că e a ta, iar butonul care te-ar trimite să te
  -- girezi pe tine însuți trebuie să dispară — regula `Mr` refuză auto-girarea, deci un buton care
  -- o oferă duce la un refuz garantat, după semnătură.
  --
  -- `RemoteData` și nu o listă: „încă se citește", „n-am putut citi" și „nu deține niciunul" sînt
  -- trei lucruri diferite, iar al treilea e o informație utilă — înseamnă „revendică unul întîi".
  , owned :: RemoteData String (Array ProfileRow)
  , active :: Maybe ProfileRow
  }

initialStore :: Store
initialStore =
  { wallet: Nothing
  , user: Nothing
  , refreshKey: 0
  , owned: NotAsked
  , active: Nothing
  }

-- | Store actions. Add more cases as your dApp grows.
data Action
  = Connect GateVerdict
  | Disconnect
  | SetUser Username
  | ClearUser
  -- | O scriere s-a confirmat pe lanț. Ridicat de înveliș, citit de ecrane.
  | Refresh
  -- | Ce profiluri deține portofelul. Învelișul le citește o dată, la conectare.
  | SetOwned (RemoteData String (Array ProfileRow))
  -- | Cu ce profil lucrezi. Ales din bara de sus, sau implicit primul deținut.
  | SetActive ProfileRow

-- | Pure reducer for store actions.
reduce :: Store -> Action -> Store
reduce store = case _ of
  Connect verdict -> store { wallet = Just verdict }
  Refresh -> store { refreshKey = store.refreshKey + 1 }
  -- Primul deținut devine activ, ca la `bjj-belts`: cu un singur profil — cazul obișnuit — nu există
  -- nicio alegere de făcut, iar a cere una ar fi un clic cerut degeaba. Alegerea existentă NU se
  -- suprascrie: lista se recitește și după o scriere confirmată.
  SetOwned owned -> store
    { owned = owned
    , active = case store.active, owned of
        Just a, _ -> Just a
        Nothing, Success rows -> head rows
        Nothing, _ -> Nothing
    }
  SetActive row -> store { active = Just row }
  -- La deconectare se uită TOT ce era legat de portofel. Un profil activ rămas în urmă ar
  -- precompleta un formular cu o identitate pe care nimeni nu mai poate semna.
  Disconnect -> store { wallet = Nothing, user = Nothing, owned = NotAsked, active = Nothing }
  SetUser name -> store { user = Just name }
  ClearUser -> store { user = Nothing }
