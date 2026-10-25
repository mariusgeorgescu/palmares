-- | DTO-urile suprafeței de citire.
-- |
-- | __Decodoarele sunt scrise de mână, cu cheile snake_case literale.__ Nu generate din swagger și
-- | nu derivate generic dintr-un modificator de nume de câmp, pentru trei motive măsurate:
-- | swagger-ul declară pentru `limit`/`offset` intervalul Int64 și descrie `GYAddress` ca bech32
-- | când e hex; corpurile de scriere au camelCase în interiorul unor corpuri snake_case, deci un
-- | singur modificator global ar rupe exact jumătate; și o cheie scrisă literal aici e vizibilă la
-- | citire, deci o nepotrivire se vede în diff.
module Capabilities.Query.Gov.Types
  ( GovSync(..)
  , AttestSync(..)
  , GovStatus(..)
  , ChipState(..)
  , chipState
  , chipStateFor
  ) where

import Prelude

import Data.Argonaut.Decode (class DecodeJson, decodeJson, (.:), (.:?))
import Data.Maybe (Maybe(..))

-- | Blocul de sincronizare al db-sync-ului. Prezent mereu.
newtype GovSync = GovSync
  { epoch :: Int
  , slot :: Int
  , blockTime :: String
  , lagSeconds :: Int
  , isReady :: Boolean
  , source :: String
  }

derive instance Eq GovSync

instance DecodeJson GovSync where
  decodeJson json = do
    o <- decodeJson json
    epoch <- o .: "epoch"
    slot <- o .: "slot"
    blockTime <- o .: "block_time"
    lagSeconds <- o .: "lag_seconds"
    isReady <- o .: "is_ready"
    source <- o .: "source"
    pure (GovSync { epoch, slot, blockTime, lagSeconds, isReady, source })

-- | Blocul proiectorului de atestări. `last_error` e `null` când nu e nicio eroare, iar întregul
-- | obiect lipsește pe un deploy doar-guvernanță — de aceea `GovStatus.attestation` e `Maybe`.
newtype AttestSync = AttestSync
  { slot :: Int
  , kupoTipSlot :: Int
  , lagSeconds :: Int
  , state :: String
  , lastSyncAt :: Maybe String
  , isReady :: Boolean
  , policyId :: String
  , lastError :: Maybe String
  , source :: String
  }

derive instance Eq AttestSync

instance DecodeJson AttestSync where
  decodeJson json = do
    o <- decodeJson json
    slot <- o .: "slot"
    kupoTipSlot <- o .: "kupo_tip_slot"
    lagSeconds <- o .: "lag_seconds"
    state <- o .: "state"
    lastSyncAt <- o .:? "last_sync_at"
    isReady <- o .: "is_ready"
    policyId <- o .: "policy_id"
    lastError <- o .:? "last_error"
    source <- o .: "source"
    pure (AttestSync { slot, kupoTipSlot, lagSeconds, state, lastSyncAt, isReady, policyId, lastError, source })

-- | `GET /status`, un singur apel, din care se randează tot chip-ul global.
-- |
-- | `drepDistrEpoch` e câmp separat de `governance.epoch` pentru că ledgerul scrie distribuția de
-- | stake a DRep-ilor cu o epocă în urmă față de tip. Orice cifră de putere se etichetează cu
-- | __el__, nu cu epoca curentă. La fel, `metricsAsOfEpoch` e epoca din care vin metricile.
-- |
-- | `epoch_params` din răspuns nu e modelat aici: singurul ecran care-l cere e Metodologia, și îl va
-- | lua prin propriul DTO când ajungem la el. Un câmp nemodelat nu deranjează: decodorul citește
-- | cheile pe care le numește și ignoră restul.
newtype GovStatus = GovStatus
  { network :: String
  , governance :: GovSync
  , attestation :: Maybe AttestSync
  , attestLagSeconds :: Maybe Int
  , drepDistrEpoch :: Int
  , amberLagSeconds :: Int
  , readyMaxLagSeconds :: Int
  , metricsAsOfEpoch :: Int
  }

derive instance Eq GovStatus

instance DecodeJson GovStatus where
  decodeJson json = do
    o <- decodeJson json
    network <- o .: "network"
    governance <- o .: "governance"
    attestation <- o .:? "attestation"
    attestLagSeconds <- o .:? "attest_lag_seconds"
    drepDistrEpoch <- o .: "drep_distr_epoch"
    amberLagSeconds <- o .: "amber_lag_seconds"
    readyMaxLagSeconds <- o .: "ready_max_lag_seconds"
    metricsAsOfEpoch <- o .: "metrics_as_of_epoch"
    pure
      ( GovStatus
          { network
          , governance
          , attestation
          , attestLagSeconds
          , drepDistrEpoch
          , amberLagSeconds
          , readyMaxLagSeconds
          , metricsAsOfEpoch
          }
      )

-- | Culoarea chip-ului de prospețime. `Unknown` nu e decor: înseamnă „n-am putut citi starea", care
-- | e un fapt diferit de „datele sunt proaspete" și de „datele sunt vechi". Un chip care arată verde
-- | când nu știe e singurul mod în care acest produs poate minți fără să greșească un calcul.
data ChipState = Green | Amber | Red | Unknown

derive instance Eq ChipState

instance Show ChipState where
  show = case _ of
    Green -> "green"
    Amber -> "amber"
    Red -> "red"
    Unknown -> "unknown"

-- | Pragurile vin din răspuns, nu din cod: serverul publică `amber_lag_seconds` și
-- | `ready_max_lag_seconds` tocmai ca UI-ul să nu-și aleagă singur limitele și să se dezacordeze de
-- | la probe-ul care decide dacă `/ready` e verde.
chipState :: Int -> Int -> Int -> ChipState
chipState lag amber red
  | lag >= red = Red
  | lag >= amber = Amber
  | otherwise = Green

-- | Chip-ul pentru un status întreg: lag-ul cel mai rău dintre guvernanță și atestări, pentru că un
-- | ecran e la fel de proaspăt ca cea mai veche dintre sursele lui.
chipStateFor :: GovStatus -> ChipState
chipStateFor (GovStatus s) =
  chipState worstLag s.amberLagSeconds s.readyMaxLagSeconds
  where
  govLag = case s.governance of GovSync g -> g.lagSeconds
  attestLag = case s.attestation of
    Nothing -> 0
    Just (AttestSync a) -> a.lagSeconds
  worstLag = max govLag attestLag
