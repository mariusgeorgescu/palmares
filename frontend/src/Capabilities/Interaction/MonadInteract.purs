-- | Cusătura de scriere: construiește, trimite, întreabă.
-- |
-- | Trei metode pentru nouă fluxuri, pentru că mecanica e una singură și diferă doar corpul.
-- | O metodă per flux ar fi fost nouă copii ale aceluiași POST.
-- |
-- | __Nu există o metodă care semnează.__ Semnătura e a wallet-ului, nu a transportului, și stă în
-- | `Capabilities.Wallet`. Un transport care ar ști să semneze ar putea fi chemat fără poarta de
-- | rețea — exact lucrul pe care poarta există să-l împiedice.
module Capabilities.Interaction.MonadInteract
  ( class MonadInteract
  , buildFlow
  , submitSigned
  , txStatus
  ) where

import Prelude

import Capabilities.Interaction.Types (FlowRequest, SubmitParams)
import Capabilities.Query.Gov.Http (ApiError)
import Control.Monad.Trans.Class (lift)
import Data.Either (Either)
import Halogen (HalogenM)

class Monad m <= MonadInteract m where
  -- | `POST /<flux>` — întoarce tranzacția NESEMNATĂ, hex-CBOR. Nimic nu s-a întâmplat pe lanț.
  buildFlow :: FlowRequest -> m (Either ApiError String)

  -- | `POST /submit-tx` — tranzacția plus martorul. ĂSTA e pasul ireversibil.
  submitSigned :: SubmitParams -> m (Either ApiError String)

  -- | `GET /tx-status/{id}` — dacă s-a confirmat. `false` înseamnă „încă nu", nu „a eșuat".
  txStatus :: String -> m (Either ApiError Boolean)

instance monadInteractHalogenM :: MonadInteract m => MonadInteract (HalogenM st act slots msg m) where
  buildFlow = lift <<< buildFlow
  submitSigned = lift <<< submitSigned
  txStatus = lift <<< txStatus
