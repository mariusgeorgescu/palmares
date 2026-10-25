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
  , Lifecycle(..)
  , GovActionSummary(..)
  , DashboardPage(..)
  , PowerBucket(..)
  , DRepExplorerPage(..)
  , ChainPoint(..)
  , FinalVotes(..)
  , VoteTypeStats(..)
  , DRepMetrics(..)
  , DelegatorStats(..)
  , PowerPoint(..)
  , Delegator(..)
  , DRepUpdate(..)
  , AnchorRef(..)
  , AnchorContent(..)
  , DRepDetail(..)
  , Tally(..)
  , Withdrawal(..)
  , ParamChange(..)
  , Proposer(..)
  , ActionAnchor(..)
  , GovActionDetail(..)
  , GovActionPage(..)
  , VoteAnchor(..)
  , VoteRow(..)
  , VotePage(..)
  ) where

import Prelude

import Data.Argonaut.Decode (class DecodeJson, decodeJson, (.:), (.:?))
import Data.Maybe (Maybe(..), fromMaybe)
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

-- | Ciclul de viață al unei acțiuni. Cele patru epoci sunt separate și toate opționale, pentru că
-- | o acțiune reală măsurată avea __și__ `expired_epoch` 304 __și__ `dropped_epoch` 305: starea e
-- | un cuvânt, dar drumul până la ea are mai mulți pași, iar `formula_id` spune care regulă l-a
-- | decis.
newtype Lifecycle = Lifecycle
  { state :: String
  , ratifiedEpoch :: Maybe Int
  , enactedEpoch :: Maybe Int
  , expiredEpoch :: Maybe Int
  , droppedEpoch :: Maybe Int
  , formulaId :: Maybe String
  }

derive instance Eq Lifecycle

instance DecodeJson Lifecycle where
  decodeJson json = do
    o <- decodeJson json
    state <- o .: "state"
    ratifiedEpoch <- o .:? "ratified_epoch"
    enactedEpoch <- o .:? "enacted_epoch"
    expiredEpoch <- o .:? "expired_epoch"
    droppedEpoch <- o .:? "dropped_epoch"
    formulaId <- o .:? "formula_id"
    pure (Lifecycle { state, ratifiedEpoch, enactedEpoch, expiredEpoch, droppedEpoch, formulaId })

