-- | Implementarea HTTP a lui `MonadQueryGov`. `AppM` deleagă aici.
-- |
-- | Fiecare funcție primește prin `HasGovEnv` doar partea de env de care are nevoie, și trece prin
-- | `Http.getJson` — care e singurul loc care știe cum arată o eroare a acestui API.
module Capabilities.Query.Gov.Default
  ( getStatusDefault
  , getDashboardDefault
  , getDRepExplorerDefault
  , getDRepDetailDefault
  , getGovActionsDefault
  , getGovActionDetailDefault
  , getVotesDefault
  , searchAllDefault
  , getFormulasDefault
  , getSposDefault
  , getCommitteeDefault
  , getWithdrawalsDefault
  , getDelegationsDefault
  ) where

import Prelude

import Capabilities.Query.Gov.Env (HasGovEnv)
import Capabilities.Query.Gov.Http (ApiError, getJson)
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
  )
import Data.Either (Either)
import Data.Maybe (Maybe(..))
import Data.String as String
import Effect.Aff.Class (class MonadAff)
import Route.GovQueries
  ( DRepFilters
  , GovActionFilters
  , DelegationFilters
  , SpoFilters
  , VoteFilters
  , WithdrawalFilters
  , renderSpoFilters
  , withdrawalListHrefFor
  , delegationListHrefFor
  , encodePathSegment
  , renderDRepFilters
  , renderGovActionFilters
  , encodeQueryValue
  , renderVoteFilters
  )

getStatusDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> m (Either ApiError GovStatus)
getStatusDefault env = getJson (env.queryBaseUrl <> "/status")

getDashboardDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> m (Either ApiError DashboardPage)
getDashboardDefault env = getJson (env.queryBaseUrl <> "/pages/dashboard")

getDRepExplorerDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> DRepFilters
  -> m (Either ApiError DRepExplorerPage)
getDRepExplorerDefault env filters =
  getJson (env.queryBaseUrl <> "/pages/drep-explorer" <> renderDRepFilters filters)

getDRepDetailDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> String
  -> m (Either ApiError DRepDetail)
getDRepDetailDefault env drepId =
  getJson (env.queryBaseUrl <> "/pages/drep/" <> encodePathSegment drepId)

getGovActionsDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> GovActionFilters
  -> m (Either ApiError GovActionPage)
getGovActionsDefault env filters =
  getJson (env.queryBaseUrl <> "/gov-actions" <> renderGovActionFilters filters)

getGovActionDetailDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> String
  -> m (Either ApiError GovActionDetail)
getGovActionDetailDefault env actionId =
  getJson (env.queryBaseUrl <> "/pages/gov-action/" <> encodePathSegment actionId)

getVotesDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> VoteFilters
  -> m (Either ApiError VotePage)
getVotesDefault env filters = getJson (env.queryBaseUrl <> "/votes" <> renderVoteFilters filters)

-- | Interogarea se codează procentual: e text scris de om și poate conține orice.
searchAllDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> String
  -> m (Either ApiError SearchResults)
searchAllDefault env q = getJson (env.queryBaseUrl <> "/search?q=" <> encodeQueryValue q)

getFormulasDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> m (Either ApiError (Array Formula))
getFormulasDefault env = getJson (env.queryBaseUrl <> "/metrics/formulas")

getSposDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> SpoFilters
  -> m (Either ApiError SpoPage)
getSposDefault env filters = getJson (env.queryBaseUrl <> "/spos" <> renderSpoFilters filters)

getCommitteeDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> m (Either ApiError CommitteeState)
getCommitteeDefault env = getJson (env.queryBaseUrl <> "/committee")

-- | Calea se compune din exact același helper care face href-ul din UI, ca să nu existe două
-- | definiții ale aceleiași interogări. `withdrawalListPath` e „/treasury" în rută și
-- | „/treasury-withdrawals" în API, deci prefixul se taie aici.
getWithdrawalsDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> WithdrawalFilters
  -> m (Either ApiError WithdrawalPage)
getWithdrawalsDefault env filters =
  getJson (env.queryBaseUrl <> "/treasury-withdrawals" <> queryOf (withdrawalListHrefFor filters))

getDelegationsDefault
  :: forall m r
   . MonadAff m
  => Record (HasGovEnv r)
  -> DelegationFilters
  -> m (Either ApiError DelegationPage)
getDelegationsDefault env filters =
  getJson (env.queryBaseUrl <> "/delegations" <> queryOf (delegationListHrefFor filters))

-- | Partea de după „?" dintr-un href, sau șirul gol. Astfel ruta și cererea poartă ACELEAȘI
-- | parametri, și nu două liste care se pot desincroniza.
queryOf :: String -> String
queryOf href = case String.indexOf (String.Pattern "?") href of
  Just i -> String.drop i href
  Nothing -> ""
