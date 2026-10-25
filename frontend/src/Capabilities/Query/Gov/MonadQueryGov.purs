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
  , getDRepDetail
  , getGovActions
  , getGovActionDetail
  , getVotes
  , searchAll
  , getFormulas
  , getSpos
  , getCommittee
  , getWithdrawals
  , getDelegations
  , getActivity
  , getProfiles
  , getAttestations
  , getDisputes
  , getRegistrySummary
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Types
  ( DRepDetail
  , DRepExplorerPage
  , DashboardPage
  , GovActionDetail
  , GovActionPage
  , Formula
  , GovStatus
  , SearchResults
  , SpoPage
  , CommitteeState
  , WithdrawalPage
  , DelegationPage
  , ActivityPage
  , ProfilePage
  , AttestationPage
  , DisputePage
  , RegistrySummary
  , VotePage
  )
import Control.Monad.Trans.Class (lift)
import Data.Either (Either)
import Halogen (HalogenM)
import Route.GovQueries
  ( ActivityFilters
  , DRepFilters
  , DelegationFilters
  , GovActionFilters
  , RegistryFilters
  , SpoFilters
  , VoteFilters
  , WithdrawalFilters
  )

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

  -- | `GET /pages/drep/{id}` — identitate, metrici, delegatori, putere pe epoci, istoria
  -- | înregistrării și documentul de metadate, într-un apel. Sfatul de a chema patru rute separate
  -- | pentru ecranul acesta e mort: compozitul există tocmai ca să nu existe N+1.
  getDRepDetail :: String -> m (Either ApiError DRepDetail)

  -- | `GET /gov-actions` — lista. Nu există compozit de pagină pentru ea, și nu trebuie: plicul
  -- | poartă deja tot ce randează tabelul.
  getGovActions :: GovActionFilters -> m (Either ApiError GovActionPage)

  -- | `GET /pages/gov-action/{id}` — acțiunea, numărătorile pe rol, retragerile, parametrii atinși,
  -- | proponentul și documentul, într-un apel.
  getGovActionDetail :: String -> m (Either ApiError GovActionDetail)

  -- | `GET /votes` — un rând per vot, cu acțiunea și votantul denormalizate în el.
  getVotes :: VoteFilters -> m (Either ApiError VotePage)

  -- | `GET /search` — șase grupuri într-un apel. Interogarea se trimite așa cum a scris-o omul.
  searchAll :: String -> m (Either ApiError SearchResults)

  -- | `GET /metrics/formulas` — un array nud cu toate formulele publicate, SQL inclus.
  getFormulas :: m (Either ApiError (Array Formula))

  -- | `GET /spos` — operatorii cu putere de vot. Fără compozit de pagină și fără faceturi: plicul
  -- | poartă tot ce randează tabelul, iar singurele controale sunt sortarea și paginarea.
  getSpos :: SpoFilters -> m (Either ApiError SpoPage)

  -- | `GET /committee` — comitetul ÎNTREG, nu o pagină de membri: cvorumul e o proprietate a
  -- | corpului, iar trei membri nu au nevoie de paginare.
  getCommittee :: m (Either ApiError CommitteeState)

  -- | `GET /treasury-withdrawals` — fiecare retragere propusă vreodată, cu acțiunea ei. Lista e
  -- | globală, deci rîndul poartă acțiunea cu el.
  getWithdrawals :: WithdrawalFilters -> m (Either ApiError WithdrawalPage)

  -- | `GET /delegations` — cine și-a delegat puterea de vot, cui și cînd. Filtrul pe DRep e
  -- | singurul pe care un link din produs îl setează.
  getDelegations :: DelegationFilters -> m (Either ApiError DelegationPage)

  -- | `GET /activity` — fluxul, paginat pe CURSOR. Nu există un total, și nu e o scăpare: vezi
  -- | `ActivityPage`.
  getActivity :: ActivityFilters -> m (Either ApiError ActivityPage)

  -- | `GET /profiles` — registrul de profiluri. Un profil e un TOKEN: cine îl deține, îl deține.
  getProfiles :: RegistryFilters -> m (Either ApiError ProfilePage)

  -- | `GET /attestations` — cine ce a afirmat despre cine, și dacă subiectul a recunoscut.
  getAttestations :: RegistryFilters -> m (Either ApiError AttestationPage)

  -- | `GET /disputes` — contestațiile deschise împotriva atestărilor, cu depozitul pus la bătaie.
  getDisputes :: RegistryFilters -> m (Either ApiError DisputePage)

  -- | Cele trei numere ale registrului, pentru pagina de pornire. Compus din trei cereri de un
  -- | rând, nu dintr-un endpoint propriu — vezi `RegistrySummary`.
  getRegistrySummary :: m (Either ApiError RegistrySummary)

instance monadQueryGovHalogenM ::
  MonadQueryGov m =>
  MonadQueryGov (HalogenM st act slots msg m) where
  getStatus = lift getStatus
  getDashboard = lift getDashboard
  getDRepExplorer = lift <<< getDRepExplorer
  getDRepDetail = lift <<< getDRepDetail
  getGovActions = lift <<< getGovActions
  getGovActionDetail = lift <<< getGovActionDetail
  getVotes = lift <<< getVotes
  searchAll = lift <<< searchAll
  getFormulas = lift getFormulas
  getSpos = lift <<< getSpos
  getCommittee = lift getCommittee
  getWithdrawals = lift <<< getWithdrawals
  getDelegations = lift <<< getDelegations
  getActivity = lift <<< getActivity
  getProfiles = lift <<< getProfiles
  getAttestations = lift <<< getAttestations
  getDisputes = lift <<< getDisputes
  getRegistrySummary = lift getRegistrySummary
