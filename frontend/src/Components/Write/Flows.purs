-- | Descrierea celor nouă fluxuri de scriere: ce cîmpuri are fiecare, și cum devin o cerere.
-- |
-- | Partea asta e PURĂ și testată. Un formular care construiește greșit corpul produce o
-- | tranzacție greșită pe care omul o semnează — deci locul unde se decide ce intră în cerere nu
-- | are voie să fie încurcat cu locul unde se desenează butoane.
-- |
-- | Descriptorii NU sînt un formular generic de dragul generalității: cele nouă fluxuri au aceeași
-- | mecanică (construiește → semnează → trimite → așteaptă) și diferă doar prin cîmpuri, iar nouă
-- | copii ale aceluiași ecran ar fi însemnat nouă locuri în care se repară aceeași greșeală.
module Components.Write.Flows
  ( FieldKind(..)
  , FieldSpec
  , FlowSpec
  , flowSpecs
  , specFor
  , buildRequest
  , missingFields
  ) where

import Prelude

import Capabilities.Interaction.Types (FlowRequest(..), UserAddresses, attestationKinds, disputeVerdicts, profileKinds)
import Data.Array (filter, find, null)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String

data FieldKind
  = Text
  | LongText
  | Select (Array String)

derive instance Eq FieldKind

type FieldSpec =
  { key :: String
  , label :: String
  , hint :: String
  , kind :: FieldKind
  , required :: Boolean
  }

type FlowSpec =
  { id :: String
  , title :: String
  -- Ce face fluxul, în cuvintele cuiva care nu a citit protocolul. Apare DEASUPRA formularului,
  -- nu într-un tooltip: e ultimul loc în care cineva poate să-și dea seama că e pe ecranul greșit.
  , summary :: String
  -- Ce se întîmplă ireversibil dacă apeși. Scris separat de `summary` fiindcă e singura propoziție
  -- care contează după ce wallet-ul cere semnătura.
  , consequence :: String
  , fields :: Array FieldSpec
  }

txt :: String -> String -> String -> FieldSpec
txt key label hint = { key, label, hint, kind: Text, required: true }

long :: String -> String -> String -> FieldSpec
long key label hint = { key, label, hint, kind: LongText, required: true }

sel :: String -> String -> String -> Array String -> FieldSpec
sel key label hint opts = { key, label, hint, kind: Select opts, required: true }

optional :: FieldSpec -> FieldSpec
optional f = f { required = false }

-- | Cele nouă fluxuri, în ordinea în care un om le întîlnește: întîi ai un profil, apoi atestări
-- | despre el, apoi dispute despre atestări, apoi credențiale legate de profil.
flowSpecs :: Array FlowSpec
flowSpecs =
  [ { id: "claim-profile"
    , title: "Claim a profile"
    , summary:
        "Mints a profile token. Whoever holds the token holds the profile, and the name can never \
        \be changed afterwards."
    , consequence: "Mints a new token to your wallet and writes the profile on chain."
    , fields:
        [ sel "kind" "Kind" "What this profile represents." profileKinds
        , txt "name" "Name" "Immutable once minted. Everything else can be edited later."
        , long "description" "Description" "What this profile is."
        , txt "image_uri" "Image URI" "You host the image; the protocol only stores the link."
        ]
    }
  , { id: "update-profile"
    , title: "Edit a profile"
    , summary: "Changes a profile's description and image. The name is immutable and is not asked for."
    , consequence: "Replaces the profile's metadata on chain. The old values stop being current."
    , fields:
        [ txt "profile_id" "Profile" "The profile's asset class — policy.assetName."
        , txt "image_uri" "Image URI" "Required: the server replaces the whole metadata record."
        , optional (long "description" "Description" "Leave empty to keep the current one.")
        ]
    }
  , { id: "issue-attestation"
    , title: "Issue an attestation"
    , summary:
        "States something about someone else's profile. It is not binding on them until they accept \
        \it, and anyone can dispute it."
    , consequence: "Writes a pending attestation on chain, signed by you, naming the subject."
    , fields:
        [ txt "subject_profile_id" "Subject" "The profile this is about."
        , txt "issuer_profile_id" "Issuer" "Your profile — the one making the claim."
        , sel "kind" "Kind" "What sort of claim this is." attestationKinds
        , txt "name" "Name" "A short title for the attestation."
        , long "description" "Description" "What exactly is being attested."
        , txt "image_uri" "Image URI" "You host the image; the protocol only stores the link."
        ]
    }
  , { id: "accept-attestation"
    , title: "Accept an attestation"
    , summary: "Countersigns an attestation about your own profile. Only the subject can do this."
    , consequence: "Marks the attestation as accepted on chain. It cannot be un-accepted."
    , fields: [ txt "attestation_id" "Attestation" "The attestation's asset class." ]
    }
  , { id: "open-dispute"
    , title: "Open a dispute"
    , summary:
        "Contests an attestation and locks a deposit. The deposit is what separates a challenge \
        \from an opinion, and you lose it if the dispute is dismissed."
    , consequence: "Locks the oracle's current deposit from your wallet until the dispute resolves."
    , fields:
        [ txt "attestation_id" "Attestation" "The attestation being contested."
        , txt "opened_by_profile_id" "Your profile" "The profile opening the dispute."
        , txt "name" "Name" "A short title for the dispute."
        , long "description" "Description" "What is being contested, and why."
        , txt "image_uri" "Image URI" "You host the image; the protocol only stores the link."
        ]
    }
  , { id: "resolve-dispute"
    , title: "Resolve a dispute"
    , summary: "Records the verdict on a dispute. Only the oracle's authority can do this."
    , consequence: "Settles the dispute and releases or forfeits the deposit accordingly."
    , fields:
        [ txt "dispute_id" "Dispute" "The dispute's asset class."
        , sel "verdict" "Verdict" "Upheld means the attestation falls." disputeVerdicts
        ]
    }
  , { id: "expire-dispute"
    , title: "Expire a dispute"
    , summary:
        "Closes a dispute that was never decided, after its stale-after moment. Anyone can do this \
        \— that is the point of a deadline."
    , consequence: "Closes the dispute as stale and returns the deposit."
    , fields: [ txt "dispute_id" "Dispute" "The dispute's asset class." ]
    }
  , { id: "claim-credential"
    , title: "Claim a governance credential"
    , summary:
        "Binds an on-chain governance identity — a DRep or a committee key — to your profile. This \
        \is the flow that needs CIP-95: the wallet has to prove the credential is yours."
    , consequence: "Writes a credential claim on chain, linking the profile to the credential."
    , fields:
        [ txt "profile_id" "Profile" "The profile making the claim."
        , txt "credential" "Credential" "CIP-129 identifier: drep1…, cc_cold1… or cc_hot1…."
        , txt "name" "Name" "A short title for the claim."
        , long "description" "Description" "What this claim asserts."
        , txt "image_uri" "Image URI" "You host the image; the protocol only stores the link."
        ]
    }
  , { id: "withdraw-credential"
    , title: "Withdraw a governance credential"
    , summary: "Undoes a credential claim. The claim stays in history; it stops being current."
    , consequence: "Writes a withdrawal on chain. The earlier claim remains visible and dated."
    , fields:
        [ txt "profile_id" "Profile" "The profile withdrawing the claim."
        , txt "credential" "Credential" "The CIP-129 identifier being withdrawn."
        , txt "name" "Name" "A short title for the withdrawal."
        , long "description" "Description" "Why it is being withdrawn."
        , txt "image_uri" "Image URI" "You host the image; the protocol only stores the link."
        ]
    }
  ]

