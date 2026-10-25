-- | Corpurile celor nouă fluxuri de scriere, plus transportul comun.
-- |
-- | __Codificatoarele sunt scrise de mână, și aici motivul e mai tare decât la citire:__ corpurile
-- | de scriere sunt snake_case LA EXTERIOR și camelCase ÎN INTERIOR. `user_addresses` conține
-- | `usedAddresses` și `changeAddress`. Un singur modificator global de nume — generic sau derivat
-- | — ar rupe exact jumătate din fiecare cerere, iar serverul ar răspunde cu o eroare de validare
-- | care arată ca „datele tale sunt greșite" în loc de „clientul tău serializează greșit".
-- | Măsurat din `swagger-api.json` al lui interaction-api, nu din design.
module Capabilities.Interaction.Types
  ( UserAddresses
  , FlowRequest(..)
  , flowPath
  , flowLabel
  , encodeFlow
  , SubmitParams
  , encodeSubmit
  , profileKinds
  , attestationKinds
  , disputeVerdicts
  , OracleParams(..)
  , InteractionStatus(..)
  , oracleGate
  , OracleGate(..)
  ) where

import Prelude

import Data.Argonaut.Core (Json, jsonEmptyObject)
import Data.Argonaut.Decode (class DecodeJson, decodeJson, (.:), (.:?))
import Data.Argonaut.Encode ((:=), (~>))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Capabilities.Query.Gov.Types (Lovelace)

-- | Adresele pe care serverul le folosește ca să aleagă intrările și să dea restul.
-- |
-- | Cheile sunt camelCase pentru că AȘA le cere serverul, înăuntrul unui corp snake_case. Vezi
-- | antetul modulului.
type UserAddresses =
  { usedAddresses :: Array String
  , changeAddress :: String
  }

-- | Cele nouă fluxuri. Un singur tip, pentru că mecanica e identică — construiește, semnează,
-- | trimite, așteaptă — iar diferența e doar corpul și calea.
data FlowRequest
  = ClaimProfile
      { kind :: String
      , name :: String
      , description :: String
      , imageUri :: String
      , addresses :: UserAddresses
      }
  | UpdateProfile
      { profileId :: String
      , description :: Maybe String
      , imageUri :: String
      , addresses :: UserAddresses
      }
  | IssueAttestation
      { subjectProfileId :: String
      , issuerProfileId :: String
      , kind :: String
      , name :: String
      , description :: String
      , imageUri :: String
      , addresses :: UserAddresses
      }
  | AcceptAttestation
      { attestationId :: String
      , addresses :: UserAddresses
      }
  | OpenDispute
      { attestationId :: String
      , openedByProfileId :: String
      , name :: String
      , description :: String
      , imageUri :: String
      , addresses :: UserAddresses
      }
  | ResolveDispute
      { disputeId :: String
      , verdict :: String
      , addresses :: UserAddresses
      }
  | ExpireDispute
      { disputeId :: String
      , addresses :: UserAddresses
      }
  | ClaimCredential
      { profileId :: String
      , credential :: String
      , name :: String
      , description :: String
      , imageUri :: String
      , addresses :: UserAddresses
      }
  | WithdrawCredential
      { profileId :: String
      , credential :: String
      , name :: String
      , description :: String
      , imageUri :: String
      , addresses :: UserAddresses
      }

-- | Calea serverului pentru fiecare flux. Scrisă literal, nu derivată din numele constructorului:
-- | o derivare ar lega numele tipului de API, iar o redenumire inofensivă ar schimba tăcut ruta.
flowPath :: FlowRequest -> String
flowPath = case _ of
  ClaimProfile _ -> "/claim-profile"
  UpdateProfile _ -> "/update-profile"
  IssueAttestation _ -> "/issue-attestation"
  AcceptAttestation _ -> "/accept-attestation"
  OpenDispute _ -> "/open-dispute"
  ResolveDispute _ -> "/resolve-dispute"
  ExpireDispute _ -> "/expire-dispute"
  ClaimCredential _ -> "/claim-credential"
  WithdrawCredential _ -> "/withdraw-credential"

