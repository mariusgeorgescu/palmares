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
  , getDashboard
  , getDRepExplorer
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Types (DRepExplorerPage, DashboardPage, GovStatus)
import Control.Monad.Trans.Class (lift)
import Data.Either (Either)
import Halogen (HalogenM)
import Route.GovQueries (DRepFilters)

class Monad m <= MonadQueryGov m where
  -- | `GET /status` — rețeaua, epoca, lag-ul, pragurile și starea proiectorului, într-un singur
  -- | apel. Nu există un al doilea.
  getStatus :: m (Either ApiError GovStatus)

  -- | `GET /pages/dashboard` — tot ecranul de pornire într-un apel. Fără parametri: serverul are
  -- | deja valori implicite potrivite (`top_limit` 10, `closing_soon_limit` 5, `epochs` 20) și
  -- | niciun control din UI nu le schimbă. Când apare un control, parametrii intră aici.
  getDashboard :: m (Either ApiError DashboardPage)

  -- | `GET /pages/drep-explorer` — rândurile, totalul, cele trei faceturi și intervalele de putere,
  -- | într-un apel. Filtrele vin din rută, deci ecranul nu-și ține o a doua copie a lor.
  getDRepExplorer :: DRepFilters -> m (Either ApiError DRepExplorerPage)

instance monadQueryGovHalogenM ::
  MonadQueryGov m =>
  MonadQueryGov (HalogenM st act slots msg m) where
  getStatus = lift getStatus
  getDashboard = lift getDashboard
  getDRepExplorer = lift <<< getDRepExplorer
