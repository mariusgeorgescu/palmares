-- | Poarta de wallet: ce poate face wallet-ul conectat, și ce REFUZĂM să începem cu el.
-- |
-- | Produsul ăsta scrie pe lanț în numele cuiva. Două lucruri trebuie decise __înainte__ de prima
-- | semnătură, nu după:
-- |
-- |   * __pe ce rețea suntem.__ `getNetworkId` din CIP-30 întoarce 0 pentru preprod, pentru
-- |     preview ȘI pentru un devnet local — sunt toate „testnet". O tranzacție construită pentru
-- |     preprod și semnată pe preview e cheia cuiva cheltuită pe un lanț pe care nu l-a ales. De
-- |     aceea magic-ul (CIP-142) nu e un lux: fără el, fluxul nu pornește;
-- |   * __dacă wallet-ul poate identifica o credențială de guvernanță__ (CIP-95). Fără asta,
-- |     „revendică credențiala" n-are ce să dovedească.
-- |
-- | Detecția se face în TREI forme, și toate trei se păstrează, pentru că în practică se contrazic:
-- |
-- |   1. `supportedExtensions` de pe obiectul wallet-ului — ce SUSȚINE că poate, înainte de enable;
-- |   2. `getExtensions()` de pe API — ce s-a NEGOCIAT la enable;
-- |   3. existența obiectului `api.cip95` / `api.cip142` — ce EXISTĂ chiar pe conexiunea asta.
-- |
-- | Verdictul se ia pe (3), fiindcă e singurul fapt despre conexiune; (1) și (2) se arată omului,
-- | ca să vadă DE CE a fost refuzat un wallet care „scrie pe cutie" că suportă extensia.
module Capabilities.Wallet.Governance
  ( WalletCapabilities
  , GateVerdict(..)
  , BlockReason(..)
  , GovWallet
  , class MonadGovWallet
  , connectGovernance
  , capabilitiesOf
  , verdictOf
  , blockMessage
  , supportsCip95
  , supportsCip142
  , hasExtension
  ) where

import Prelude

import AppEnv (NetworkMagic(..), unNetworkMagic)
import Cardano.Wallet.Cip30 (Api, Extension, WalletName)
import Control.Monad.Trans.Class (lift)
import Data.Array (any)
import Data.Maybe (Maybe(..))
import Halogen (HalogenM)

-- | Ce am aflat despre wallet, în cele trei forme, plus magic-ul dacă s-a putut afla.
type WalletCapabilities =
  { walletName :: WalletName
  , advertised :: Array Extension
  , negotiated :: Array Extension
  , cip95Present :: Boolean
  , cip142Present :: Boolean
  , networkMagic :: Maybe NetworkMagic
  }

-- | Wallet-ul gata de scris: API-ul plus ce s-a constatat despre el.
type GovWallet =
  { api :: Api
  , capabilities :: WalletCapabilities
  }

data BlockReason
  -- | Nu se poate afla pe ce rețea suntem. NU presupunem preprod.
  = NetworkUndetermined
  -- | Se știe rețeaua, și nu e a noastră.
  | WrongNetwork NetworkMagic NetworkMagic
  -- | Wallet-ul nu poate identifica o credențială de guvernanță.
  | NoGovernanceKeys

derive instance Eq BlockReason

-- | `Show` e pentru mesaje de test: „expected Just NetworkUndetermined but got Just (WrongNetwork …)"
-- | spune care refuz s-a declanșat, iar `false /= true` nu spune nimic.
instance Show BlockReason where
  show = case _ of
    NetworkUndetermined -> "NetworkUndetermined"
    WrongNetwork e a -> "WrongNetwork expected=" <> show e <> " actual=" <> show a
    NoGovernanceKeys -> "NoGovernanceKeys"

data GateVerdict
  = Allowed GovWallet
  | Blocked BlockReason WalletCapabilities

-- | Cuvintele pe care le vede omul. Fiecare spune CE lipsește și CE nu va merge din cauza asta —
-- | un „wallet incompatibil" fără obiect e un mesaj pe care nimeni nu-l poate acționa.
blockMessage :: BlockReason -> String
blockMessage = case _ of
  NetworkUndetermined ->
    "This wallet cannot tell us which network it is on. CIP-30 reports every testnet as the same \
    \number, so preprod and preview are indistinguishable without the CIP-142 extension. Signing \
    \here could spend your key on a chain you did not choose, so nothing will be built."
  WrongNetwork expected actual ->
    "This wallet is on network " <> show (unNetworkMagic actual)
      <> ", and this deployment is on "
      <> show (unNetworkMagic expected)
      <> ". Switch the wallet's network and reconnect."
  NoGovernanceKeys ->
    "This wallet does not expose governance keys (CIP-95), so it cannot prove which DRep or \
    \committee credential belongs to it. Reading works; claiming a credential does not."

supportsCip95 :: WalletCapabilities -> Boolean
supportsCip95 c = c.cip95Present

supportsCip142 :: WalletCapabilities -> Boolean
supportsCip142 c = c.cip142Present

capabilitiesOf :: GateVerdict -> WalletCapabilities
capabilitiesOf = case _ of
  Allowed w -> w.capabilities
  Blocked _ c -> c

verdictOf :: WalletCapabilities -> NetworkMagic -> Maybe BlockReason
verdictOf c expected
  | not c.cip142Present = Just NetworkUndetermined
  | otherwise = case c.networkMagic of
      Nothing -> Just NetworkUndetermined
      Just actual
        | actual /= expected -> Just (WrongNetwork expected actual)
        | not c.cip95Present -> Just NoGovernanceKeys
        | otherwise -> Nothing

-- | Cusătura. Componentele cer poarta, nu wallet-ul.
class Monad m <= MonadGovWallet m where
  -- | Conectează, constată, și decide. Nu aruncă: un wallet refuzat e un rezultat, nu o eroare.
  connectGovernance :: WalletName -> m GateVerdict

instance monadGovWalletHalogenM :: MonadGovWallet m => MonadGovWallet (HalogenM st act slots msg m) where
  connectGovernance = lift <<< connectGovernance

-- | Dacă lista de extensii conține un `cip` anume. Folosit doar pentru formele (1) și (2), cele
-- | care se ARATĂ omului; verdictul nu se ia pe ele.
hasExtension :: Int -> Array Extension -> Boolean
hasExtension n = any (\e -> e.cip == n)
