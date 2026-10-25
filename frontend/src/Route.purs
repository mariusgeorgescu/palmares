-- | Top-level route ADT for the application.
module Route
  ( Route(..)
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
  | ProfileList RegistryFilters
  | AttestationList RegistryFilters
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
    ProfileList _ -> "ProfileList"
    AttestationList _ -> "AttestationList"
    DisputeList _ -> "DisputeList"
    Graph f -> "Graph " <> fromMaybe "" f.drep
    Embed f -> "Embed " <> fromMaybe "" f.drep
    Write f -> "Write " <> fromMaybe "" f.flow
    Methodology f -> "Methodology " <> fromMaybe "" f.focus
    NotFound -> "NotFound"
