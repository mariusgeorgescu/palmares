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
  , decodeFixture
  ) where

import Prelude

import Capabilities.Query.Gov.Fixtures
  ( dashboardFixture
  , drepDetailFixture
  , drepExplorerFixture
  , govActionDetailFixture
  , govActionListFixture
  , statusFixture
  , votesListFixture
  )
import Capabilities.Query.Gov.Http (ApiError(..), classifyResponse)
import Capabilities.Query.Gov.Types
  ( DRepDetail
  , DRepExplorerPage
  , DashboardPage
  , GovActionDetail
  , GovActionPage
  , GovStatus
  , VotePage
  )
import Data.Argonaut.Decode (class DecodeJson, decodeJson, printJsonDecodeError)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Route.GovQueries (DRepFilters, GovActionFilters, VoteFilters)

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
