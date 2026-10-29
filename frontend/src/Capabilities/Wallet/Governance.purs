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
  , impliedMagic
  , singleTestnetWallets
  ) where

import Prelude

import AppEnv (NetworkMagic(..), mainnetMagic, unNetworkMagic)
import Cardano.Wallet.Cip30 (Api, Extension, WalletName)
import Control.Monad.Trans.Class (lift)
import Data.Array (any, find)
import Data.Maybe (Maybe(..))
import Data.String (toLower)
import Halogen (HalogenM)

-- | Ce am aflat despre wallet, în cele trei forme, plus magic-ul dacă s-a putut afla.
type WalletCapabilities =
  { walletName :: WalletName
  , advertised :: Array Extension
  , negotiated :: Array Extension
  , cip95Present :: Boolean
  , cip142Present :: Boolean
  -- Magic-ul CONFIRMAT prin CIP-142, cînd extensia există și a răspuns.
  , networkMagic :: Maybe NetworkMagic
  -- `getNetworkId` din CIP-30: 0 sau 1. Nu distinge testnet-urile între ele, dar distinge un
  -- testnet de mainnet — iar asta e jumătate din ce avem nevoie pentru calea (b) de mai jos.
  , networkId :: Maybe Int
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
  -- | Wallet-ul n-a dat un API deloc: omul a refuzat prompt-ul, sau extensia a aruncat.
  --
  -- E o stare SEPARATĂ de celelalte pentru că nu spune nimic despre wallet — spune că n-am
  -- ajuns să aflăm. Un mesaj despre extensii lipsă aici ar fi o acuzație nedreaptă.
  | WalletDeclined String

derive instance Eq BlockReason

-- | `Show` e pentru mesaje de test: „expected Just NetworkUndetermined but got Just (WrongNetwork …)"
-- | spune care refuz s-a declanșat, iar `false /= true` nu spune nimic.
instance Show BlockReason where
  show = case _ of
    NetworkUndetermined -> "NetworkUndetermined"
    WrongNetwork e a -> "WrongNetwork expected=" <> show e <> " actual=" <> show a
    NoGovernanceKeys -> "NoGovernanceKeys"
    WalletDeclined e -> "WalletDeclined " <> e

data GateVerdict
  = Allowed GovWallet
  | Blocked BlockReason WalletCapabilities

-- | Cuvintele pe care le vede omul. Fiecare spune CE lipsește și CE nu va merge din cauza asta —
-- | un „wallet incompatibil" fără obiect e un mesaj pe care nimeni nu-l poate acționa.
blockMessage :: BlockReason -> String
blockMessage = case _ of
  NetworkUndetermined ->
    "This wallet cannot tell us which test network it is on. CIP-30 reports every testnet as the \
    \same number, so preprod and preview are indistinguishable unless the wallet supports the \
    \CIP-142 extension, or is one that only ever connects to preprod — Yoroi is the one we have \
    \measured. Signing here could spend your key on a chain you did not choose, so none of the \
    \nine actions will be built. A wallet on mainnet is not affected: there is only one mainnet, \
    \so nothing has to be guessed."
  WrongNetwork expected actual ->
    "This wallet is on network " <> show (unNetworkMagic actual)
      <> ", and this deployment is on "
      <> show (unNetworkMagic expected)
      <> ". Switch the wallet's network and reconnect."
  NoGovernanceKeys ->
    "This wallet does not expose governance keys (CIP-95), so it cannot prove which DRep or \
    \committee credential belongs to it. Reading the register works, but none of the nine actions \
    \will be built from here — not only the credential ones."
  WalletDeclined detail ->
    "The wallet did not connect"
      <> (if detail == "" then "" else " (" <> detail <> ")")
      <> ". If you dismissed the prompt, press connect again."

supportsCip95 :: WalletCapabilities -> Boolean
supportsCip95 c = c.cip95Present

supportsCip142 :: WalletCapabilities -> Boolean
supportsCip142 c = c.cip142Present

capabilitiesOf :: GateVerdict -> WalletCapabilities
capabilitiesOf = case _ of
  Allowed w -> w.capabilities
  Blocked _ c -> c

-- | Wallet-urile a căror IDENTITATE implică exact o rețea de test.
-- |
-- | Calea (b) din R6. Pentru un wallet din lista asta, `getNetworkId() == 0` nu mai e ambiguu:
-- | dacă wallet-ul nu POATE fi pe preview, întrebarea pe care CIP-142 o rezolvă nu există.
-- |
-- | Lista e scurtă și explicită pentru că fiecare intrare e o afirmație despre un produs din afară
-- | — exact genul de lucru care se învechește — iar un wallet necunoscut nu intră pe calea asta, ci
-- | pe refuz. Yoroi-extensie e cea măsurată în design: preprod e singurul ei testnet.
singleTestnetWallets :: Array { name :: WalletName, magic :: NetworkMagic }
singleTestnetWallets =
  [ { name: "yoroi", magic: NetworkMagic 1 }
  ]

-- | Rețeaua pe care o implică identitatea wallet-ului, dacă o implică.
-- |
-- | **Mainnet e UNUL.** `networkId == 1` nu lasă nicio ambiguitate de rezolvat, deci aici nu se
-- | ghicește nimic: `R6` interzice GHICITUL, nu deducția, iar întrebarea pe care CIP-142 o rezolvă
-- | — „care testnet?" — pur și simplu nu există pe mainnet. Fără ramura asta un deploy de mainnet
-- | ar refuza ORICE wallet, fiindcă lista de mai jos vorbește numai despre testnet-uri: toate cele
-- | nouă fluxuri de scriere ar fi moarte pentru toată lumea, iar garanția n-ar fi protejat nimic.
-- |
-- | `Nothing` pe orice altceva: un wallet necunoscut pe un testnet nu spune nimic despre CARE
-- | testnet, iar presupunerea e exact ce R6 interzice.
impliedMagic :: WalletName -> Maybe Int -> Maybe NetworkMagic
impliedMagic name = case _ of
  Just 1 -> Just mainnetMagic
  Just 0 -> map _.magic (find (\w -> w.name == toLower name) singleTestnetWallets)
  _ -> Nothing

-- | Verdictul porții.
-- |
-- | R6 se satisface pe DOUĂ căi, nu pe una — și asta nu e o slăbire. Prima versiune cerea CIP-142
-- | și numai CIP-142, iar intersecția dintre wallet-urile care implementează CIP-142 și cele care
-- | semnează pe `required_signers` e GOALĂ: revendicarea de credențială ar fi fost imposibilă prin
-- | construcție. Calea (b) păstrează garanția întreagă, pentru că un wallet care nu poate fi pe
-- | preview nu lasă loc ambiguității pe care CIP-142 o rezolvă.
verdictOf :: WalletCapabilities -> NetworkMagic -> Maybe BlockReason
verdictOf c expected = case confirmedMagic c of
  Nothing -> Just NetworkUndetermined
  Just actual
    | actual /= expected -> Just (WrongNetwork expected actual)
    | not c.cip95Present -> Just NoGovernanceKeys
    | otherwise -> Nothing

-- | Magic-ul pe care îl putem susține fără să ghicim: întîi cel confirmat prin CIP-142, apoi cel
-- | implicat de identitatea wallet-ului. În această ordine, pentru că primul e o măsurătoare și al
-- | doilea o deducție.
confirmedMagic :: WalletCapabilities -> Maybe NetworkMagic
confirmedMagic c = case c.networkMagic of
  Just m | c.cip142Present -> Just m
  _ -> impliedMagic c.walletName c.networkId

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
