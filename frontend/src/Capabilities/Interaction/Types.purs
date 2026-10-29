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
  , explainRefusal
  , traceCodeMeaning
  , attestationKinds
  , disputeVerdicts
  , OracleParams(..)
  , InteractionStatus(..)
  , oracleGate
  , OracleGate(..)
  , confirmPollMax
  , confirmPollDelayMs
  ) where

import Prelude

import Data.Argonaut.Core (Json, jsonEmptyObject)
import Data.Argonaut.Decode (class DecodeJson, decodeJson, (.:), (.:?))
import Data.Argonaut.Encode ((:=), (~>))
import Data.Array (filter, mapMaybe, null)
import Data.Maybe (Maybe(..))
import Data.String as String
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
  IssueAttestation _ -> "Issue vouch"
  AcceptAttestation _ -> "Accept vouch"
  OpenDispute _ -> "Open challenge"
  ResolveDispute _ -> "Resolve challenge"
  ExpireDispute _ -> "Expire challenge"
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

-- | Cele două verdicte pe care le poate alege un om, scrise ca pe sârmă — enumul serverului e
-- | `upheld | rejected | expired`, iar opțiunea aleasă AICI e valoarea trimisă, deci un cuvânt
-- | inventat nu dă o etichetă urâtă, dă o cerere respinsă.
-- |
-- | `expired` lipsește DELIBERAT: nu e decizia nimănui, e ce scrie `expire-dispute` când trece
-- | termenul. A-l „completa" aici ar oferi ca alegere o închidere pe care fluxul ăsta nu o face.
disputeVerdicts :: Array String
disputeVerdicts = [ "upheld", "rejected" ]

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
-- | trebuie să-l vadă ÎNAINTE să deschidă o dispută — e ce i se blochează. NU e ce riscă: validatorul
-- | cere plata depozitului la închidere pe orice verdict, deci nu există verdict care îl confiscă.
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

-- | Ce a refuzat lanțul, spus în cuvinte.
-- |
-- | Serverul întoarce `ScriptRefused` cu un mesaj care numește codurile de trace emise de validator
-- | și trimite la `docs/architecture/onchain-flows.md` — un document din depozit, pe care serviciul
-- | NU îl servește. Deci omul primea, după ce completase formularul și ceruse semnătura, un cod de
-- | două litere și o cale moartă. Asta e cel mai prost moment posibil pentru un drum închis.
-- |
-- | Formatul mesajului e fixat în `TxBuilding/Exceptions.hs:387-389`; dacă se schimbă acolo, parsarea
-- | de aici întoarce `Nothing` și se afișează mesajul serverului ca înainte — degradează, nu minte.
explainRefusal :: { code :: String, message :: String } -> Maybe { codes :: Array String, meanings :: Array String }
explainRefusal r
  | r.code /= "ScriptRefused" = Nothing
  | otherwise =
      case String.stripPrefix (String.Pattern refusalPrefix) r.message of
        Nothing -> Nothing
        Just rest ->
          let
            codes = filter (_ /= "") (String.split (String.Pattern " ") (takeUpToDot rest))
          in
            if null codes then Nothing
            else Just { codes, meanings: mapMaybe traceCodeMeaning codes }
      where
      refusalPrefix = "A validator refused this transaction: "
      takeUpToDot t = case String.indexOf (String.Pattern ".") t of
        Nothing -> t
        Just i -> String.take i t