-- | Ce scrie pe buton și în mesajul de confirmare.
flowLabel :: FlowRequest -> String
flowLabel = case _ of
  ClaimProfile _ -> "Claim profile"
  UpdateProfile _ -> "Update profile"
  IssueAttestation _ -> "Issue attestation"
  AcceptAttestation _ -> "Accept attestation"
  OpenDispute _ -> "Open dispute"
  ResolveDispute _ -> "Resolve dispute"
  ExpireDispute _ -> "Expire dispute"
  ClaimCredential _ -> "Claim credential"
  WithdrawCredential _ -> "Withdraw credential"

-- | Cele șase feluri de profil, din enum-ul serverului.
profileKinds :: Array String
profileKinds = [ "person_d_rep", "organization", "committee", "community", "vendor", "auditor" ]

-- | Cele șapte feluri de atestare. Ultimele două — `credential_claim` și `credential_withdrawal` —
-- | NU se aleg de mână: le produce serverul pentru fluxurile de credențiale, iar un om care le-ar
-- | alege aici ar emite o atestare care pretinde ceva ce n-a fost dovedit.
attestationKinds :: Array String
attestationKinds =
  [ "milestone_delivered", "audit_passed", "affiliation", "role_held", "endorsement" ]

disputeVerdicts :: Array String
disputeVerdicts = [ "upheld", "dismissed" ]

encodeAddresses :: UserAddresses -> Json
encodeAddresses a =
  "usedAddresses" := a.usedAddresses
    ~> "changeAddress" := a.changeAddress
    ~> jsonEmptyObject

-- | Corpul cererii. Cheile exterioare snake_case, cele din `user_addresses` camelCase.
encodeFlow :: FlowRequest -> Json
encodeFlow = case _ of
  ClaimProfile r ->
    "kind" := r.kind
      ~> "name" := r.name
      ~> "description" := r.description
      ~> "image_uri" := r.imageUri
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject
  UpdateProfile r ->
    -- `description` se omite ca să se păstreze cea curentă; de-aia e `Maybe` și de-aia se
    -- serializează doar când există. Un `null` trimis ar șterge-o.
    withOptional (Tuple "description" r.description)
      ( "profile_id" := r.profileId
          ~> "image_uri" := r.imageUri
          ~> "user_addresses" := encodeAddresses r.addresses
          ~> jsonEmptyObject
      )
  IssueAttestation r ->
    "subject_profile_id" := r.subjectProfileId
      ~> "issuer_profile_id" := r.issuerProfileId
      ~> "kind" := r.kind
      ~> "name" := r.name
      ~> "description" := r.description
      ~> "image_uri" := r.imageUri
      -- Obligatoriu chiar gol: serverul îl cere în `required`.
      ~> "other_metadata" := ([] :: Array (Array String))
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject
  AcceptAttestation r ->
    "attestation_id" := r.attestationId
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject
  OpenDispute r ->
    "attestation_id" := r.attestationId
      ~> "opened_by_profile_id" := r.openedByProfileId
      ~> "name" := r.name
      ~> "description" := r.description
      ~> "image_uri" := r.imageUri
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject
  ResolveDispute r ->
    "dispute_id" := r.disputeId
      ~> "verdict" := r.verdict
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject
  ExpireDispute r ->
    "dispute_id" := r.disputeId
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject
  ClaimCredential r ->
    "profile_id" := r.profileId
      ~> "credential" := r.credential
      ~> "name" := r.name
      ~> "description" := r.description
      ~> "image_uri" := r.imageUri
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject
  WithdrawCredential r ->
    "profile_id" := r.profileId
      ~> "credential" := r.credential
      ~> "name" := r.name
      ~> "description" := r.description
      ~> "image_uri" := r.imageUri
      ~> "user_addresses" := encodeAddresses r.addresses
      ~> jsonEmptyObject

withOptional :: Tuple String (Maybe String) -> Json -> Json
withOptional kv rest = case snd kv of
  Nothing -> rest
  Just v -> fst kv := v ~> rest

-- | Tranzacția nesemnată plus martorul venit de la wallet.
type SubmitParams =
  { txUnsigned :: String
  , txWit :: String
  }

