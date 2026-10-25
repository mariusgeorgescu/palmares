-- | Implementarea reală a porții de wallet, peste CIP-30/95/142.
-- |
-- | Ordinea apelurilor e parte din contract, nu detaliu: se cer extensiile la `enable`, apoi se
-- | constată ce s-a obținut, apoi se citește magic-ul, și abia la urmă se dă verdictul. Un flux
-- | care ar cere magic-ul după ce a început să construiască tranzacția ar afla pe ce rețea e prea
-- | târziu ca să mai conteze.
module Capabilities.Wallet.GovernanceDefault
  ( connectGovernanceDefault
  ) where

import Prelude

import AppEnv (NetworkMagic(..))
import Capabilities.Wallet.Governance (GateVerdict(..), WalletCapabilities, verdictOf)
import Cardano.Wallet.Cip30 (WalletName, enable, getExtensions, getSupportedExtensions)
import Cardano.Wallet.Cip142 (cip142Extension, getNetworkMagic, hasCip142)
import Cardano.Wallet.Cip95 (cip95Extension, hasCip95)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff, attempt)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)

-- | Conectează un wallet pentru scris și dă verdictul.
-- |
-- | `attempt` peste fiecare citire nu e prudență generică: un wallet care anunță o extensie și
-- | aruncă la apel e cazul OBIȘNUIT în ecosistem, iar o excepție aici ar arăta ca „aplicația s-a
-- | stricat" în loc de „wallet-ul ăsta nu poate". Un eșec devine „nu avem capacitatea", care e
-- | exact ce vrem să citim mai jos.
connectGovernanceDefault
  :: forall m
   . MonadAff m
  => NetworkMagic
  -> WalletName
  -> m GateVerdict
connectGovernanceDefault expected walletName = liftAff do
  advertised <- orEmpty (liftEffect (getSupportedExtensions walletName))
  api <- enable walletName [ cip95Extension, cip142Extension ]
  negotiated <- orEmpty (getExtensions api)
  cip95 <- orFalse (liftEffect (hasCip95 api))
  cip142 <- orFalse (liftEffect (hasCip142 api))
  magic <-
    if cip142 then orNothing (NetworkMagic <$> getNetworkMagic api)
    else pure Nothing
  let
    capabilities :: WalletCapabilities
    capabilities =
      { walletName
      , advertised
      , negotiated
      , cip95Present: cip95
      , cip142Present: cip142
      , networkMagic: magic
      }
  pure case verdictOf capabilities expected of
    Just reason -> Blocked reason capabilities
    Nothing -> Allowed { api, capabilities }
  where
  orEmpty :: forall a. Aff (Array a) -> Aff (Array a)
  orEmpty act = attempt act <#> case _ of
    Right xs -> xs
    Left _ -> []

  orFalse :: Aff Boolean -> Aff Boolean
  orFalse act = attempt act <#> case _ of
    Right b -> b
    Left _ -> false

  orNothing :: forall a. Aff a -> Aff (Maybe a)
  orNothing act = attempt act <#> case _ of
    Right a -> Just a
    Left _ -> Nothing
