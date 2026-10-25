-- | Decodarea celor două ecrane M1b care nu depind de nicio altă pagină: lista de SPO-uri și
-- | comitetul.
-- |
-- | Cazul care contează pe lista de SPO-uri nu e un rând plin, ci unul în care DOUĂ coloane sînt
-- | goale — pentru că așa sînt toate cele 511 de pe preprod. Dacă cineva întoarce `.:?` în `.:`
-- | pentru `ticker` sau `participation_rate`, ecranul nu se mai randează deloc, iar asta se vede
-- | aici și nu pe deploy.
module Test.Capabilities.SpoCommitteeSpec (spec) where

import Prelude

import Capabilities.Query.Gov.Fixtures
  ( activityFixture
  , attestationListFixture
  , disputeListFixture
  , profileListFixture
  , committeeFixture
  , delegationListFixture
  , spoListFixture
  , withdrawalListFixture
  )
import Capabilities.Query.Gov.Http (ApiError)
import Capabilities.Query.Gov.Mock (decodeFixture)
import Capabilities.Query.Gov.Types
  ( ChainPoint(..)
  , CommitteeMember(..)
  , CommitteeState(..)
  , DelegationPage(..)
  , DelegationRow(..)
  , ActivityEvent(..)
  , ActivityPage(..)
  , AttestationPage(..)
  , AttestationRow(..)
  , DisputePage(..)
  , DisputeRow(..)
  , ProfilePage(..)
  , ProfileRow(..)
  , SpoPage(..)
  , SpoRow(..)
  , WithdrawalPage(..)
  , WithdrawalRow(..)
  )
