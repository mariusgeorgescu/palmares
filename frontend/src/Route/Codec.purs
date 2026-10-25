-- | Path-based route codec via routing-duplex (parse + print). NotFound for unknown paths.
module Route.Codec
  ( routeCodec
  , parseRoute
  , printRoute
  ) where

import Data.Either (Either(..))
-- `(/)` din `Routing.Duplex.Generic.Syntax` ascunde împărțirea din Prelude; aici nu se împarte
-- nimic, iar avertismentul ar rămâne la fiecare build.
import Prelude hiding ((/))
import Route (Route(..))
import Route.GovQueries
  ( activityFiltersCodec
  , delegationFiltersCodec
  , drepFiltersCodec
  , govActionFiltersCodec
  , embedFiltersCodec
  , writeFiltersCodec
  , graphFiltersCodec
  , methodologyCodec
  , registryFiltersCodec
  , spoFiltersCodec
  , voteFiltersCodec
  , withdrawalFiltersCodec
  )
import Routing.Duplex (RouteDuplex', parse, path, print, root, segment)
import Routing.Duplex.Generic (noArgs, sum)
import Routing.Duplex.Generic.Syntax ((/))

-- | Codec for all routes. NotFound uses an internal path; parse failures also map to NotFound.
routeCodec :: RouteDuplex' Route
routeCodec = root $ sum
  { "Home": noArgs
  , "DRepDetail": "dreps" / segment
  , "DRepList": path "dreps" drepFiltersCodec
  , "ActionDetail": "gov-actions" / segment
  , "ActionList": path "gov-actions" govActionFiltersCodec
  , "VoteList": path "votes" voteFiltersCodec
  , "SpoList": path "spos" spoFiltersCodec
  , "Committee": path "committee" noArgs
  , "TreasuryList": path "treasury" withdrawalFiltersCodec
  , "DelegationList": path "delegations" delegationFiltersCodec
  , "Activity": path "activity" activityFiltersCodec
  , "ProfileList": path "profiles" registryFiltersCodec
  , "AttestationList": path "attestations" registryFiltersCodec
  , "DisputeList": path "disputes" registryFiltersCodec
  , "Graph": path "graph" graphFiltersCodec
  , "Embed": path "embed" embedFiltersCodec
  , "Write": path "write" writeFiltersCodec
  , "Methodology": path "methodology" methodologyCodec
  , "NotFound": path "__not_found__" noArgs
  }

parseRoute :: String -> Route
parseRoute p = case parse routeCodec p of
  Right r -> r
  Left _ -> NotFound

printRoute :: Route -> String
printRoute NotFound = "/"
printRoute r = print routeCodec r
