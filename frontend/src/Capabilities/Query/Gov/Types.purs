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
  , Lovelace
  , EpochPoint(..)
  , DRepSummary(..)
  , GovActionSummary(..)
  , DashboardPage(..)
  , PowerBucket(..)
  , DRepExplorerPage(..)
  ) where

import Prelude

import Data.Argonaut.Decode (class DecodeJson, decodeJson, (.:), (.:?))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple)

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

-- | Lovelace ca `Number`, nu `Int`: `drep_power_lovelace` era 505.754.377.083.269 la măsurătoare,
-- | iar `Int` în PureScript e pe 32 de biți. `Number` e exact până la 2^53 ≈ 9,007e15 lovelace (9
-- | miliarde de ADA), deci pe preprod e exact. Pe mainnet, cifra de always-abstain (~9,75e15) trece
-- | pragul — dar eroarea cade în ultimele cifre de lovelace, iar noi afișăm ADA cu două zecimale,
-- | deci nu se vede. Când se va vedea, drumul e decodare ca `String` plus `BigInt`.
type Lovelace = Number

-- | Un punct din seria de participare. `participation_rate` e `Maybe` deși măsurătoarea n-a găsit
-- | niciun `null` în 20 de puncte: o rată absentă se randează „n/a", iar „0%" ar fi o afirmație
-- | despre comportament, nu despre date.
newtype EpochPoint = EpochPoint
  { epoch :: Int
  , drepsWithPower :: Int
  , drepsVoted :: Int
  , votesCast :: Int
  , participationRate :: Maybe Number
  }

derive instance Eq EpochPoint

instance DecodeJson EpochPoint where
  decodeJson json = do
    o <- decodeJson json
    epoch <- o .: "epoch"
    drepsWithPower <- o .: "dreps_with_power"
    drepsVoted <- o .: "dreps_voted"
    votesCast <- o .: "votes_cast"
    participationRate <- o .:? "participation_rate"
    pure (EpochPoint { epoch, drepsWithPower, drepsVoted, votesCast, participationRate })

-- | Rândul de DRep, cu toate cele 22 de câmpuri pe care le întoarce serverul. E același obiect în
-- | `top_dreps_by_power` de pe dashboard și în `items` din lista de DRep-i, deci se decodează o
-- | singură dată, aici.
-- |
-- | Ce e `Maybe` nu e ales din prudență, ci din măsurătoare pe 200 de rânduri reale: `given_name`
-- | lipsea la 154, `image_url` la 162, `language` la 151, `anchor_status` la 108, `rationale_rate`
-- | la 172, `last_vote_at` la 166, `active_until_epoch` la 9. Restul n-aveau niciun `null`.
newtype DRepSummary = DRepSummary
  { id :: String
  , hex :: String
  , hasScript :: Boolean
  , status :: String
  , isActive :: Boolean
  , activeUntilEpoch :: Maybe Int
  , givenName :: Maybe String
  , imageUrl :: Maybe String
  , language :: Maybe String
  , anchorStatus :: Maybe String
  , registeredAt :: String
  , ageDays :: Int
  , votingPower :: Lovelace
  , votingPowerEpoch :: Int
  , delegatorCount :: Int
  , eligibleActions :: Int
  , votesCast :: Int
  , participationRate :: Maybe Number
  , rationaleRate :: Maybe Number
  , openActionsUnvoted :: Int
  , lastVoteAt :: Maybe String
  , asOfEpoch :: Int
  }

derive instance Eq DRepSummary

