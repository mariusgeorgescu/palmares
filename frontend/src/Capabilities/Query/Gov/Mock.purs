-- | Implementarea cu fixturi a lui `MonadQueryGov`. `DemoM` deleagă aici, iar `MainDemo` — bundle-ul
-- | implicit — o folosește, deci `npm run dev` și e2e-ul merg fără backend, fără wallet și fără lanț.
-- |
-- | Modulul e doar cablaj: payload-urile stau în `Fixtures`. Fiecare trece prin **același** drum de
-- | decodare ca răspunsul real — dacă decodorul și forma reală se despart, bundle-ul demo arată
-- | eroarea de decodare pe ecran în loc să ascundă divergența în spatele unui record construit de
-- | mână.
module Capabilities.Query.Gov.Mock
  ( getStatusMock
  , getDashboardMock
  , getDRepExplorerMock
  , getDRepDetailMock
  , getGovActionsMock
  , getGovActionDetailMock
  , getVotesMock
  , searchAllMock
  , getFormulasMock
  , getSposMock
  , getCommitteeMock
  , getWithdrawalsMock
  , getDelegationsMock
  , getActivityMock
  , getProfileMock
  , getProfileByUserTokenMock
  , getProfilesMock
  , getAttestationMock
  , getAttestationsMock
  , getDisputeMock
  , getDisputesMock
  , getRegistrySummaryMock
  , decodeFixture
  ) where

import Prelude

import Capabilities.Query.Gov.Fixtures
  ( dashboardFixture
  , drepDetailFixture
  , drepExplorerFixture
  , govActionDetailFixture
  , govActionListFixture
  , formulasFixture
  , searchFixture
  , statusFixture
  , votesListFixture
  , spoListFixture
  , committeeFixture
  , withdrawalListFixture
  , delegationListFixture
  , activityFixture
  , disputeDetailFixture
  , attestationDetailFixture
  , profileDetailFixture
  , profileListFixture
  , attestationListFixture
  , disputeListFixture
  )
import Capabilities.Query.Gov.Http (ApiError(..), classifyResponse)
import Capabilities.Query.Gov.Types
  ( DRepDetail
  , DRepExplorerPage
  , DashboardPage
  , GovActionDetail
  , GovActionPage
  , Formula
  , GovStatus
  , SearchResults
  , VotePage
  , SpoPage
  , CommitteeState
  , WithdrawalPage
  , DelegationPage
  , ActivityPage
  , ProfilePage(..)
  , ProfileRow(..)
  , AttestationDetail
  , AttestationPage(..)
  , AttestationRow(..)
  , DisputePage(..)
  , DisputeRow(..)
  , RegistrySummary
  )
import Data.Argonaut.Decode (class DecodeJson, decodeJson, printJsonDecodeError)
import Data.Array (any, drop, filter, find, length, null, take)
import Data.Array as Array
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Foldable (all)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Data.String as String
import Route.GovQueries
  ( ActivityFilters
  , DRepFilters
  , DelegationFilters
  , GovActionFilters
  , RegistryFilters
  , SpoFilters
  , VoteFilters
  , WithdrawalFilters
  )

-- | Decodează o fixtură exact cum s-ar decoda un 200 real.
decodeFixture :: forall a. DecodeJson a => String -> Either ApiError a
decodeFixture s = case classifyResponse 200 s of
  Left e -> Left e
  Right json -> lmap (Decode <<< printJsonDecodeError) (decodeJson json)

-- | De ce filtrează mocurile de registru, când celelalte își ignoră argumentul: suita de fixturi
-- | (`e2e/palmares.spec.js`) e SINGURA care randează un ecran, deci e singurul loc unde s-ar putea
-- | vedea un filtru care nu ajunge niciodată la API. Cât timp mocul răspunde la fel la orice
-- | întrebare, suita e structural oarbă exact la defectul care a ajuns pe deploy: `kind` pus în
-- | codecul de rută și uitat în șirul de interogare, cu titlul „Verified credentials" deasupra
-- | tuturor rândurilor. Un mock care nu-și citește argumentul nu poate deosebi un filtru care merge
-- | de unul care nu merge — iar aici filtrarea e tocmai ce se verifică, nu o comoditate de demo.
-- |
-- | `total` după filtrare, câmp cu câmp:
-- |
-- |   * cu filtre de rând — numărul rândurilor care potrivesc, pentru că atât știe mocul despre
-- |     întrebarea asta. Un `total` lăsat la cel înregistrat lângă un singur rând ar fi o minciună
-- |     NOUĂ (pager-ul și linia de potriviri se construiesc din el), mai rea decât nefiltrarea
-- |     cinstită de până acum;
-- |   * fără filtre de rând — totalul ÎNREGISTRAT în fixtură (19 atestări, 12 profiluri), fiindcă
-- |     fixtura e o fereastră măsurată dintr-un set mai mare, iar cardurile din pagina de pornire
-- |     numără același set. Scăzându-l la șase, ecranul ar contrazice pagina de pornire.
-- |
-- | `limit`/`offset` se întorc așa cum au fost cerute, pentru că pager-ul își citește propriile
-- | valori din răspuns.
narrowPage
  :: forall a
   . Array (a -> Boolean)
  -> RegistryFilters
  -> { items :: Array a, total :: Int, limit :: Int, offset :: Int }
  -> { items :: Array a, total :: Int, limit :: Int, offset :: Int }
