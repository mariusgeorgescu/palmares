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
  , WriteGate(..)
  , writeGate
  ) where

import Prelude

import Capabilities.Interaction.Types (FlowRequest(..), OracleGate(..), UserAddresses, attestationKinds, disputeVerdicts, profileKinds)
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
        [ txt "profile_id" "Profile" "Paste the profile's identifier — the long string shown under its title on the Profiles page."
        , txt "image_uri" "Image URI" "Required: the server replaces the whole metadata record."
        , optional (long "description" "Description" "Leave empty to keep the current one.")
        ]
    }
  , { id: "issue-attestation"
    , title: "Issue a vouch"
    , summary:
        "States something about someone else's profile. It is not binding on them until they accept \
        \it, and anyone can challenge it."
    , consequence: "Writes a pending vouch on chain, signed by you, naming the subject."
    , fields:
        [ txt "subject_profile_id" "Subject" "The profile you are making a claim about — paste its identifier."
        , txt "issuer_profile_id" "Issuer" "Your own profile's identifier. You must hold its token to sign this."
        , sel "kind" "Kind" "What sort of claim this is." attestationKinds
        , txt "name" "Name" "A short title for the vouch."
        , long "description" "Description" "What exactly is being vouched for."
        , txt "image_uri" "Image URI" "You host the image; the protocol only stores the link."
        ]
    }
  , { id: "accept-attestation"
    , title: "Accept a vouch"
    , summary: "Countersigns a vouch about your own profile. Only the subject can do this."
    , consequence: "Marks the vouch as accepted on chain. It cannot be un-accepted."
    , fields: [ txt "attestation_id" "Vouch" "Paste the vouch's identifier. The Vouches page has an \"Accept\" link that fills this in for you." ]
    }
  , { id: "open-dispute"
    , title: "Open a challenge"
    , summary:
        "Contests a vouch and locks a deposit until the challenge closes. The deposit is what \
        \separates a challenge from an opinion — it comes back whatever the outcome, so contesting \
        \costs network fees and nothing else."
    , consequence: "Locks the oracle's current deposit from your wallet until the challenge resolves."
    , fields:
        [ txt "attestation_id" "Vouch" "The claim you are challenging. The Vouches page has a \"Challenge\" link that fills this in."
        , txt "opened_by_profile_id" "Your profile" "Your own profile's identifier. The deposit comes from your wallet."
        , txt "name" "Name" "A short title for the challenge."
        , long "description" "Description" "What is being contested, and why."
        , txt "image_uri" "Image URI" "You host the image; the protocol only stores the link."
        ]
    }
  , { id: "resolve-dispute"
    , title: "Resolve a challenge"
    , summary: "Records the verdict on a challenge. Only the oracle's authority can do this."
    , consequence: "Settles the challenge and returns the deposit to whoever opened it, whatever the verdict."
    , fields:
        [ txt "dispute_id" "Challenge" "Paste the challenge's identifier. The Challenges page has links that fill this in for you."
        , sel "verdict" "Verdict"
            "Upheld records that the vouch did not survive the objection; rejected records that it \
            \stands. Either way the deposit goes back to whoever opened the challenge."
            disputeVerdicts
        ]
    }
  , { id: "expire-dispute"
    , title: "Expire a challenge"
    , summary:
        "Closes a challenge that was never decided, after its stale-after moment. Anyone can do this \
        \— that is the point of a deadline."
    , consequence: "Closes the challenge as stale and returns the deposit."
    , fields: [ txt "dispute_id" "Challenge" "Paste the challenge's identifier. The Challenges page has links that fill this in for you." ]
    }
  , { id: "claim-credential"
    , title: "Claim a governance credential"
    , summary:
        "Binds an on-chain governance identity — a DRep or a committee key — to your profile. This \
        \is the flow that needs CIP-95: the wallet has to prove the credential is yours."
    , consequence: "Writes a credential claim on chain, linking the profile to the credential."
    , fields:
        [ txt "profile_id" "Profile" "The profile making the claim."
        , txt "credential" "Credential" "The governance identity you are claiming: a DRep id starting drep1…, or a committee key starting cc_cold1… or cc_hot1…."
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
        , txt "credential" "Credential" "The same governance identity you claimed before: drep1…, cc_cold1… or cc_hot1…."
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

-- | Ce arată ecranul de scriere: formularul, nota de wallet, sau nota de oracol.
data WriteGate
  = ShowForm
  | WalletNote
  | OracleNote OracleGate

derive instance Eq WriteGate

-- | `Show` e pentru mesajele de test, ca la `OracleGate`: „expected ShowForm but got
-- | (OracleNote OraclePaused)" spune ce s-a întîmplat fără să deschizi fișierul.
instance Show WriteGate where
  show = case _ of
    ShowForm -> "ShowForm"
    WalletNote -> "WalletNote"
    OracleNote g -> "OracleNote " <> show g

-- | Decizia porții, ca funcție pură, ca să poată fi fixată de un test.
-- |
-- | **`expire-dispute` e scutită de pauza oracolului, și asta nu e o slăbire.** Arma
-- | `ExpireDispute` din validator verifică doar `D3` (nu e deja rezolvată) și `D9` (termenul a
-- | trecut); `D7`, garda de pauză, stă numai pe arma de rezolvare
-- | (`DisputesValidator.hs:145`). E deliberat: expirarea e ieșirea permisionless, cea care nu
-- | trebuie să depindă de nimeni — iar cel care pauzează protocolul e exact operatorul. O poartă de
-- | UI care o închide o face inaccesibilă tocmai cînd e singurul lucru care mai poate închide o
-- | dispută.
-- |
-- | Wallet-ul rămâne obligatoriu pe toate: fără el nu există semnătură, deci nu există tranzacție.
writeGate :: OracleGate -> Boolean -> String -> WriteGate
writeGate og walletOk flowId = case og, walletOk of
  OracleOpen, true -> ShowForm
  OracleOpen, false -> WalletNote
  _, true | flowId == "expire-dispute" -> ShowForm
  -- Și aici ordinea e o afirmație: pentru expirare oracolul NU blochează, deci cu protocolul oprit
  -- și fără wallet motivul real e wallet-ul. Nota de oracol i-ar spune că nu se poate scrie nimic,
  -- exact cînd singurul lucru care se poate e ăsta.
  _, false | flowId == "expire-dispute" -> WalletNote
  g, _ -> OracleNote g