instance DecodeJson DRepSummary where
  decodeJson json = do
    o <- decodeJson json
    id <- o .: "id"
    hex <- o .: "hex"
    hasScript <- o .: "has_script"
    status <- o .: "status"
    isActive <- o .: "is_active"
    activeUntilEpoch <- o .:? "active_until_epoch"
    givenName <- o .:? "given_name"
    imageUrl <- o .:? "image_url"
    language <- o .:? "language"
    anchorStatus <- o .:? "anchor_status"
    registeredAt <- o .: "registered_at"
    ageDays <- o .: "age_days"
    votingPower <- o .: "voting_power"
    votingPowerEpoch <- o .: "voting_power_epoch"
    delegatorCount <- o .: "delegator_count"
    eligibleActions <- o .: "eligible_actions"
    votesCast <- o .: "votes_cast"
    participationRate <- o .:? "participation_rate"
    rationaleRate <- o .:? "rationale_rate"
    openActionsUnvoted <- o .: "open_actions_unvoted"
    lastVoteAt <- o .:? "last_vote_at"
    asOfEpoch <- o .: "as_of_epoch"
    pure
      ( DRepSummary
          { id
          , hex
          , hasScript
          , status
          , isActive
          , activeUntilEpoch
          , givenName
          , imageUrl
          , language
          , anchorStatus
          , registeredAt
          , ageDays
          , votingPower
          , votingPowerEpoch
          , delegatorCount
          , eligibleActions
          , votesCast
          , participationRate
          , rationaleRate
          , openActionsUnvoted
          , lastVoteAt
          , asOfEpoch
          }
      )

-- | Rândul de acțiune de guvernanță, din care se citesc câmpurile pe care le randează cineva acum.
-- | `proposed_at` și `lifecycle` sunt obiecte imbricate pe care le întoarce serverul și pe care
-- | niciun ecran livrat nu le arată încă; decodorul le ignoră, pentru că Argonaut citește cheile pe
-- | care le numește. Detaliul de acțiune (taskul 8) le adaugă când le afișează.
newtype GovActionSummary = GovActionSummary
  { id :: String
  , bech32 :: String
  , type_ :: String
  , title :: Maybe String
  , anchorStatus :: Maybe String
  , expiresEpoch :: Int
  , lastVotableEpoch :: Int
  , treasuryAmount :: Maybe Lovelace
  , votesCast :: Int
  }

derive instance Eq GovActionSummary

instance DecodeJson GovActionSummary where
  decodeJson json = do
    o <- decodeJson json
    id <- o .: "id"
    bech32 <- o .: "bech32"
    type_ <- o .: "type"
    title <- o .:? "title"
    anchorStatus <- o .:? "anchor_status"
    expiresEpoch <- o .: "expires_epoch"
    lastVotableEpoch <- o .: "last_votable_epoch"
    treasuryAmount <- o .:? "treasury_amount"
    votesCast <- o .: "votes_cast"
    pure
      ( GovActionSummary
          { id, bech32, type_, title, anchorStatus, expiresEpoch, lastVotableEpoch, treasuryAmount, votesCast }
      )

-- | `GET /pages/dashboard`, un singur apel pentru tot ecranul de pornire.
-- |
-- | Trei lucruri pe care forma răspunsului le impune ecranului:
-- |
-- |   * `total_dreps` (294) __nu__ e `active + inactive` (204). Diferența sunt cei cu status
-- |     `unknown`. Orice link de la o cifră spre listă trebuie să poarte filtrul cifrei;
-- |   * trezoreria sunt __două__ numere — cerut și adoptat — iar `treasury_enacted_lovelace` era 0
-- |     la măsurătoare. Un singur număr ar sugera că s-au plătit 656 de milioane de ADA;
-- |   * `power_epoch` e epoca distribuției de putere, separată de `epoch`. Cifrele de putere se
-- |     etichetează cu ea.
newtype DashboardPage = DashboardPage
  { epoch :: Int
  , totalDreps :: Int
  , activeDreps :: Int
  , inactiveDreps :: Int
  , unknownDreps :: Int
  , retiredDreps :: Int
  , powerEpoch :: Int
  , drepPowerLovelace :: Lovelace
  , alwaysAbstainLovelace :: Lovelace
  , alwaysNoConfidenceLovelace :: Lovelace
  , totalActions :: Int
  , actionsInFlight :: Int
  , treasuryRequestedLovelace :: Lovelace
  , treasuryEnactedLovelace :: Lovelace
  , actionsByType :: Array (Tuple String Int)
  , actionsByState :: Array (Tuple String Int)
  , participationByEpoch :: Array EpochPoint
  , topDrepsByPower :: Array DRepSummary
  , closingSoon :: Array GovActionSummary
  }

derive instance Eq DashboardPage

