-- | Cusătura de citire a datelor. Componentele depind de clasa asta, nu de HTTP sau de fixturi.
-- | `AppM` deleagă către `Default`, `DemoM` către `Mock`. O metodă nouă se adaugă aici și se oglindește
-- | în ambele implementări — tipul nu lasă să uiți.
-- |
-- | **O metodă per ecran, nu una per rută.** Contractul API-ului e deja în formă de pagină: fiecare
-- | ecran din `docs/usecases/api-screen-map.md` §2 se servește dintr-un singur apel, cu rândurile
-- | purtând toate câmpurile de care are nevoie tabelul. O capabilitate cu granularitate de rută ar
-- | reintroduce N+1-ul pe care backendul l-a eliminat deja.
module Capabilities.Query.Gov.MonadQueryGov
  ( class MonadQueryGov
  , getStatus
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Types (GovStatus)
import Control.Monad.Trans.Class (lift)
import Data.Either (Either)
import Halogen (HalogenM)

class Monad m <= MonadQueryGov m where
  -- | `GET /status` — rețeaua, epoca, lag-ul, pragurile și starea proiectorului, într-un singur
  -- | apel. Nu există un al doilea.
  getStatus :: m (Either ApiError GovStatus)

instance monadQueryGovHalogenM ::
  MonadQueryGov m =>
  MonadQueryGov (HalogenM st act slots msg m) where
  getStatus = lift getStatus