encodeSubmit :: SubmitParams -> Json
encodeSubmit p =
  "tx_unsigned" := p.txUnsigned
    ~> "tx_wit" := p.txWit
    ~> jsonEmptyObject

-- | Parametrii pe care oracolul îi impune acum. Depozitul de dispută e singurul număr pe care un om
-- | trebuie să-l vadă ÎNAINTE să deschidă o dispută — e ce riscă.
-- |
-- | Taxele sunt `Maybe` și sunt `null` pe preprod: protocolul permite taxe, deploymentul ăsta nu le
-- | cere. „Fără taxă" și „nu știm taxa" nu sunt același lucru, deci nu se scriu la fel.
newtype OracleParams = OracleParams
  { disputeDepositLovelace :: Lovelace
  , disputeTimeoutMs :: Number
  , minUtxoLovelace :: Lovelace
  , profileCreationFeeLovelace :: Maybe Lovelace
  , attestationFeeLovelace :: Maybe Lovelace
  }

derive instance Eq OracleParams

instance DecodeJson OracleParams where
  decodeJson json = do
    o <- decodeJson json
    disputeDepositLovelace <- o .: "dispute_deposit_lovelace"
    disputeTimeoutMs <- o .: "dispute_timeout_ms"
    minUtxoLovelace <- o .: "min_utxo_lovelace"
    profileCreationFeeLovelace <- o .:? "profile_creation_fee_lovelace"
    attestationFeeLovelace <- o .:? "attestation_fee_lovelace"
    pure
      ( OracleParams
          { disputeDepositLovelace
          , disputeTimeoutMs
          , minUtxoLovelace
          , profileCreationFeeLovelace
          , attestationFeeLovelace
          }
      )

-- | `GET /status` al lui interaction-api.
-- |
-- | `oraclePaused` și `oracle` sunt amândouă opționale în contractul serverului — NU sunt în
-- | `required` — și asta e informație, nu o scăpare: un server care n-a putut citi oracolul nu are
-- | ce să pună acolo. Vezi `oracleGate`.
newtype InteractionStatus = InteractionStatus
  { provider :: String
  , network :: String
  , deployedScripts :: Boolean
  , oraclePaused :: Maybe Boolean
  , oracle :: Maybe OracleParams
  }

derive instance Eq InteractionStatus

instance DecodeJson InteractionStatus where
  decodeJson json = do
    o <- decodeJson json
    provider <- o .: "provider"
    network <- o .: "network"
    deployedScripts <- o .: "deployed_scripts"
    oraclePaused <- o .:? "oracle_paused"
    oracle <- o .:? "oracle"
    pure (InteractionStatus { provider, network, deployedScripts, oraclePaused, oracle })

-- | Ce are voie să se întâmple, după starea oracolului.
data OracleGate
  = OracleOpen
  -- | Oracolul a oprit protocolul. E o stare voită a cuiva, nu o defecțiune.
  | OraclePaused
  -- | Nu se știe dacă e oprit. __Se blochează la fel ca „oprit"__, și din același motiv pentru
  -- | care se blochează o rețea nedeterminată: a presupune „probabil merge" înseamnă a construi o
  -- | tranzacție care va fi respinsă de validator după ce omul a semnat-o.
  | OracleUnknown
  -- | Scripturile nu sunt pe lanț. Nimic nu se poate construi împotriva lor.
  | ScriptsMissing

derive instance Eq OracleGate

instance Show OracleGate where
  show = case _ of
    OracleOpen -> "OracleOpen"
    OraclePaused -> "OraclePaused"
    OracleUnknown -> "OracleUnknown"
    ScriptsMissing -> "ScriptsMissing"

-- | Verdictul. Ordinea contează: fără scripturi pe lanț, starea oracolului e irelevantă.
oracleGate :: InteractionStatus -> OracleGate
oracleGate (InteractionStatus s)
  | not s.deployedScripts = ScriptsMissing
  | otherwise = case s.oraclePaused of
      Nothing -> OracleUnknown
      Just true -> OraclePaused
      Just false -> OracleOpen