instance DecodeJson DashboardPage where
  decodeJson json = do
    o <- decodeJson json
    epoch <- o .: "epoch"
    totalDreps <- o .: "total_dreps"
    activeDreps <- o .: "active_dreps"
    inactiveDreps <- o .: "inactive_dreps"
    unknownDreps <- o .: "unknown_dreps"
    retiredDreps <- o .: "retired_dreps"
    powerEpoch <- o .: "power_epoch"
    drepPowerLovelace <- o .: "drep_power_lovelace"
    alwaysAbstainLovelace <- o .: "always_abstain_lovelace"
    alwaysNoConfidenceLovelace <- o .: "always_no_confidence_lovelace"
    totalActions <- o .: "total_actions"
    actionsInFlight <- o .: "actions_in_flight"
    treasuryRequestedLovelace <- o .: "treasury_requested_lovelace"
    treasuryEnactedLovelace <- o .: "treasury_enacted_lovelace"
    actionsByType <- o .: "actions_by_type"
    actionsByState <- o .: "actions_by_state"
    participationByEpoch <- o .: "participation_by_epoch"
    topDrepsByPower <- o .: "top_dreps_by_power"
    closingSoon <- o .: "closing_soon"
    pure
      ( DashboardPage
          { epoch
          , totalDreps
          , activeDreps
          , inactiveDreps
          , unknownDreps
          , retiredDreps
          , powerEpoch
          , drepPowerLovelace
          , alwaysAbstainLovelace
          , alwaysNoConfidenceLovelace
          , totalActions
          , actionsInFlight
          , treasuryRequestedLovelace
          , treasuryEnactedLovelace
          , actionsByType
          , actionsByState
          , participationByEpoch
          , topDrepsByPower
          , closingSoon
          }
      )

-- | Un interval de putere de vot, cu numărul de DRep-i din el. `hi` lipsește la ultimul bucket:
-- | „peste un milion de ADA" nu are plafon.
newtype PowerBucket = PowerBucket
  { lo :: Lovelace
  , hi :: Maybe Lovelace
  , count :: Int
  }

derive instance Eq PowerBucket

instance DecodeJson PowerBucket where
  decodeJson json = do
    o <- decodeJson json
    lo <- o .: "lo"
    hi <- o .:? "hi"
    count <- o .: "count"
    pure (PowerBucket { lo, hi, count })

-- | `GET /pages/drep-explorer` — rândurile, totalul, facetele barei laterale și desfășurarea pe
-- | intervale de putere, într-un singur apel. Fără el, bara laterală ar trage patru numărători la
-- | fiecare tastă apăsată.
-- |
-- | __Facetele nu însumează la `total`__, și asta nu e un bug: fiecare se numără cu propriul
-- | predicat scos, ca bara să poată arăta „Retired (526)" în timp ce filtrul activ e
-- | `status=active`. Măsurat: 17+187+526+90 = 820, iar `total` era 294. Deci niciun procent nu se
-- | calculează dintr-un facet. `power_buckets` e singura excepție — fiecare DRep cade în exact un
-- | interval, și cele șase însumau exact 294.
newtype DRepExplorerPage = DRepExplorerPage
  { items :: Array DRepSummary
  , total :: Int
  , limit :: Int
  , offset :: Int
  , epoch :: Int
  , statusFacets :: Array (Tuple String Int)
  , anchorFacets :: Array (Tuple String Int)
  , languageFacets :: Array (Tuple String Int)
  , powerBuckets :: Array PowerBucket
  }

derive instance Eq DRepExplorerPage

instance DecodeJson DRepExplorerPage where
  decodeJson json = do
    o <- decodeJson json
    items <- o .: "items"
    total <- o .: "total"
    limit <- o .: "limit"
    offset <- o .: "offset"
    epoch <- o .: "epoch"
    statusFacets <- o .: "status_facets"
    anchorFacets <- o .: "anchor_facets"
    languageFacets <- o .: "language_facets"
    powerBuckets <- o .: "power_buckets"
    pure
      ( DRepExplorerPage
          { items, total, limit, offset, epoch, statusFacets, anchorFacets, languageFacets, powerBuckets }
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
