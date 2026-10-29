-- | Top-level route ADT for the application.
module Route
  ( Route(..)
  , section
  ) where

import Data.Generic.Rep (class Generic)
import Data.Maybe (fromMaybe)
import Prelude
import Route.GovQueries
  ( DRepFilters
  , GovActionFilters
  , MethodologyFilters
  , ActivityFilters
  , DelegationFilters
  , EmbedFilters
  , WriteFilters
  , GraphFilters
  , RegistryFilters
  , SpoFilters
  , WithdrawalFilters
  , VoteFilters
  , renderDRepFilters
  , renderGovActionFilters
  , renderSpoFilters
  , renderVoteFilters
  )

-- Rutele se adaugă pe măsură ce ecranele se livrează (plan, taskurile 5–11), nu în avans: o rută
-- fără pagină e un link care duce la NotFound.
-- Ordinea constructorilor __contează__: `Routing.Duplex.parse` acceptă o potrivire care lasă
-- segmente neconsumate (`run` ignoră restul), deci `DRepList`, care consumă doar „dreps", ar
-- înghiți și „/dreps/drep1…" dacă ar fi încercat primul. Specificul înaintea generalului.
data Route
  = Home
  | DRepDetail String
  -- Filtrele călătoresc în rută, nu în starea componentei: URL-ul e stare partajabilă, iar
  -- butoanele înainte/înapoi ale browserului sunt controale ale ecranului, nu accidente.
  | DRepList DRepFilters
  | ActionDetail String
  | ActionList GovActionFilters
  | VoteList VoteFilters
  | SpoList SpoFilters
  | Committee
  | TreasuryList WithdrawalFilters
  | DelegationList DelegationFilters
  | Activity ActivityFilters
  | ProfileDetail String
  | ProfileList RegistryFilters
  | AttestationDetail String
  | AttestationList RegistryFilters
  | DisputeDetail String
  | DisputeList RegistryFilters
  | Graph GraphFilters
  | Embed EmbedFilters
  | Write WriteFilters
  | Methodology MethodologyFilters
  | NotFound

derive instance eqRoute :: Eq Route
derive instance Generic Route _

-- `Show` e pentru mesaje de eroare și teste: un „expected DRepList ?status=active but got
-- NotFound" spune de ce a eșuat parsarea, iar un `false /= true` nu spune nimic.
--
-- Scris de mână, nu `genericShow`: reprezentarea generică a unui record de unsprezece câmpuri l-a
-- ținut pe `purs` peste șapte minute pe un singur modul, fără să termine. Oricum tipărește mai
-- citibil — URL-ul, nu arborele.
instance Show Route where
  show = case _ of
    Home -> "Home"
    DRepDetail i -> "DRepDetail " <> i
    DRepList f -> "DRepList " <> renderDRepFilters f
    ActionDetail i -> "ActionDetail " <> i
    ActionList f -> "ActionList " <> renderGovActionFilters f
    VoteList f -> "VoteList " <> renderVoteFilters f
    SpoList f -> "SpoList " <> renderSpoFilters f
    Committee -> "Committee"
    TreasuryList _ -> "TreasuryList"
    DelegationList f -> "DelegationList " <> fromMaybe "" f.drep_id
    Activity f -> "Activity " <> fromMaybe "" f.before
    ProfileDetail i -> "ProfileDetail " <> i
    ProfileList _ -> "ProfileList"
    AttestationDetail i -> "AttestationDetail " <> i
    AttestationList _ -> "AttestationList"
    DisputeDetail i -> "DisputeDetail " <> i
    DisputeList _ -> "DisputeList"
    Graph f -> "Graph " <> fromMaybe "" f.drep
    Embed f -> "Embed " <> fromMaybe "" f.drep
    Write f -> "Write " <> fromMaybe "" f.flow
    Methodology f -> "Methodology " <> fromMaybe "" f.focus
    NotFound -> "NotFound"

-- | Secțiunea din care face parte ruta — numele sub care barele de navigare o marchează.
-- |
-- | Stă aici, lângă tipul `Route`, și nu în bare: „în ce secțiune e ruta asta?" e o proprietate a
-- | rutei și a nimic altceva. Trăise în două exemplare, una în `NavBar` și una în `Sidebar`, iar
-- | fiecare rută de detaliu adăugată săptămâna asta a trebuit scrisă în amândouă — a doua copie e
-- | locul unde se uită.
-- |
-- | Două reguli pe care le ține, fiindcă altfel bara luminează altceva decât ecranul deschis:
-- | filtrele NU schimbă secțiunea (un `Eq` pe `Route` le-ar compara, deci `/profiles?kind=auditor`
-- | n-ar mai lumina „Profiles"), iar o rută de detaliu stă în secțiunea listei ei.
section :: Route -> String
section = case _ of
  Home -> "home"
  DRepList _ -> "dreps"
  DRepDetail _ -> "dreps"
  ActionList _ -> "actions"
  ActionDetail _ -> "actions"
  VoteList _ -> "votes"
  SpoList _ -> "spos"
  Committee -> "committee"
  TreasuryList _ -> "treasury"
  DelegationList _ -> "delegations"
  Activity _ -> "activity"
  ProfileDetail _ -> "profiles"
  ProfileList _ -> "profiles"
  AttestationDetail _ -> "attestations"
  AttestationList _ -> "attestations"
  DisputeDetail _ -> "disputes"
  DisputeList _ -> "disputes"
  Graph _ -> "graph"
  -- Fișa de încorporat nu apare în nicio bară, pentru că nu se navighează la ea: se pune în
  -- `iframe`. Are totuși o secțiune proprie, ca să nu se lipească accidental de alta.
  Embed _ -> "embed"
  Write _ -> "write"
  Methodology _ -> "methodology"
  -- Nicio bară nu are o destinație „none", deci pe NotFound nu se marchează nimic — exact ce
  -- trebuie: ecranul acela nu e într-o secțiune.
  NotFound -> "none"