import Components.Explorer.DelegationList (isStandingChoice, standingLabel)
import Components.Explorer.Graph (buildGraph)
import Route as R
import Route.Codec (parseRoute, printRoute)
import Data.Array (any, filter)
import Data.Array (head, length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isJust, isNothing)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = do
  describe "SpoPage decoding" do
    it "decodes the measured payload, empty columns and all" do
      case (decodeFixture spoListFixture :: Either ApiError SpoPage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (SpoPage p) -> do
          p.total `shouldEqual` 511
          length p.items `shouldEqual` 5
          case head p.items of
            Nothing -> fail "expected a pool"
            Just (SpoRow r) -> do
              r.votingPower `shouldEqual` 488729208474515.0
              r.votingPowerEpoch `shouldEqual` 321
              r.delegatorCount `shouldEqual` 5
              r.votesCast `shouldEqual` 8
              -- Cele două care sînt goale pe toată rețeaua. Vezi antetul modulului.
              isNothing r.ticker `shouldEqual` true
              isNothing r.participationRate `shouldEqual` true

  describe "CommitteeState decoding" do
    it "carries the quorum, which is the question the screen exists to answer" do
      case (decodeFixture committeeFixture :: Either ApiError CommitteeState) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (CommitteeState c) -> do
          c.quorumNumerator `shouldEqual` 2
          c.quorumDenominator `shouldEqual` 3
          c.epoch `shouldEqual` 321
          length c.members `shouldEqual` 3
          case head c.members of
            Nothing -> fail "expected a member"
            Just (CommitteeMember m) -> do
              m.expirationEpoch `shouldEqual` 372
              m.status `shouldEqual` "active"
              m.votesCast `shouldEqual` 6
              -- Autorizat și nedemisionat: cazul obișnuit, în care `resigned_at` lipsă e normalul.
              isNothing m.resignedAt `shouldEqual` true
              case m.authorizedAt of
                Nothing -> fail "expected an authorization point"
                Just (ChainPoint at) -> at.epoch `shouldEqual` 228

  describe "WithdrawalPage decoding" do
    it "decodes a network where nothing was ever paid out" do
      case (decodeFixture withdrawalListFixture :: Either ApiError WithdrawalPage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (WithdrawalPage p) -> do
          p.total `shouldEqual` 83
          -- Plicul trebuie să fie POSIBIL: o limită mai mare decât numărul de rânduri, cu un total
          -- peste amândouă, e un răspuns pe care serverul nu-l poate da — iar paginatorul ar
          -- deduce din el că paginile mai adânci sunt refuzate.
          p.limit `shouldEqual` length p.items
          -- Niciun rând adoptat: de-aia ecranul separă „cerut" de „plătit".
          any (\(WithdrawalRow w) -> w.enactedEpoch /= Nothing) p.items `shouldEqual` false

  describe "DelegationPage decoding" do
    it "keeps the two standing choices apart from real DReps" do
      case (decodeFixture delegationListFixture :: Either ApiError DelegationPage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (DelegationPage p) -> do
          p.limit `shouldEqual` length p.items
          -- Dacă prefixul `drep_` dispare din verificare, linia asta cade, și nu ecranul live:
          -- serverul scrie `drep_always_abstain`, nu `always_abstain`.
          any (\(DelegationRow d) -> isStandingChoice d.target) p.items `shouldEqual` true
          length (filter (\(DelegationRow d) -> d.lovelace == Nothing) p.items) `shouldEqual` 1

    it "names the standing choices in words" do
      standingLabel "drep_always_abstain" `shouldEqual` "always abstain"
      standingLabel "drep_always_no_confidence" `shouldEqual` "always no confidence"
      -- Un identificator necunoscut se scrie așa cum e, nu se înlocuiește cu o ghicire.
      standingLabel "drep1abc" `shouldEqual` "drep1abc"

  describe "ActivityPage decoding" do
    it "survives the four events that have no slot and no transaction" do
      case (decodeFixture activityFixture :: Either ApiError ActivityPage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (ActivityPage p) -> do
          length p.items `shouldEqual` 11
          -- Evenimentele de granita de epoca — o actiune care expira, una care se ratifica — n-au
          -- nici slot nici tranzactie, pentru ca nu le-a provocat nicio tranzactie. Un decodor
          -- care cerea un numar pentru `slot` rupea tot fluxul; s-a vazut pe ecran, nu in teste.
          length (filter (\(ActivityEvent e) -> noSlot e.at) p.items) `shouldEqual` 4
          length (filter (\(ActivityEvent e) -> e.actorId == Nothing) p.items) `shouldEqual` 4
          -- `total` nu exista pe ruta asta (`D-18`) si de-aia plicul nici nu-l are.
          isJust p.nextCursor `shouldEqual` true

  describe "the attestation registry decodes" do
    it "profiles, half of which claim no governance credential" do
      case (decodeFixture profileListFixture :: Either ApiError ProfilePage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (ProfilePage p) -> do
          p.total `shouldEqual` 12
          p.limit `shouldEqual` length p.items
          -- Un profil fara credential nu e incomplet: e un profil care nu pretinde o identitate pe
          -- lant. Daca `.:?` devine `.:`, jumatate din registru nu se mai randeaza.
          length (filter (\(ProfileRow r) -> r.credential == Nothing) p.items) `shouldEqual` 3

    it "attestations, where accepted and disputed are separate questions" do
      case (decodeFixture attestationListFixture :: Either ApiError AttestationPage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (AttestationPage p) -> do
          p.total `shouldEqual` 19
          p.limit `shouldEqual` length p.items
          -- Exista o atestare ACCEPTATA si totusi contestata cu verdict impotriva ei. Daca ecranul
          -- ar avea o singura „stare", cazul asta ar trebui mintit intr-un fel sau altul.
          any (\(AttestationRow a) -> a.accepted && a.upheldDisputeCount > 0) p.items `shouldEqual` true

    it "disputes, with the deposit that separates a challenge from an opinion" do
      case (decodeFixture disputeListFixture :: Either ApiError DisputePage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (DisputePage p) -> do
          p.total `shouldEqual` 5
          p.limit `shouldEqual` length p.items
          any (\(DisputeRow d) -> d.deposit > 0.0) p.items `shouldEqual` true

  describe "the new routes round-trip" do
    it "carries the chosen representative through the URL" do
      -- Un graf partajat trebuie sa se deschida la fel la celalalt capat, deci DRep-ul e in URL.
      parseRoute "/graph?drep=drep1abc" `shouldEqual` R.Graph { drep: Just "drep1abc" }
      parseRoute (printRoute (R.Graph { drep: Just "drep1abc" }))
        `shouldEqual` R.Graph { drep: Just "drep1abc" }
      parseRoute "/graph" `shouldEqual` R.Graph { drep: Nothing }

  describe "the delegation graph" do
    it "puts the representative in the middle, once" do
      case (decodeFixture delegationListFixture :: Either ApiError DelegationPage) of
        Left e -> fail ("fixture did not decode: " <> show e)
        Right (DelegationPage p) -> do
          let g = buildGraph "drep1root" p.items
          -- Radacina plus cite un nod per delegator. Daca radacina ar fi dedusa din rinduri in loc
          -- sa fie data, un DRep fara delegari n-ar avea centru si graful ar fi gol in loc de
          -- „niciun delegator".
          length g.nodes `shouldEqual` (length p.items + 1)
          length (filter (\n -> n.isRoot) g.nodes) `shouldEqual` 1
          length g.edges `shouldEqual` length p.items

    it "draws a representative with no delegators as a lone centre, not an empty canvas" do
      let g = buildGraph "drep1root" []
      length g.nodes `shouldEqual` 1
      length g.edges `shouldEqual` 0

  where
  noSlot (ChainPoint c) = c.slot == Nothing
