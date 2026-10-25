-- | Implementarea cu fixturi a lui `MonadQueryGov`. `DemoM` deleagă aici, iar `MainDemo` — bundle-ul
-- | implicit — o folosește, deci `npm run dev` și e2e-ul merg fără backend, fără wallet și fără lanț.
-- |
-- | **Fixturile sunt payload-uri măsurate, nu inventate.** Fiecare e copiat din
-- | `docs/usecases/api-screen-map.md`, care a fost scris interogând serviciul care rulează. Și
-- | fiecare trece prin **același** drum de decodare ca răspunsul real: dacă decodorul și forma reală
-- | se despart, bundle-ul demo arată eroarea de decodare pe ecran în loc să ascundă divergența în
-- | spatele unui record construit de mână.
module Capabilities.Query.Gov.Mock
  ( getStatusMock
  , decodeFixture
  , statusFixture
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError(..), classifyResponse)
import Capabilities.Query.Gov.Types (GovStatus)
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

-- | `GET /status` pe preprod, 2026-10-24. `epoch_params` e omis: niciun decodor nu-l citește încă,
-- | iar ecranul de Metodologie își va aduce propriul DTO.
statusFixture :: String
statusFixture =
  """
  { "network": "preprod"
  , "governance":
      { "epoch": 321
      , "slot": 137140009
      , "block_time": "2026-10-24T06:26:49Z"
      , "lag_seconds": 43
      , "is_ready": true
      , "source": "cardano-db-sync"
      }
  , "attest_lag_seconds": 0
  , "attestation":
      { "slot": 137140009
      , "kupo_tip_slot": 137140009
      , "lag_seconds": 0
      , "state": "following"
      , "last_sync_at": "2026-10-24T06:27:22.960784Z"
      , "is_ready": true
      , "policy_id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3"
      , "last_error": null
      , "source": "attest-sync/kupo"
      }
  , "drep_distr_epoch": 321
  , "amber_lag_seconds": 120
  , "ready_max_lag_seconds": 300
  , "metrics_as_of_epoch": 321
  }
  """