-- | Codurile pe care un om le poate CHIAR atinge, fiecare cu ce să facă în loc.
-- |
-- | **Lista nu e a mea.** E §4.2 din `docs/usecases/attestation-protocol.md`, „On-chain refusals a
-- | user can actually reach", care are deja o coloană „What the UI should say" per cod — și, mai
-- | important, analiza pe care un dicționar derivat din comentariile validatorului nu o are: CUM
-- | ajunge omul acolo. Prima variantă a acestui dicționar a fost derivată din validator și greșea
-- | cauza în două locuri: `Mq`/`Md6` nu înseamnă „a stat nesemnată prea mult", ci că portofelul a
-- | lărgit intervalul de validitate peste 14,4 ore; iar `D9` e un decalaj de ceas între client și
-- | lanț, nu un termen pe care omul l-ar putea grăbi.
-- |
-- | Același document cere exact traducerea asta, la `attestation-protocol.md:812`: „**never show
-- | this raw.** Map the first code or fall back to «The protocol refused this transaction
-- | (<codes>)»." Era o obligație scrisă și neîndeplinită.
-- |
-- | Deliberat parțial, și nu din lene. Din cele 54 de coduri ale protocolului, restul sunt fie
-- | invariante interne — cheltuirea sămânței pentru unicitate, blocarea la adresa validatorului —
-- | fie prinse înainte de lanț de verificările off-chain din §4.1, care întorc un cod propriu. Un
-- | mesaj pentru un cod care nu ajunge niciodată e cod mort; o propoziție care i-ar sugera omului ce
-- | să schimbe pentru o regulă internă e un sfat inventat. Pentru alea se arată codul, care e
-- | lucrul verificabil.
traceCodeMeaning :: String -> Maybe String
traceCodeMeaning = case _ of
  -- O pauză care a aterizat între construire și trimitere.
  "M0" -> Just pausedMsg
  "A7" -> Just pausedMsg
  "D7" -> Just pausedMsg
  "P6" -> Just pausedMsg

  -- Cine ești și despre cine vorbești.
  "Mr" -> Just "A profile cannot vouch for itself. The subject and the issuer are the same profile here."
  "Mg" -> Just "A vouch can only be about a profile — not about another vouch, a challenge, or a user token."

  -- Credențiale.
  "Mc2" -> Just "Use the credential-binding flow rather than the vouch form: a credential record has to name the credential it binds."
  "Mc3" -> Just "The credential's own signature — or, for a script credential, its proving input — is missing from this transaction."

  -- Depozitul, la deschiderea unei provocări.
  "Md8" -> Just "Use a funded address for the refund, or leave the field empty and let us choose one: the refund address has to put an input into this transaction."
  "Mda" -> Just "The refund address has to be an ordinary wallet address. A script address cannot receive the deposit back."

  -- Timp.
  "Mq" -> Just widenedWindowMsg
  "Md6" -> Just widenedWindowMsg
  "D9" -> Just "Not yet — the chain does not agree the deadline has passed. Try again shortly; this is usually a clock difference between your browser and the chain."

  -- Curse: altcineva, sau alt tab, a ajuns primul.
  "A3" -> Just "Already countersigned. Acceptance happens once and cannot be repeated."
  "D3" -> Just "Already decided. A verdict is written once."
  "D1" -> Just "Only the arbiter can sign a verdict, and this transaction was signed by another key."

  _ -> Nothing
  where
  pausedMsg = "The registry was paused while you were signing. Nothing can be written until whoever holds that authority resumes it."
  widenedWindowMsg =
    "Your wallet widened the transaction's validity window past what the protocol accepts. Build it \
    \again, or try a different wallet."

-- | Cît timp se așteaptă confirmarea, și cu ce ritm.
-- |
-- | Programul nu e uniform pentru că nici așteptarea nu e: primele secunde după trimitere nu pot
-- | aduce nimic — tranzacția abia se propagă — deci o interogare pe secundă acolo e trafic pur. Pe
-- | preprod un bloc vine la ~20s, iar confirmarea se vede de obicei în primul minut, deci acolo se
-- | întreabă des. După două minute, dacă încă nu s-a văzut, probabil nu e o chestiune de răbdare.
-- |
-- |   * interogările 0–5:   10s fiecare (primul minut);
-- |   * interogările 6–17:   5s fiecare (minutul în care se vede de obicei);
-- |   * interogările 18–23: 10s fiecare (ultimul minut).
-- |
-- | În total 24 de interogări, ~3 minute. Pe urmă se spune că n-a fost văzută, NU că a eșuat —
-- | tranzacția e trimisă, iar singurul lucru care s-a terminat e răbdarea noastră.
confirmPollMax :: Int
confirmPollMax = 24

confirmPollDelayMs :: Int -> Number
confirmPollDelayMs n
  | n < 6 = 10_000.0
  | n < 18 = 5_000.0
  | otherwise = 10_000.0