narrowPage matchers f p =
  { items: take limit (drop offset matching)
  , total: if null matchers then p.total else length matching
  , limit
  , offset
  }
  where
  matching = filter (\row -> all (\match -> match row) matchers) p.items
  limit = intOr p.limit f.limit
  offset = intOr p.offset f.offset
  -- Un `limit` sau `offset` care nu e număr NU schimbă nimic: serverul l-ar refuza cu 400, iar o
  -- fixtură n-are cum să imite un refuz — deci se randează fereastra înregistrată, nu una goală.
  intOr fallback = maybe fallback (fromMaybe fallback <<< Int.fromString)

-- | Un filtru dat devine un predicat pe rând; unul absent, niciun predicat — iar „niciun predicat"
-- | e tocmai ce deosebește o pagină cerută nefiltrat de una care n-a potrivit nimic.
matchOn :: forall a. (a -> String) -> Maybe String -> Array (a -> Boolean)
matchOn field = maybe [] \v -> [ \row -> field row == v ]

-- | Un filtru de tip da/nu. Vine din URL ca text, deci orice altceva decît „true"/„false" nu
-- | filtrează nimic — exact ce face și serverul cu un `Bool` pe care nu-l poate parsa.
matchBool :: forall a. (a -> Boolean) -> Maybe String -> Array (a -> Boolean)
matchBool field = case _ of
  Just "true" -> [ field ]
  Just "false" -> [ not <<< field ]
  _ -> []

-- | Căutarea pe text, ca a serverului: potrivire parțială, fără majuscule, peste cîmpurile date.
-- | `%` și `_` sînt literale aici, fiindcă `?q=` le tratează literal și nu ca metacaractere.
matchText :: forall a. Array (a -> String) -> Maybe String -> Array (a -> Boolean)
matchText fields = maybe [] \v ->
  [ \row -> any (\field -> String.contains (String.Pattern (String.toLower v)) (String.toLower (field row))) fields ]

getStatusMock :: forall m. Applicative m => m (Either ApiError GovStatus)
getStatusMock = pure (decodeFixture statusFixture)

getDashboardMock :: forall m. Applicative m => m (Either ApiError DashboardPage)
getDashboardMock = pure (decodeFixture dashboardFixture)

-- | Fixtura ignoră filtrele: e un răspuns înregistrat, nu o bază de date. Bundle-ul demo arată
-- | deci mereu aceleași patru rânduri, oricare facet s-ar apăsa — ceea ce e tot ce trebuie ca să
-- | verifici randarea, și e exact ce nu trebuie ca să verifici filtrarea. Filtrarea se verifică pe
-- | serverul adevărat.
getDRepExplorerMock :: forall m. Applicative m => DRepFilters -> m (Either ApiError DRepExplorerPage)
getDRepExplorerMock _ = pure (decodeFixture drepExplorerFixture)

-- | Aceeași fixtură pentru orice ID: bundle-ul demo arată mereu DRep-ul-cazul-greu.
getDRepDetailMock :: forall m. Applicative m => String -> m (Either ApiError DRepDetail)
getDRepDetailMock _ = pure (decodeFixture drepDetailFixture)

getGovActionsMock :: forall m. Applicative m => GovActionFilters -> m (Either ApiError GovActionPage)
getGovActionsMock _ = pure (decodeFixture govActionListFixture)

getGovActionDetailMock :: forall m. Applicative m => String -> m (Either ApiError GovActionDetail)
getGovActionDetailMock _ = pure (decodeFixture govActionDetailFixture)

getVotesMock :: forall m. Applicative m => VoteFilters -> m (Either ApiError VotePage)
getVotesMock _ = pure (decodeFixture votesListFixture)

searchAllMock :: forall m. Applicative m => String -> m (Either ApiError SearchResults)
searchAllMock _ = pure (decodeFixture searchFixture)

getFormulasMock :: forall m. Applicative m => m (Either ApiError (Array Formula))
getFormulasMock = pure (decodeFixture formulasFixture)

getSposMock :: forall m. Applicative m => SpoFilters -> m (Either ApiError SpoPage)
getSposMock _ = pure (decodeFixture spoListFixture)

getCommitteeMock :: forall m. Applicative m => m (Either ApiError CommitteeState)
getCommitteeMock = pure (decodeFixture committeeFixture)

getWithdrawalsMock :: forall m. Applicative m => WithdrawalFilters -> m (Either ApiError WithdrawalPage)
getWithdrawalsMock _ = pure (decodeFixture withdrawalListFixture)

