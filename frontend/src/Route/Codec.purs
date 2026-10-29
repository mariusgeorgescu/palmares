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

import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), stripSuffix)
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
import Routing.Duplex (RouteDuplex', as, parse, path, print, root, segment)
import Routing.Duplex.Generic (noArgs, sum)
import Routing.Duplex.Generic.Syntax ((/))

-- `segment` reușește și pe un segment gol, așa că un slash final făcea ca „/profiles/" să fie
-- parsat ca `ProfileDetail ""`: ecranul cerea apoi `/profiles/` de la API, primea o pagină de
-- listă și afișa alerta de decodare. Garda respinge șirul gol la parsare, deci ramura de listă
-- câștigă din nou `Alt`-ul și „/profiles/" ajunge la `ProfileList`. Stă aici, unde converg toate
-- rutele de detaliu, nu în fiecare componentă — și nu atinge ordinea detaliu-înaintea-listei.
nonEmptySegment :: RouteDuplex' String
nonEmptySegment = as identity (\s -> if s == "" then Left "non-empty segment" else Right s) segment

-- | Codec for all routes. NotFound uses an internal path; parse failures also map to NotFound.
routeCodec :: RouteDuplex' Route
routeCodec = root $ sum
  { "Home": noArgs
  , "DRepDetail": "dreps" / nonEmptySegment
  , "DRepList": path "dreps" drepFiltersCodec
  , "ActionDetail": "gov-actions" / nonEmptySegment
  , "ActionList": path "gov-actions" govActionFiltersCodec
  , "VoteList": path "votes" voteFiltersCodec
  , "SpoList": path "spos" spoFiltersCodec
  , "Committee": path "committee" noArgs
  , "TreasuryList": path "treasury" withdrawalFiltersCodec
  , "DelegationList": path "delegations" delegationFiltersCodec
  , "Activity": path "activity" activityFiltersCodec
  -- Detaliul INAINTEA listei, ca `/profiles/<id>` sa nu fie inghitit de `/profiles`.
  , "ProfileDetail": "profiles" / nonEmptySegment
  , "ProfileList": path "profiles" registryFiltersCodec
  , "AttestationDetail": "attestations" / nonEmptySegment
  , "AttestationList": path "attestations" registryFiltersCodec
  , "DisputeDetail": "disputes" / nonEmptySegment
  , "DisputeList": path "disputes" registryFiltersCodec
  , "Graph": path "graph" graphFiltersCodec
  , "Embed": path "embed" embedFiltersCodec
  , "Write": path "write" writeFiltersCodec
  , "Methodology": path "methodology" methodologyCodec
  , "NotFound": path "__not_found__" noArgs
  }

parseRoute :: String -> Route
parseRoute p = case parse routeCodec (withoutTrailingSlash p) of
  Right r -> r
  Left _ -> NotFound

-- | Un slash final nu e o adresă diferită, deci nu are voie să fie o rută diferită.
-- |
-- | `nonEmptySegment` oprește `/profiles/` să se parseze ca un detaliu cu id gol — care cerea
-- | `/profiles/` de la API și randa alerta de decodare — dar codecul de listă nu consumă nici el
-- | segmentul gol, deci fără normalizarea asta adresa ar cădea pe `NotFound`: o pagină lipsă pentru
-- | o adresă perfect validă. Se taie AICI, înaintea parsării, ca să se aplice tuturor rutelor
-- | deodată și nu doar celor cinci cu segment.
withoutTrailingSlash :: String -> String
withoutTrailingSlash s = case stripSuffix (Pattern "/") s of
  Just "" -> "/"
  Just rest -> rest
  Nothing -> s

printRoute :: Route -> String
printRoute NotFound = "/"
printRoute r = print routeCodec r
