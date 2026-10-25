-- | Path-based route codec via routing-duplex (parse + print). NotFound for unknown paths.
module Route.Codec
  ( routeCodec
  , parseRoute
  , printRoute
  ) where

import Data.Either (Either(..))
import Prelude
import Route (Route(..))
import Route.GovQueries (drepFiltersCodec)
import Routing.Duplex (RouteDuplex', parse, path, print, root)
import Routing.Duplex.Generic (noArgs, sum)

-- | Codec for all routes. NotFound uses an internal path; parse failures also map to NotFound.
routeCodec :: RouteDuplex' Route
routeCodec = root $ sum
  { "Home": noArgs
  , "DRepList": path "dreps" drepFiltersCodec
  , "NotFound": path "__not_found__" noArgs
  }

parseRoute :: String -> Route
parseRoute p = case parse routeCodec p of
  Right r -> r
  Left _ -> NotFound

printRoute :: Route -> String
printRoute NotFound = "/"
printRoute r = print routeCodec r