getDelegationsMock :: forall m. Applicative m => DelegationFilters -> m (Either ApiError DelegationPage)
getDelegationsMock _ = pure (decodeFixture delegationListFixture)

getActivityMock :: forall m. Applicative m => ActivityFilters -> m (Either ApiError ActivityPage)
getActivityMock _ = pure (decodeFixture activityFixture)

-- | Caută id-ul CERUT în lista înregistrată, și cade pe fixture-ul de detaliu doar dacă nu e acolo.
-- |
-- | Varianta de dinainte ignora id-ul, iar asta a devenit o minciună în momentul în care paginile de
-- | detaliu au trecut de la un director de nume la căutări per id: pe pagina unui vouch, subiectul
-- | și emitentul afișau AMBELE același nume, deși href-urile duceau la profiluri diferite. Prins de
-- | suita de fixtures, care e singura ce randează ecrane — și e exact motivul pentru care un mock nu
-- | are voie să-și ignore argumentul.
getProfileMock :: forall m. Applicative m => String -> m (Either ApiError ProfileRow)
getProfileMock pid = pure case decodeFixture profileListFixture of
  Right (ProfilePage p) -> case find (\(ProfileRow r) -> r.id == pid) p.items of
    Just row -> Right row
    Nothing -> decodeFixture profileDetailFixture
  Left _ -> decodeFixture profileDetailFixture

-- | În demo, portofelul nu există, deci nimeni nu ajunge aici prin ecran. Mock-ul întoarce totuși
-- | PRIMUL profil din fixtură, și nu o eroare: un `Left` ar face ca o eventuală folosire viitoare
-- | să arate ca un defect de server, cînd de fapt e un bundle fără portofel.
getProfileByUserTokenMock :: forall m. Applicative m => String -> m (Either ApiError ProfileRow)
getProfileByUserTokenMock _ = pure case decodeFixture profileListFixture of
  Right (ProfilePage p) -> case Array.head p.items of
    Just row -> Right row
    Nothing -> decodeFixture profileDetailFixture
  Left _ -> decodeFixture profileDetailFixture

-- | Singurul filtru de rând pe care îl poartă un profil e `kind`; `subject`/`issuer` sunt întrebări
-- | despre atestări, iar `ProfileRow` nu are câmpurile.
getProfilesMock :: forall m. Applicative m => RegistryFilters -> m (Either ApiError ProfilePage)
getProfilesMock f = pure (map narrow (decodeFixture profileListFixture))
  where
  narrow (ProfilePage p) =
    ProfilePage
      ( narrowPage
          ( matchOn (\(ProfileRow r) -> r.kind) f.kind
              -- `claimed` nu e un cîmp, e o întrebare despre unul: „revendică vreo credențială".
              <> matchBool (\(ProfileRow r) -> isJust r.credential) f.claimed
              <> matchText [ \(ProfileRow r) -> r.name, \(ProfileRow r) -> r.description ] f.q
          )
          f
          p
      )

getAttestationMock :: forall m. Applicative m => String -> m (Either ApiError AttestationDetail)
getAttestationMock _ = pure (decodeFixture attestationDetailFixture)

-- | Cele trei filtre de rând ale registrului se aplică ÎMPREUNĂ (ȘI, nu SAU), fiindcă așa le
-- | compune și serverul: `?subject=X&issuer=Y` înseamnă „ce a spus Y despre X", nu reuniunea lor.
getAttestationsMock :: forall m. Applicative m => RegistryFilters -> m (Either ApiError AttestationPage)
getAttestationsMock f = pure (map narrow (decodeFixture attestationListFixture))
  where
  narrow (AttestationPage p) =
    AttestationPage
      ( narrowPage
          ( matchOn (\(AttestationRow a) -> a.kind) f.kind
              <> matchOn (\(AttestationRow a) -> a.subject) f.subject
              <> matchOn (\(AttestationRow a) -> a.issuer) f.issuer
              <> matchBool (\(AttestationRow a) -> a.accepted) f.accepted
          )
          f
          p
      )

getDisputeMock :: forall m. Applicative m => String -> m (Either ApiError DisputeRow)
getDisputeMock _ = pure (decodeFixture disputeDetailFixture)

-- | Disputele au UN filtru de rând: `resolved`, care e „are verdict". `kind`, `subject` și
-- | `issuer` nu există pe `DisputeRow`, iar `target` nu există în `RegistryFilters`.
getDisputesMock :: forall m. Applicative m => RegistryFilters -> m (Either ApiError DisputePage)
getDisputesMock f = pure (map narrow (decodeFixture disputeListFixture))
  where
  narrow (DisputePage p) =
    DisputePage (narrowPage (matchBool (\(DisputeRow d) -> isJust d.verdict) f.resolved) f p)

-- | Numerele măsurate pe preprod, ca și fixturile din care ar fi putut fi citite.
getRegistrySummaryMock :: forall m. Applicative m => m (Either ApiError RegistrySummary)
getRegistrySummaryMock = pure (Right { profiles: 12, attestations: 19, disputes: 5 })
