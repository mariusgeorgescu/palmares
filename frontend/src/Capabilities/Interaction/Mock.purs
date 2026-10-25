-- | Transportul de scriere pentru bundle-ul demo: nimic nu părăsește browserul.
-- |
-- | Fluxurile de scriere NU se pot simula onest până la capăt — semnătura e a unui wallet care nu
-- | există aici — deci mock-ul merge exact până unde merge și realitatea fără wallet: construiește
-- | o tranzacție și se oprește. Ce se testează pe el sunt FORMULARELE și REFUZURILE, nu semnarea.
module Capabilities.Interaction.Mock
  ( buildFlowMock
  , submitSignedMock
  , txStatusMock
  ) where

import Prelude

import Capabilities.Interaction.Types (FlowRequest, SubmitParams)
import Capabilities.Query.Gov.Http (ApiError(..))
import Data.Either (Either(..))

-- | O tranzacție nesemnată de formă plauzibilă. Nu e validă pe niciun lanț, și nici nu trebuie:
-- | singurul lucru care o atinge în demo e ecranul care o arată.
buildFlowMock :: forall m. Applicative m => FlowRequest -> m (Either ApiError String)
buildFlowMock _ = pure (Right "84a300d9010281825820")

-- | Trimiterea e refuzată explicit în demo, și cu motiv scris: un mock care ar răspunde „am
-- | trimis" ar învăța ecranul să arate un succes care nu s-a întâmplat.
submitSignedMock :: forall m. Applicative m => SubmitParams -> m (Either ApiError String)
submitSignedMock _ =
  pure (Left (Api { code: "demo_no_submit", message: "The demo build never submits a transaction." }))

txStatusMock :: forall m. Applicative m => String -> m (Either ApiError Boolean)
txStatusMock _ = pure (Right false)
