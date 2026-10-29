-- | Partea pură a scrierii: poarta de wallet, cîmpurile obligatorii, și corpurile trimise.
-- |
-- | Aici cade cel mai scump fel de greșeală din tot produsul. Un ecran de citire gresit arată un
-- | număr fals; un corp de scriere greșit produce o tranzacție pe care OMUL O SEMNEAZĂ. De-aia
-- | decizia „ce intră în cerere" e pură și testată, separat de locul unde se desenează butoane.
module Test.Capabilities.WriteSpec (spec) where

import Prelude

import AppEnv (NetworkMagic(..), mainnetMagic, preprodMagic, previewMagic)
import Capabilities.Interaction.Types (FlowRequest(..), InteractionStatus(..), OracleGate(..), OracleParams(..), encodeFlow, flowPath, oracleGate)
import Capabilities.Wallet.Governance (BlockReason(..), WalletCapabilities, blockMessage, impliedMagic, verdictOf)
import Components.Write.Flows (buildRequest, flowSpecs, missingFields, specFor)
import Components.Write.TxSummary (summariseJson)
import Data.Argonaut.Core (stringify)
import Data.Array (head, length, nub)
import Data.Map as Map
import Data.Tuple.Nested ((/\))
import Data.Maybe (Maybe(..), isJust, isNothing)
import Data.String as String
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

addresses :: { usedAddresses :: Array String, changeAddress :: String }
addresses = { usedAddresses: [ "addr_test1qq" ], changeAddress: "addr_test1qq" }

baseCaps :: WalletCapabilities
baseCaps =
  { walletName: "lace"
  , advertised: [ { cip: 95 }, { cip: 142 } ]
  , negotiated: [ { cip: 95 }, { cip: 142 } ]
  , cip95Present: true
  , cip142Present: true
  , networkMagic: Just preprodMagic
  , networkId: Just 0
  }