-- | Rândul de acțiune de guvernanță. Același obiect în `closing_soon` de pe dashboard, în `items`
-- | din listă și în `action` din detaliu, deci un singur decodor.
newtype GovActionSummary = GovActionSummary
  { id :: String
  , bech32 :: String
  , type_ :: String
  , title :: Maybe String
  , abstract :: Maybe String
  , anchorStatus :: Maybe String
  , proposedAt :: ChainPoint
  , expiresEpoch :: Int
  , lastVotableEpoch :: Int
  , lifecycle :: Lifecycle
  , deposit :: Maybe Lovelace
  , returnAddress :: Maybe String
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
    abstract <- o .:? "abstract"
    anchorStatus <- o .:? "anchor_status"
    proposedAt <- o .: "proposed_at"
    expiresEpoch <- o .: "expires_epoch"
    lastVotableEpoch <- o .: "last_votable_epoch"
    lifecycle <- o .: "lifecycle"
    deposit <- o .:? "deposit"
    returnAddress <- o .:? "return_address"
    treasuryAmount <- o .:? "treasury_amount"
    votesCast <- o .: "votes_cast"
    pure
      ( GovActionSummary
          { id
          , bech32
          , type_
          , title
          , abstract
          , anchorStatus
          , proposedAt
          , expiresEpoch
          , lastVotableEpoch
          , lifecycle
          , deposit
          , returnAddress
          , treasuryAmount
          , votesCast
          }
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

-- | Un punct în lanț: slotul, epoca, ora și tranzacția. Apare peste tot unde un eveniment trebuie
-- | să poată fi verificat de cineva care nu ne crede pe cuvânt — de aceea `txHash` nu e opțional.
newtype ChainPoint = ChainPoint
  { slot :: Int
  , epoch :: Int
  , time :: String
  , txHash :: String
  }

derive instance Eq ChainPoint

instance DecodeJson ChainPoint where
  decodeJson json = do
    o <- decodeJson json
    slot <- o .: "slot"
    epoch <- o .: "epoch"
    time <- o .: "time"
    txHash <- o .: "tx_hash"
    pure (ChainPoint { slot, epoch, time, txHash })

newtype FinalVotes = FinalVotes
  { yes :: Int
  , no :: Int
  , abstain :: Int
  }

derive instance Eq FinalVotes

instance DecodeJson FinalVotes where
  decodeJson json = do
    o <- decodeJson json
    yes <- o .: "yes"
    no <- o .: "no"
    abstain <- o .: "abstain"
    pure (FinalVotes { yes, no, abstain })

-- | Comportamentul pe un tip de acțiune. `eligible_actions` e numitorul, și e per tip: un DRep care
-- | a votat o dată din două acțiuni de hard fork are 50%, nu 0,8% din total.
newtype VoteTypeStats = VoteTypeStats
  { eligibleActions :: Int
  , votesCast :: Int
  , yes :: Int
  , no :: Int
  , abstain :: Int
  , participationRate :: Maybe Number
  }

derive instance Eq VoteTypeStats

instance DecodeJson VoteTypeStats where
  decodeJson json = do
    o <- decodeJson json
    eligibleActions <- o .: "eligible_actions"
    votesCast <- o .: "votes_cast"
    yes <- o .: "yes"
    no <- o .: "no"
    abstain <- o .: "abstain"
    participationRate <- o .:? "participation_rate"
    pure (VoteTypeStats { eligibleActions, votesCast, yes, no, abstain, participationRate })

-- | Metricile unui DRep, cu desfășurarea raționamentelor pe șase stări.
-- |
-- | Cele șase nu sunt decor: „absent" (n-a publicat nimic), „pending" (n-am verificat încă),
-- | „unverified" (am încercat și n-am putut) și „verified" sunt fapte diferite despre lume, iar un
-- | singur procent le-ar topi într-o acuzație. `formulaIds` sunt formulele publicate din care au
-- | ieșit cifrele — fiecare rezolvabilă în `/metrics/formulas`.
newtype DRepMetrics = DRepMetrics
  { asOfEpoch :: Int
  , eligibleActions :: Int
  , votesCast :: Int
  , openActionsUnvoted :: Int
  , participationRate :: Maybe Number
  , rationaleVerified :: Int
  , rationaleInline :: Int
  , rationaleUnverified :: Int
  , rationalePending :: Int
  , rationaleAbsent :: Int
  , rationaleCip100Valid :: Int
  , rationaleRate :: Maybe Number
  , voteLatencyMedianHours :: Maybe Number
  , voteLatencyP90Hours :: Maybe Number
  , voteLatencySample :: Int
  , ageDays :: Int
  , finalVotes :: FinalVotes
  , votesByType :: Array (Tuple String VoteTypeStats)
  , formulaIds :: Array String
  }

derive instance Eq DRepMetrics

instance DecodeJson DRepMetrics where
  decodeJson json = do
    o <- decodeJson json
    asOfEpoch <- o .: "as_of_epoch"
    eligibleActions <- o .: "eligible_actions"
    votesCast <- o .: "votes_cast"
    openActionsUnvoted <- o .: "open_actions_unvoted"
    participationRate <- o .:? "participation_rate"
    rationaleVerified <- o .: "rationale_verified"
    rationaleInline <- o .: "rationale_inline"
    rationaleUnverified <- o .: "rationale_unverified"
    rationalePending <- o .: "rationale_pending"
    rationaleAbsent <- o .: "rationale_absent"
    rationaleCip100Valid <- o .: "rationale_cip100_valid"
    rationaleRate <- o .:? "rationale_rate"
    voteLatencyMedianHours <- o .:? "vote_latency_median_hours"
    voteLatencyP90Hours <- o .:? "vote_latency_p90_hours"
    voteLatencySample <- o .: "vote_latency_sample"
    ageDays <- o .: "age_days"
    finalVotes <- o .: "final_votes"
    votesByType <- o .: "votes_by_type"
    formulaIds <- o .: "formula_ids"
    pure
      ( DRepMetrics
          { asOfEpoch
          , eligibleActions
          , votesCast
          , openActionsUnvoted
          , participationRate
          , rationaleVerified
          , rationaleInline
          , rationaleUnverified
          , rationalePending
          , rationaleAbsent
          , rationaleCip100Valid
          , rationaleRate
          , voteLatencyMedianHours
          , voteLatencyP90Hours
          , voteLatencySample
          , ageDays
          , finalVotes
          , votesByType
          , formulaIds
          }
      )

-- | Mișcarea delegatorilor pe o fereastră de epoci. `delegator_count_prev` e termenul de comparație
-- | pe care serverul l-a calculat; fără el, „19 delegatori" nu spune dacă e în creștere.
newtype DelegatorStats = DelegatorStats
  { delegatorCount :: Int
  , delegatorCountPrev :: Int
  , delegatorsRetained :: Int
  , delegatorsJoined :: Int
  , delegatorsLeft :: Int
  , delegatorRetentionRate :: Maybe Number
  , windowEpochs :: Int
  }

derive instance Eq DelegatorStats

instance DecodeJson DelegatorStats where
  decodeJson json = do
    o <- decodeJson json
    delegatorCount <- o .: "delegator_count"
    delegatorCountPrev <- o .: "delegator_count_prev"
    delegatorsRetained <- o .: "delegators_retained"
    delegatorsJoined <- o .: "delegators_joined"
    delegatorsLeft <- o .: "delegators_left"
    delegatorRetentionRate <- o .:? "delegator_retention_rate"
    windowEpochs <- o .: "window_epochs"
    pure
      ( DelegatorStats
          { delegatorCount
          , delegatorCountPrev
          , delegatorsRetained
          , delegatorsJoined
          , delegatorsLeft
          , delegatorRetentionRate
          , windowEpochs
          }
      )

newtype PowerPoint = PowerPoint
  { epoch :: Int
  , lovelace :: Lovelace
  , delegatorCount :: Int
  }

derive instance Eq PowerPoint

instance DecodeJson PowerPoint where
  decodeJson json = do
    o <- decodeJson json
    epoch <- o .: "epoch"
    lovelace <- o .: "lovelace"
    delegatorCount <- o .: "delegator_count"
    pure (PowerPoint { epoch, lovelace, delegatorCount })

-- | `lovelace` e `Maybe`, și nu din prudență: măsurat pe serverul care rulează, al cincilea
-- | delegator al unui DRep real îl avea `null`. Suma delegată se citește din `epoch_stake`, iar
-- | epoca poate să n-aibă încă rândul (limitarea §8.3 din contractul API-ului). Un decodor care
-- | cerea un număr a rupt tot ecranul pentru un singur rând incomplet.
newtype Delegator = Delegator
  { stakeAddress :: String
  , lovelace :: Maybe Lovelace
  , delegatedAt :: ChainPoint
  , isCurrent :: Boolean
  }

derive instance Eq Delegator

instance DecodeJson Delegator where
  decodeJson json = do
    o <- decodeJson json
    stakeAddress <- o .: "stake_address"
    lovelace <- o .:? "lovelace"
    delegatedAt <- o .: "delegated_at"
    isCurrent <- o .: "is_current"
    pure (Delegator { stakeAddress, lovelace, delegatedAt, isCurrent })

-- | Un eveniment din viața înregistrării: `registered`, `updated`, `retired`. `anchor_url` e cel
-- | declarat la acel moment, deci istoria metadatelor se vede fără să ne credem pe cuvânt.
newtype DRepUpdate = DRepUpdate
  { kind :: String
  , at :: ChainPoint
  , deposit :: Maybe Lovelace
  , anchorUrl :: Maybe String
  , anchorStatus :: Maybe String
  }

derive instance Eq DRepUpdate

instance DecodeJson DRepUpdate where
  decodeJson json = do
    o <- decodeJson json
    kind <- o .: "kind"
    at <- o .: "at"
    deposit <- o .:? "deposit"
    anchorUrl <- o .:? "anchor_url"
    anchorStatus <- o .:? "anchor_status"
    pure (DRepUpdate { kind, at, deposit, anchorUrl, anchorStatus })

-- | O referință din documentul de metadate. Scrisă de autorul documentului, deci `uri` e text
-- | neîncrezut: `Components.Shared.Anchor` decide dacă devine link sau rămâne text.
newtype AnchorRef = AnchorRef
  { label :: Maybe String
  , uri :: Maybe String
  }

derive instance Eq AnchorRef

instance DecodeJson AnchorRef where
  decodeJson json = do
    o <- decodeJson json
    label <- o .:? "label"
    uri <- o .:? "uri"
    pure (AnchorRef { label, uri })

-- | Conținutul documentului CIP-119, normalizat de server la șapte câmpuri (verificat pe șase
-- | documente reale, toate aveau exact același set de chei).
-- |
-- | __Totul de aici e text străin.__ Niciun câmp nu ajunge pe ecran ca HTML, toate se taie la
-- | randare, și `image_url`/`payment_address` nu se folosesc ca să se încarce sau să se plătească
-- | ceva — se arată.
newtype AnchorContent = AnchorContent
  { givenName :: Maybe String
  , objectives :: Maybe String
  , motivations :: Maybe String
  , qualifications :: Maybe String
  , imageUrl :: Maybe String
  , paymentAddress :: Maybe String
  , references :: Array AnchorRef
  }

derive instance Eq AnchorContent

instance DecodeJson AnchorContent where
  decodeJson json = do
    o <- decodeJson json
    givenName <- o .:? "given_name"
    objectives <- o .:? "objectives"
    motivations <- o .:? "motivations"
    qualifications <- o .:? "qualifications"
    imageUrl <- o .:? "image_url"
    paymentAddress <- o .:? "payment_address"
    references <- fromMaybe [] <$> o .:? "references"
    pure
      ( AnchorContent
          { givenName, objectives, motivations, qualifications, imageUrl, paymentAddress, references }
      )

-- | `GET /pages/drep/{id}` — identitatea, metricile, delegatorii, puterea pe epoci, istoria
-- | înregistrării și documentul de metadate, într-un __singur__ apel.
-- |
-- | Ce nu e aici: istoricul de voturi. Nu lipsește din greșeală — `/votes` filtrat după acest DRep
-- | e propriul ecran, cu propria paginare, iar un istoric întreg lipit aici ar fi exact adâncimea
-- | pe care serverul o servește în 12 secunde.
newtype DRepDetail = DRepDetail
  { drep :: DRepSummary
  , metrics :: DRepMetrics
  , delegatorStats :: DelegatorStats
  , powerByEpoch :: Array PowerPoint
  , topDelegators :: Array Delegator
  , updates :: Array DRepUpdate
  , anchorContent :: Maybe AnchorContent
  }

derive instance Eq DRepDetail

instance DecodeJson DRepDetail where
  decodeJson json = do
    o <- decodeJson json
    drep <- o .: "drep"
    metrics <- o .: "metrics"
    delegatorStats <- o .: "delegator_stats"
    powerByEpoch <- o .: "power_by_epoch"
    topDelegators <- o .: "top_delegators"
    updates <- o .: "updates"
    anchorContent <- o .:? "anchor_content"
    pure
      ( DRepDetail
          { drep, metrics, delegatorStats, powerByEpoch, topDelegators, updates, anchorContent }
      )

-- | Numărătoarea voturilor pentru un rol, la o epocă.
-- |
-- | `ratio` e `Maybe` pentru un motiv măsurat: pe o acțiune reală, cu 43 de voturi exprimate, era
-- | `null` — pragul se calculează pe putere de vot, iar când puterea de partea „da" și cea de
-- | partea „nu" sunt amândouă zero, raportul nu există. „0%" ar fi o afirmație despre rezultat;
-- | „n/a" e adevărul. `threshold_param` numește parametrul de protocol care a dat pragul, iar
-- | `basis` spune ce a intrat în numitor (`cast_votes_only`).
newtype Tally = Tally
  { role :: String
  , epoch :: Int
  , yesPower :: Lovelace
  , noPower :: Lovelace
  , abstainPower :: Lovelace
  , yesCount :: Int
  , noCount :: Int
  , abstainCount :: Int
  , ratio :: Maybe Number
  , threshold :: Maybe Number
  , thresholdParam :: Maybe String
  , basis :: Maybe String
  , formulaId :: Maybe String
  }

derive instance Eq Tally

instance DecodeJson Tally where
  decodeJson json = do
    o <- decodeJson json
    role <- o .: "role"
    epoch <- o .: "epoch"
    yesPower <- o .: "yes_power"
    noPower <- o .: "no_power"
    abstainPower <- o .: "abstain_power"
    yesCount <- o .: "yes_count"
    noCount <- o .: "no_count"
    abstainCount <- o .: "abstain_count"
    ratio <- o .:? "ratio"
    threshold <- o .:? "threshold"
    thresholdParam <- o .:? "threshold_param"
    basis <- o .:? "basis"
    formulaId <- o .:? "formula_id"
    pure
      ( Tally
          { role
          , epoch
          , yesPower
          , noPower
          , abstainPower
          , yesCount
          , noCount
          , abstainCount
          , ratio
          , threshold
          , thresholdParam
          , basis
          , formulaId
          }
      )

-- | O retragere propusă. `paid_heuristic` e cinstea serverului: plata nu se poate citi direct din
-- | lanț pentru fiecare caz, deci câmpul spune când „plătit" e o deducție, nu o observație. Ecranul
-- | trebuie să spună același lucru.
newtype Withdrawal = Withdrawal
  { beneficiary :: String
  , amount :: Lovelace
  , enactedAt :: Maybe ChainPoint
  , paidHeuristic :: Boolean
  }

derive instance Eq Withdrawal

instance DecodeJson Withdrawal where
  decodeJson json = do
    o <- decodeJson json
    beneficiary <- o .: "beneficiary"
    amount <- o .: "amount"
    enactedAt <- o .:? "enacted_at"
    paidHeuristic <- o .: "paid_heuristic"
    pure (Withdrawal { beneficiary, amount, enactedAt, paidHeuristic })

-- | Un parametru de protocol pe care acțiunea îl schimbă, cu grupul din care își ia pragul.
newtype ParamChange = ParamChange
  { param :: String
  , group :: Maybe String
  }

derive instance Eq ParamChange

instance DecodeJson ParamChange where
  decodeJson json = do
    o <- decodeJson json
    param <- o .: "param"
    group <- o .:? "group"
    pure (ParamChange { param, group })

-- | Cine a propus, și de câte ori. `actions_count` e contextul care transformă „o adresă de stake"
-- | în „cineva care a propus deja de zece ori".
newtype Proposer = Proposer
  { stakeAddress :: String
  , actionsCount :: Int
  }

derive instance Eq Proposer

instance DecodeJson Proposer where
  decodeJson json = do
    o <- decodeJson json
    stakeAddress <- o .: "stake_address"
    actionsCount <- o .: "actions_count"
    pure (Proposer { stakeAddress, actionsCount })

-- | Documentul de metadate al unei acțiuni — CIP-108, deci __alt set de câmpuri__ decât documentul
-- | unui DRep (CIP-119). Măsurat pe o propunere reală: `rationale` avea peste 2.500 de caractere,
-- | iar `references` conținea același link de două ori. Amândouă se randează așa cum sunt: e
-- | documentul lor, iar un deduplicator ar ascunde ce au scris.
newtype ActionAnchor = ActionAnchor
  { title :: Maybe String
  , abstract :: Maybe String
  , motivation :: Maybe String
  , rationale :: Maybe String
  , references :: Array AnchorRef
  }

derive instance Eq ActionAnchor

instance DecodeJson ActionAnchor where
  decodeJson json = do
    o <- decodeJson json
    title <- o .:? "title"
    abstract <- o .:? "abstract"
    motivation <- o .:? "motivation"
    rationale <- o .:? "rationale"
    references <- fromMaybe [] <$> o .:? "references"
    pure (ActionAnchor { title, abstract, motivation, rationale, references })

-- | `GET /pages/gov-action/{id}` — acțiunea, numărătorile pe rol, retragerile, parametrii atinși,
-- | proponentul și documentul, într-un apel.
newtype GovActionDetail = GovActionDetail
  { action :: GovActionSummary
  , tallies :: Array Tally
  , withdrawals :: Array Withdrawal
  , paramChanges :: Array ParamChange
  , proposer :: Maybe Proposer
  , anchorContent :: Maybe ActionAnchor
  }

derive instance Eq GovActionDetail

instance DecodeJson GovActionDetail where
  decodeJson json = do
    o <- decodeJson json
    action <- o .: "action"
    tallies <- fromMaybe [] <$> o .:? "tallies"
    withdrawals <- fromMaybe [] <$> o .:? "withdrawals"
    paramChanges <- fromMaybe [] <$> o .:? "param_changes"
    proposer <- o .:? "proposer"
    anchorContent <- o .:? "anchor_content"
    pure (GovActionDetail { action, tallies, withdrawals, paramChanges, proposer, anchorContent })

-- | Plicul rutelor de listă: `items`, `total`, `limit`, `offset`. `next_cursor` există în răspuns
-- | dar nu e modelat — singura rută cu cursor e `/activity`, și n-o randează nimeni.
newtype GovActionPage = GovActionPage
  { items :: Array GovActionSummary
  , total :: Int
  , limit :: Int
  , offset :: Int
  }

derive instance Eq GovActionPage

instance DecodeJson GovActionPage where
  decodeJson json = do
    o <- decodeJson json
    items <- o .: "items"
    total <- o .: "total"
    limit <- o .: "limit"
    offset <- o .: "offset"
    pure (GovActionPage { items, total, limit, offset })

-- | Ancora unui raționament de vot: URL-ul, starea verificării, și dacă documentul respectă
-- | CIP-100. Măsurat: din ~934 de voturi finale pe preprod, __opt__ au o ancoră validă.
newtype VoteAnchor = VoteAnchor
  { url :: Maybe String
  , status :: Maybe String
  , cip100Valid :: Maybe Boolean
  }

derive instance Eq VoteAnchor

instance DecodeJson VoteAnchor where
  decodeJson json = do
    o <- decodeJson json
    url <- o .:? "url"
    status <- o .:? "status"
    cip100Valid <- o .:? "cip100_valid"
    pure (VoteAnchor { url, status, cip100Valid })

-- | Un vot, cu acțiunea și votantul denormalizate în rând — de aceea ecranul de voturi nu face
-- | N+1 ca să scrie un tabel.
-- |
-- | `is_final` și `revote_count` sunt amândouă aici pentru că un DRep __poate__ să-și schimbe
-- | votul cât acțiunea e deschisă: un rând cu `is_final: false` e un vot care a fost înlocuit, iar
-- | un ecran care nu face diferența numără același votant de mai multe ori. `voting_power` e
-- | `Maybe` și măsurat era `null` pe toate rândurile verificate.
newtype VoteRow = VoteRow
  { govActionId :: String
  , govActionBech32 :: String
  , govActionType :: String
  , govActionTitle :: Maybe String
  , voterRole :: String
  , voterId :: String
  , voterHotHash :: Maybe String
  , voterName :: Maybe String
  , verdict :: String
  , castAt :: ChainPoint
  , latencyHours :: Maybe Number
  , isFinal :: Boolean
  , isFirst :: Boolean
  , revoteCount :: Int
  , anchor :: Maybe VoteAnchor
  , votingPower :: Maybe Lovelace
  , votingPowerEpoch :: Maybe Int
  }

derive instance Eq VoteRow

instance DecodeJson VoteRow where
  decodeJson json = do
    o <- decodeJson json
    govActionId <- o .: "gov_action_id"
    govActionBech32 <- o .: "gov_action_bech32"
    govActionType <- o .: "gov_action_type"
    govActionTitle <- o .:? "gov_action_title"
    voterRole <- o .: "voter_role"
    voterId <- o .: "voter_id"
    voterHotHash <- o .:? "voter_hot_hash"
    voterName <- o .:? "voter_name"
    verdict <- o .: "verdict"
    castAt <- o .: "cast_at"
    latencyHours <- o .:? "latency_hours"
    isFinal <- o .: "is_final"
    isFirst <- o .: "is_first"
    revoteCount <- o .: "revote_count"
    anchor <- o .:? "anchor"
    votingPower <- o .:? "voting_power"
    votingPowerEpoch <- o .:? "voting_power_epoch"
    pure
      ( VoteRow
          { govActionId
          , govActionBech32
          , govActionType
          , govActionTitle
          , voterRole
          , voterId
          , voterHotHash
          , voterName
          , verdict
          , castAt
          , latencyHours
          , isFinal
          , isFirst
          , revoteCount
          , anchor
          , votingPower
          , votingPowerEpoch
          }
      )

newtype VotePage = VotePage
  { items :: Array VoteRow
  , total :: Int
  , limit :: Int
  , offset :: Int
  }

derive instance Eq VotePage

instance DecodeJson VotePage where
  decodeJson json = do
    o <- decodeJson json
    items <- o .: "items"
    total <- o .: "total"
    limit <- o .: "limit"
    offset <- o .: "offset"
    pure (VotePage { items, total, limit, offset })

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
