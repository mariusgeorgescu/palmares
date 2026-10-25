-- | Poarta de wallet în bundle-ul demo: nu există wallet, deci nu există poartă deschisă.
-- |
-- | Verdictul e `Blocked`, dar capacitățile raportate sunt ALESE ca să arate exact dezacordul
-- | pentru care există matricea: un wallet care ANUNȚĂ CIP-95 în `supportedExtensions` și nu-l are
-- | pe conexiune. Asta se întâmplă în realitate, iar ecranul trebuie să poată explica de ce a fost
-- | refuzat un wallet care „scrie pe cutie" că suportă extensia.
module Capabilities.Wallet.GovernanceMock
  ( connectGovernanceMock
  ) where

import Prelude

import Capabilities.Wallet.Governance (BlockReason(..), GateVerdict(..))
import Cardano.Wallet.Cip30 (WalletName)
import Data.Maybe (Maybe(..))

connectGovernanceMock :: forall m. Applicative m => WalletName -> m GateVerdict
connectGovernanceMock walletName =
  pure
    ( Blocked NetworkUndetermined
        { walletName
        , advertised: [ { cip: 30 }, { cip: 95 } ]
        , negotiated: [ { cip: 95 } ]
        , cip95Present: true
        , cip142Present: false
        , networkMagic: Nothing
        -- Un wallet pe testnet, dar nu unul al cărui nume implică UN testnet anume: exact cazul
        -- în care niciuna din cele două căi din R6 nu se închide.
        , networkId: Just 0
        }
    )
