-- | Implementarea cu fixturi a lui `MonadQueryGov`. `DemoM` deleagă aici, iar `MainDemo` — bundle-ul
-- | implicit — o folosește, deci `npm run dev` și e2e-ul merg fără backend, fără wallet și fără lanț.
-- |
-- | Modulul e doar cablaj: payload-urile stau în `Fixtures`. Fiecare trece prin **același** drum de
-- | decodare ca răspunsul real — dacă decodorul și forma reală se despart, bundle-ul demo arată
-- | eroarea de decodare pe ecran în loc să ascundă divergența în spatele unui record construit de
-- | mână.
module Capabilities.Query.Gov.Mock
  ( getStatusMock
  , getDashboardMock
  , getDRepExplorerMock
  , getDRepDetailMock
  , getGovActionsMock
  , getGovActionDetailMock
  , getVotesMock
  , searchAllMock
  , getFormulasMock
  , getSposMock
  , getCommitteeMock
  , getWithdrawalsMock
  , getDelegationsMock
  , getActivityMock
  , getProfileMock
  , getProfilesMock
  , getAttestationMock
  , getAttestationsMock
  , getDisputeMock
  , getDisputesMock
  , getRegistrySummaryMock
  , decodeFixture
  ) where

import Prelude

import Capabilities.Query.Gov.Fixtures
  ( dashboardFixture
  , drepDetailFixture
  , drepExplorerFixture
  , govActionDetailFixture
  , govActionListFixture
  , formulasFixture
  , searchFixture
  , statusFixture
  , votesListFixture
  , spoListFixture
  , committeeFixture
  , withdrawalListFixture
  , delegationListFixture
  , activityFixture
  , disputeDetailFixture
  , attestationDetailFixture
  , profileDetailFixture
  , profileListFixture
  , attestationListFixture
  , disputeListFixture
  )
import Capabilities.Query.Gov.Http (ApiError(..), classifyResponse)
import Capabilities.Query.Gov.Types
  ( DRepDetail
  , DRepExplorerPage
  , DashboardPage
  , GovActionDetail
  , GovActionPage
  , Formula
  , GovStatus
  , SearchResults
  , VotePage
  , SpoPage
  , CommitteeState
  , WithdrawalPage
  , DelegationPage
  , ActivityPage
  , ProfilePage
  , ProfileRow
  , AttestationDetail
  , AttestationPage
  , DisputePage
  , DisputeRow
  , RegistrySummary
  )
import Data.Argonaut.Decode (class DecodeJson, decodeJson, printJsonDecodeError)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
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

-- | Decodează o fixtură exact cum s-ar decoda un 200 real.
decodeFixture :: forall a. DecodeJson a => String -> Either ApiError a
decodeFixture s = case classifyResponse 200 s of
  Left e -> Left e
  Right json -> lmap (Decode <<< printJsonDecodeError) (decodeJson json)

getStatusMock :: forall m. Applicative m => m (Either ApiError GovStatus)
getStatusMock = pure (decodeFixture statusFixture)

getDashboardMock :: forall m. Applicative m => m (Either ApiError DashboardPage)
getDashboardMock = pure (decodeFixture dashboardFixture)

-- | Fixtura ignoră filtrele: e un răspuns înregistrat, nu o bază de date. Bundle-ul demo arată
-- | deci mereu aceleași patru rânduri, oricare facet s-ar apăsa — ceea ce e tot ce trebuie ca să
-- | verifici randarea, și e exact ce nu trebuie ca să verifici filtrarea. Filtrarea se verifică pe
-- | serverul adevărat.
getDRepExplorerMock :: forall m. Applicative m => DRepFilters -> m (Either ApiError DRepExplorerPage)
getDRepExplorerMock _ = pure (decodeFixture drepExplorerFixture)

-- | Aceeași fixtură pentru orice ID: bundle-ul demo arată mereu DRep-ul-cazul-greu.
getDRepDetailMock :: forall m. Applicative m => String -> m (Either ApiError DRepDetail)
getDRepDetailMock _ = pure (decodeFixture drepDetailFixture)

getGovActionsMock :: forall m. Applicative m => GovActionFilters -> m (Either ApiError GovActionPage)
getGovActionsMock _ = pure (decodeFixture govActionListFixture)

getGovActionDetailMock :: forall m. Applicative m => String -> m (Either ApiError GovActionDetail)
getGovActionDetailMock _ = pure (decodeFixture govActionDetailFixture)

getVotesMock :: forall m. Applicative m => VoteFilters -> m (Either ApiError VotePage)
getVotesMock _ = pure (decodeFixture votesListFixture)

searchAllMock :: forall m. Applicative m => String -> m (Either ApiError SearchResults)
searchAllMock _ = pure (decodeFixture searchFixture)

getFormulasMock :: forall m. Applicative m => m (Either ApiError (Array Formula))
getFormulasMock = pure (decodeFixture formulasFixture)

getSposMock :: forall m. Applicative m => SpoFilters -> m (Either ApiError SpoPage)
getSposMock _ = pure (decodeFixture spoListFixture)

getCommitteeMock :: forall m. Applicative m => m (Either ApiError CommitteeState)
getCommitteeMock = pure (decodeFixture committeeFixture)

getWithdrawalsMock :: forall m. Applicative m => WithdrawalFilters -> m (Either ApiError WithdrawalPage)
getWithdrawalsMock _ = pure (decodeFixture withdrawalListFixture)

getDelegationsMock :: forall m. Applicative m => DelegationFilters -> m (Either ApiError DelegationPage)
getDelegationsMock _ = pure (decodeFixture delegationListFixture)

getActivityMock :: forall m. Applicative m => ActivityFilters -> m (Either ApiError ActivityPage)
getActivityMock _ = pure (decodeFixture activityFixture)

getProfileMock :: forall m. Applicative m => String -> m (Either ApiError ProfileRow)
getProfileMock _ = pure (decodeFixture profileDetailFixture)

getProfilesMock :: forall m. Applicative m => RegistryFilters -> m (Either ApiError ProfilePage)
getProfilesMock _ = pure (decodeFixture profileListFixture)

getAttestationMock :: forall m. Applicative m => String -> m (Either ApiError AttestationDetail)
getAttestationMock _ = pure (decodeFixture attestationDetailFixture)

getAttestationsMock :: forall m. Applicative m => RegistryFilters -> m (Either ApiError AttestationPage)
getAttestationsMock _ = pure (decodeFixture attestationListFixture)

getDisputeMock :: forall m. Applicative m => String -> m (Either ApiError DisputeRow)
getDisputeMock _ = pure (decodeFixture disputeDetailFixture)

getDisputesMock :: forall m. Applicative m => RegistryFilters -> m (Either ApiError DisputePage)
getDisputesMock _ = pure (decodeFixture disputeListFixture)

-- | Numerele măsurate pe preprod, ca și fixturile din care ar fi putut fi citite.
getRegistrySummaryMock :: forall m. Applicative m => m (Either ApiError RegistrySummary)
getRegistrySummaryMock = pure (Right { profiles: 12, attestations: 19, disputes: 5 })
