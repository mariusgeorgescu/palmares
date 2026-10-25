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
  , decodeFixture
  ) where

import Prelude

import Capabilities.Query.Gov.Fixtures (dashboardFixture, statusFixture)
import Capabilities.Query.Gov.Http (ApiError(..), classifyResponse)
import Capabilities.Query.Gov.Types (DashboardPage, GovStatus)
import Data.Argonaut.Decode (class DecodeJson, decodeJson, printJsonDecodeError)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))

-- | Decodează o fixtură exact cum s-ar decoda un 200 real.
decodeFixture :: forall a. DecodeJson a => String -> Either ApiError a
decodeFixture s = case classifyResponse 200 s of
  Left e -> Left e
  Right json -> lmap (Decode <<< printJsonDecodeError) (decodeJson json)

getStatusMock :: forall m. Applicative m => m (Either ApiError GovStatus)
getStatusMock = pure (decodeFixture statusFixture)

getDashboardMock :: forall m. Applicative m => m (Either ApiError DashboardPage)
getDashboardMock = pure (decodeFixture dashboardFixture)