spec :: Spec Unit
spec = do
  describe "the wallet gate" do
    it "lets a wallet through only when it can prove the network AND the keys" do
      verdictOf baseCaps preprodMagic `shouldEqual` Nothing

    it "refuses when the network cannot be determined, rather than assuming preprod" do
      -- Asta e refuzul care conteaza cel mai mult. CIP-30 raporteaza 0 pentru preprod, preview SI
      -- un devnet local, deci „probabil preprod" ar fi un pariu facut cu cheia altcuiva.
      verdictOf (baseCaps { cip142Present = false, networkMagic = Nothing }) preprodMagic
        `shouldEqual` Just NetworkUndetermined
      -- Si nici cind extensia exista dar apelul n-a raspuns:
      verdictOf (baseCaps { networkMagic = Nothing }) preprodMagic
        `shouldEqual` Just NetworkUndetermined

    it "refuses a wallet on another network, naming both" do
      verdictOf (baseCaps { networkMagic = Just previewMagic }) preprodMagic
        `shouldEqual` Just (WrongNetwork preprodMagic previewMagic)

    it "checks the network BEFORE the governance keys" do
      -- Ordinea nu e cosmetica: un wallet pe reteaua gresita si fara CIP-95 trebuie sa afle intii
      -- despre retea, fiindca aia e cauza care face restul irelevant.
      verdictOf (baseCaps { cip95Present = false, networkMagic = Just previewMagic }) preprodMagic
        `shouldEqual` Just (WrongNetwork preprodMagic previewMagic)

    it "refuses a wallet without governance keys, once the network is settled" do
      verdictOf (baseCaps { cip95Present = false }) preprodMagic `shouldEqual` Just NoGovernanceKeys

  describe "R6, second path: a wallet whose identity implies one testnet" do
    -- Nu e o slabire a regulii. Prima versiune cerea CIP-142 si numai CIP-142, iar intersectia
    -- dintre wallet-urile care implementeaza CIP-142 si cele care semneaza pe `required_signers` e
    -- GOALA — deci revendicarea de credentiala ar fi fost imposibila prin constructie. Un wallet
    -- care nu POATE fi pe preview nu lasa loc ambiguitatii pe care CIP-142 o rezolva.
    it "passes a single-testnet wallet on networkId 0, without CIP-142" do
      verdictOf
        (baseCaps { walletName = "yoroi", cip142Present = false, networkMagic = Nothing, networkId = Just 0 })
        preprodMagic
        `shouldEqual` Nothing

    it "still refuses an unknown wallet on networkId 0" do
      -- „Testnet" nu spune CARE testnet, iar presupunerea e exact ce interzice regula.
      verdictOf
        (baseCaps { walletName = "somewallet", cip142Present = false, networkMagic = Nothing, networkId = Just 0 })
        preprodMagic
        `shouldEqual` Just NetworkUndetermined

    it "refuses a wallet reporting mainnet to a preprod deployment, and says which network" do
      -- Era `NetworkUndetermined`, fiindcă `impliedMagic` nu avea ramură pentru mainnet. Refuzul e
      -- același, dar motivul e acum cel exact: mainnet E determinat — e unul singur — deci greșeala
      -- nu e „nu știm pe ce rețea ești", e „ești pe alta decît deployul". Omul are ce face cu a doua.
      verdictOf
        (baseCaps { walletName = "yoroi", cip142Present = false, networkMagic = Nothing, networkId = Just 1 })
        preprodMagic
        `shouldEqual` Just (WrongNetwork preprodMagic mainnetMagic)

    it "opens the gate for ANY wallet on mainnet, because mainnet is one network" do
      -- Garanția lui R6 e că nu se ghicește. Pe mainnet nu e nimic de ghicit, deci lista de
      -- testnet-uri nu are ce căuta în drum: fără asta, un deploy de mainnet refuza orice wallet și
      -- toate cele nouă fluxuri erau moarte pentru toată lumea.
      impliedMagic "somewallet" (Just 1) `shouldEqual` Just mainnetMagic
      impliedMagic "lace" (Just 1) `shouldEqual` Just mainnetMagic
      verdictOf
        (baseCaps { walletName = "lace", cip142Present = false, networkMagic = Nothing, networkId = Just 1 })
        mainnetMagic
        `shouldEqual` Nothing

    it "prefers a confirmed magic over an implied one" do
      -- Masuratoarea bate deductia: daca CIP-142 spune mainnet, un nume de wallet nu schimba asta.
      verdictOf
        (baseCaps { walletName = "yoroi", networkMagic = Just (NetworkMagic 764824073) })
        preprodMagic
        `shouldEqual` Just (WrongNetwork preprodMagic (NetworkMagic 764824073))

    it "matches the wallet name case-insensitively" do
      -- `window.cardano` scrie cheile cum vrea fiecare extensie.
      impliedMagic "Yoroi" (Just 0) `shouldEqual` Just preprodMagic
      impliedMagic "yoroi" (Just 0) `shouldEqual` Just preprodMagic
      impliedMagic "yoroi" Nothing `shouldEqual` Nothing

    it "says what is missing and what will not work, not just 'incompatible'" do
      -- Un mesaj pe care nimeni nu-l poate actiona e acelasi lucru cu niciun mesaj.
      let m = blockMessage NetworkUndetermined
      String.contains (String.Pattern "CIP-142") m `shouldEqual` true
      String.contains (String.Pattern "nine actions will be built") m `shouldEqual` true
      -- Și mesajul pentru CIP-95 lipsă trebuie să spună că se blochează TOT, nu doar credențialele:
      -- varianta de dinainte zicea „Reading works; claiming a credential does not", deși poarta e
      -- aceeași pentru toate cele nouă fluxuri.
      String.contains (String.Pattern "nine actions") (blockMessage NoGovernanceKeys) `shouldEqual` true
      String.contains (String.Pattern "preprod") (blockMessage (WrongNetwork preprodMagic (NetworkMagic 2)))
        `shouldEqual` false

  describe "the nine flows" do
    it "are nine, with distinct ids and distinct server paths" do
      length flowSpecs `shouldEqual` 9
      length (nub (map _.id flowSpecs)) `shouldEqual` 9

    it "each declares what it writes and what it costs" do
      -- `consequence` e singura propozitie care conteaza dupa ce wallet-ul cere semnatura, deci
      -- niciun flux n-are voie sa n-o aiba.
      let bad = Map.fromFoldable (map (\s -> s.id /\ s.consequence) flowSpecs)
      Map.size (Map.filter (\c -> String.trim c == "") bad) `shouldEqual` 0

    it "refuses to build while a required field is empty" do
      case specFor "claim-profile" of
        Nothing -> fail "claim-profile is missing"
        Just s -> do
          length (missingFields s Map.empty) `shouldEqual` 4
          isNothing (buildRequest "claim-profile" Map.empty addresses) `shouldEqual` true

    it "treats a field of spaces as empty, because the server would not" do
      let vals = Map.fromFoldable [ "kind" /\ "organization", "name" /\ "   ", "description" /\ "d", "image_uri" /\ "u" ]
      isNothing (buildRequest "claim-profile" vals addresses) `shouldEqual` true

    it "builds when every required field is there" do
      let vals = Map.fromFoldable [ "kind" /\ "organization", "name" /\ "n", "description" /\ "d", "image_uri" /\ "u" ]
      isJust (buildRequest "claim-profile" vals addresses) `shouldEqual` true

  describe "the request bodies" do
    it "are snake_case outside and camelCase inside user_addresses" do
      -- Masurat din swagger-ul lui interaction-api. Un singur modificator global de nume ar rupe
      -- exact jumatate din fiecare cerere, iar serverul ar raspunde cu o eroare de validare care
      -- arata ca „datele tale sint gresite".
      let
        body = stringify (encodeFlow (AcceptAttestation { attestationId: "pol.name", addresses }))
      String.contains (String.Pattern "\"attestation_id\"") body `shouldEqual` true
      String.contains (String.Pattern "\"user_addresses\"") body `shouldEqual` true
      String.contains (String.Pattern "\"usedAddresses\"") body `shouldEqual` true
      String.contains (String.Pattern "\"changeAddress\"") body `shouldEqual` true
      String.contains (String.Pattern "\"used_addresses\"") body `shouldEqual` false

    it "omits an empty description on update, instead of sending null" do
      -- Serverul inlocuieste intreaga inregistrare de metadate: un `null` trimis ar STERGE
      -- descrierea, iar formularul spune „lasa gol ca sa pastrezi".
      let
        without = stringify
          (encodeFlow (UpdateProfile { profileId: "p", description: Nothing, imageUri: "u", addresses }))
        with = stringify
          (encodeFlow (UpdateProfile { profileId: "p", description: Just "d", imageUri: "u", addresses }))
      String.contains (String.Pattern "description") without `shouldEqual` false
      String.contains (String.Pattern "\"description\":\"d\"") with `shouldEqual` true

    it "always sends other_metadata on an attestation, even empty" do
      -- E in `required` al serverului. Omis, cererea e respinsa la validare.
      let
        body = stringify
          ( encodeFlow
              ( IssueAttestation
                  { subjectProfileId: "s"
                  , issuerProfileId: "i"
                  , kind: "endorsement"
                  , name: "n"
                  , description: "d"
                  , imageUri: "u"
                  , addresses
                  }
              )
          )
      String.contains (String.Pattern "\"other_metadata\":[]") body `shouldEqual` true

    it "routes each flow to its own path" do
      flowPath (AcceptAttestation { attestationId: "a", addresses }) `shouldEqual` "/accept-attestation"
      flowPath (ExpireDispute { disputeId: "d", addresses }) `shouldEqual` "/expire-dispute"

  describe "the oracle gate" do
    it "opens only when the scripts are on chain AND the oracle says it is not paused" do
      oracleGate (InteractionStatus (baseStatus { deployedScripts = true, oraclePaused = Just false })) `shouldEqual` OracleOpen

    it "blocks on an unknown pause state exactly as hard as on a known pause" do
      -- Acelasi refuz ca la reteaua nedeterminata, din acelasi motiv: o tranzactie construita
      -- impotriva unui protocol oprit e respinsa de validator DUPA ce omul a semnat-o.
      oracleGate (InteractionStatus (baseStatus { oraclePaused = Nothing })) `shouldEqual` OracleUnknown
      oracleGate (InteractionStatus (baseStatus { oraclePaused = Just true })) `shouldEqual` OraclePaused

    it "reports missing scripts before anything about the oracle" do
      -- Fara scripturi pe lant, starea oracolului e irelevanta — si un mesaj despre oracol ar
      -- trimite omul sa astepte ceva ce nu se va intimpla.
      oracleGate (InteractionStatus (baseStatus { deployedScripts = false, oraclePaused = Just false }))
        `shouldEqual` ScriptsMissing
      oracleGate (InteractionStatus (baseStatus { deployedScripts = false, oraclePaused = Nothing }))
        `shouldEqual` ScriptsMissing

  describe "R8: the signing summary is read out of the transaction" do
    -- Forma JSON-ului e luata din `cardano_serialization_lib.d.ts` al versiunii pinate (11.5.0),
    -- nu ghicita: `TransactionBodyJSON.fee` e string, `mint` e o LISTA de perechi
    -- `[policy, {assetName: quantity}]`, iar `amount.coin` e string si el. Toate sint string-uri
    -- fiindca sint numere de 64 de biti.
    it "reads the fee, the mint and the outputs out of CSL's body JSON" do
      case summariseJson bodyJson of
        Nothing -> fail "the body JSON did not decode"
        Just s -> do
          s.fee `shouldEqual` 182133.0
          length s.mints `shouldEqual` 1
          length s.outputs `shouldEqual` 2
          s.requiredSigners `shouldEqual` 1
          s.certificates `shouldEqual` 0
          case head s.mints of
            Nothing -> fail "expected a mint"
            Just m -> do
              m.quantity `shouldEqual` "1"
              m.assetName `shouldEqual` "000643b0abc"

    it "keeps 64-bit amounts intact" do
      -- 505 bilioane de lovelace nu incap intr-un Int de 32 de biti. Daca cineva schimba citirea
      -- din `Number` in `Int`, linia asta cade — si nu ecranul live, la a doua tranzactie mare.
      case summariseJson bodyJson of
        Nothing -> fail "the body JSON did not decode"
        Just s -> case head s.outputs of
          Nothing -> fail "expected an output"
          Just o -> o.lovelace `shouldEqual` 505754377083269.0

    it "counts the other tokens in an output without naming them" do
      case summariseJson bodyJson of
        Nothing -> fail "the body JSON did not decode"
        Just s -> map _.otherAssets s.outputs `shouldEqual` [ 0, 1 ]

    it "refuses a body it cannot read, instead of guessing zero" do
      -- Un sumar cu „fee 0" pe o tranzactie necitita ar fi exact minciuna pe care R8 o interzice.
      isNothing (summariseJson "{\"outputs\":[]}") `shouldEqual` true
      isNothing (summariseJson "not json") `shouldEqual` true

-- | Un `/status` de pornire, peste care testele schimbă doar cîmpul care contează.
baseStatus :: { provider :: String, network :: String, deployedScripts :: Boolean, oraclePaused :: Maybe Boolean, oracle :: Maybe OracleParams }
baseStatus =
  { provider: "node-kupo"
  , network: "preprod"
  , deployedScripts: true
  , oraclePaused: Just false
  , oracle: Nothing
  }

bodyJson :: String
bodyJson =
  """
{ "inputs": [ { "transaction_id": "aa", "index": 0 } ]
, "outputs":
    [ { "address": "addr_test1qqrecipient", "amount": { "coin": "505754377083269" } }
    , { "address": "addr_test1qqchange"
      , "amount":
          { "coin": "1500000"
          , "multiasset": { "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3": { "000643b0abc": "1" } }
          }
      }
    ]
, "fee": "182133"
, "mint": [ [ "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3", { "000643b0abc": "1" } ] ]
, "required_signers": [ "5a0ea8b28def0497f0954af950abf61097da9fed0079811605bb70b8" ]
}
"""