specFor :: String -> Maybe FlowSpec
specFor flowId = find (\s -> s.id == flowId) flowSpecs

-- | Cîmpurile obligatorii care lipsesc. Gol înseamnă „se poate construi".
-- |
-- | Un cîmp cu spații e gol: serverul ar accepta un nume din trei spații, iar omul n-ar vedea
-- | niciodată că l-a trimis.
missingFields :: FlowSpec -> Map String String -> Array FieldSpec
missingFields spec values =
  filter (\f -> f.required && String.trim (fromMaybe "" (Map.lookup f.key values)) == "") spec.fields

-- | Din valorile formularului, cererea. `Nothing` cînd lipsește ceva obligatoriu sau cînd fluxul
-- | nu există — ambele sunt stări pe care ecranul le poate explica, nu excepții.
buildRequest :: String -> Map String String -> UserAddresses -> Maybe FlowRequest
buildRequest flowId values addresses = do
  spec <- specFor flowId
  if not (null (missingFields spec values)) then Nothing
  else case flowId of
    "claim-profile" -> Just
      ( ClaimProfile
          { kind: get "kind", name: get "name", description: get "description", imageUri: get "image_uri", addresses }
      )
    "update-profile" -> Just
      ( UpdateProfile
          { profileId: get "profile_id"
          , description: opt "description"
          , imageUri: get "image_uri"
          , addresses
          }
      )
    "issue-attestation" -> Just
      ( IssueAttestation
          { subjectProfileId: get "subject_profile_id"
          , issuerProfileId: get "issuer_profile_id"
          , kind: get "kind"
          , name: get "name"
          , description: get "description"
          , imageUri: get "image_uri"
          , addresses
          }
      )
    "accept-attestation" -> Just (AcceptAttestation { attestationId: get "attestation_id", addresses })
    "open-dispute" -> Just
      ( OpenDispute
          { attestationId: get "attestation_id"
          , openedByProfileId: get "opened_by_profile_id"
          , name: get "name"
          , description: get "description"
          , imageUri: get "image_uri"
          , addresses
          }
      )
    "resolve-dispute" -> Just (ResolveDispute { disputeId: get "dispute_id", verdict: get "verdict", addresses })
    "expire-dispute" -> Just (ExpireDispute { disputeId: get "dispute_id", addresses })
    "claim-credential" -> Just
      ( ClaimCredential
          { profileId: get "profile_id"
          , credential: get "credential"
          , name: get "name"
          , description: get "description"
          , imageUri: get "image_uri"
          , addresses
          }
      )
    "withdraw-credential" -> Just
      ( WithdrawCredential
          { profileId: get "profile_id"
          , credential: get "credential"
          , name: get "name"
          , description: get "description"
          , imageUri: get "image_uri"
          , addresses
          }
      )
    _ -> Nothing
  where
  get k = String.trim (fromMaybe "" (Map.lookup k values))

  opt k =
    let
      v = get k
    in
      if v == "" then Nothing else Just v
