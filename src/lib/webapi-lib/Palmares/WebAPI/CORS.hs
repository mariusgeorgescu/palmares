{-# LANGUAGE OverloadedStrings #-}

-- | CORS middleware driven by an explicit origin allowlist (fail-closed).
-- Only origins present in @CORS_ALLOWED_ORIGINS@ receive CORS headers; every
-- other origin gets none, so the browser blocks the cross-origin response.
--
-- __The policy is unchanged and the silence is not__ (@DC-06@). An empty allowlist still denies
-- every origin — see 'getCorsConfigFromEnv' for why that stays the default — but it now says so at
-- boot, because nothing else can. A deny-all deployment is indistinguishable, from inside a browser,
-- from a server that forgot to expose its headers: both produce a response with no
-- @Access-Control-@ anything. 'describeCorsConfig' is the only place that difference is stated.
module Palmares.WebAPI.CORS where

import Data.ByteString (ByteString)
import qualified Data.List
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Network.HTTP.Types as HttpTypes
import Network.HTTP.Types.Header (hOrigin)
import Network.Wai
import Network.Wai.Middleware.Cors
import System.Environment (lookupEnv)

-- | Resolved CORS configuration. 'allowCredentials' is currently always 'False'
-- (frontend is same-origin / proxied / token-based).
data CorsConfig = CorsConfig
  { allowedOrigins :: [ByteString],
    allowCredentials :: Bool
  }
  deriving (Eq, Show)

-- | Parse a comma-separated origin allowlist: trims whitespace, drops empties.
parseCorsOrigins :: String -> [ByteString]
parseCorsOrigins raw =
  [ TE.encodeUtf8 t
  | chunk <- T.splitOn "," (T.pack raw),
    let t = T.strip chunk,
    not (T.null t)
  ]

-- | Read @CORS_ALLOWED_ORIGINS@ and __announce the resolved policy on stdout__; unset/empty yields
-- an empty allowlist (no cross-origin allowed). Credentials are disabled.
--
-- __Deny-all stays the default.__ This service's write side is guarded by Basic auth and nothing
-- else, so a permissive default would hand every page on the internet a cross-origin write form
-- against it; and the deployed topology puts a proxy and a same-origin frontend in front of these
-- APIs, so the allowlist being empty is the ordinary case rather than a mistake. What is indefensible
-- is doing it in silence, which is what @DC-06@ found: 'freshnessExposedHeaders' is correct, the
-- headers are sent on every response, and a browser client can read none of them with nothing
-- anywhere saying why.
--
-- __This function prints, which its name does not suggest.__ Deliberate, and the ceiling is named:
-- it is the one line all three servers already call at boot, and the alternative is the same
-- announcement pasted into three @Main.hs@ files that would then drift. If a server ever needs the
-- description without the printing, 'describeCorsConfig' is pure and exported.
getCorsConfigFromEnv :: IO CorsConfig
getCorsConfigFromEnv = do
  mOrigins <- lookupEnv "CORS_ALLOWED_ORIGINS"
  let cfg =
        CorsConfig
          { allowedOrigins = maybe [] parseCorsOrigins mOrigins,
            allowCredentials = False
          }
  mapM_ putStrLn (describeCorsConfig cfg)
  return cfg

-- | The boot announcement: what a browser will be allowed to do, and what it will not.
--
-- The empty case spells out the consequence instead of leaving it to be discovered from a browser
-- console, and names the headers being withheld — those are the ones somebody reading the API
-- documentation will go looking for and fail to find.
--
-- The warning arm catches the two misconfigurations that produce exactly the same silence as no
-- configuration at all, so an operator who DID set the variable is not left measuring the deny path.
-- An @Origin@ header is always @scheme:\/\/host[:port]@ — no path, no trailing slash — and it is
-- never the literal @*@, so @https:\/\/a.com\/@ and @*@ both parse, both land in the allowlist, and
-- neither can ever equal an incoming origin. 'corsPolicy' compares by equality, on purpose.
describeCorsConfig :: CorsConfig -> [String]
describeCorsConfig cfg = case allowedOrigins cfg of
  [] ->
    [ "CORS: CORS_ALLOWED_ORIGINS is empty — every cross-origin browser request is DENIED. No \
      \Access-Control-* header is sent, so the browser blocks the response. Same-origin pages and \
      \non-browser clients (curl, server-to-server) are unaffected.",
      "CORS: until an origin is allowlisted, these response headers are SENT but unreadable by \
      \cross-origin JavaScript: " <> unwords (map show freshnessExposedHeaders)
    ]
  origins ->
    [ "CORS: allowing " <> show (length origins) <> " origin(s), every other origin DENIED: " <> unwords (map show origins),
      "CORS: credentials disabled; exposing " <> unwords (map show freshnessExposedHeaders)
    ]
      <> [ "CORS: WARNING — " <> show o <> " can never match an Origin header (scheme://host[:port], \
           \no path, no trailing slash, never a literal *), so it allows nothing."
         | o <- origins,
           cannotMatchAnOrigin o
         ]

-- | Whether an allowlist entry is incapable of ever equalling an @Origin@ header.
cannotMatchAnOrigin :: ByteString -> Bool
cannotMatchAnOrigin o = case T.breakOn "://" (TE.decodeUtf8Lenient o) of
  (_, rest)
    | T.null rest -> True -- no scheme at all, which covers `*` and a bare hostname
    | otherwise -> T.isInfixOf "/" (T.drop 3 rest) -- a path or a trailing slash

-- | The freshness headers every response carries, named here so the browser can read them.
--
-- A response header is invisible to @fetch()@ unless it is in @Access-Control-Expose-Headers@.
-- Without this list the server would send the chain point on every cross-origin response and the
-- staleness chip would silently show nothing — a failure with no error anywhere to find it by.
freshnessExposedHeaders :: [HttpTypes.HeaderName]
freshnessExposedHeaders =
  [ "X-Chain-Epoch",
    "X-Chain-Slot",
    "X-Chain-Block-Time",
    "X-Data-Lag-Seconds",
    "X-Data-Source",
    -- `CS-07` added these three and did not add them here, which is the exact failure the paragraph
    -- above describes: the server sends the projector's state on every response and a browser client
    -- cannot read any of it, with nothing logged anywhere to find it by.
    "X-Attest-Slot",
    "X-Attest-Lag-Seconds",
    "X-Attest-State"
  ]

-- | Policy: reflect the request 'Origin' only if it is in the allowlist,
-- otherwise emit no CORS headers.
corsPolicy :: CorsConfig -> Request -> Maybe CorsResourcePolicy
corsPolicy cfg req =
  case Data.List.lookup hOrigin (requestHeaders req) of
    Just o
      | o `elem` allowedOrigins cfg ->
          Just
            simpleCorsResourcePolicy
              { corsOrigins = Just ([o], allowCredentials cfg),
                corsMethods = ["GET", "POST", "PUT", "OPTIONS", "DELETE"],
                corsRequestHeaders = simpleHeaders <> [HttpTypes.hAuthorization],
                corsExposedHeaders = Just $ simpleHeaders <> [HttpTypes.hAuthorization] <> freshnessExposedHeaders,
                corsVaryOrigin = True,
                corsRequireOrigin = False,
                corsIgnoreFailures = False,
                corsMaxAge = Just 600
              }
    _ -> Nothing

-- | WAI middleware applying the allowlist CORS policy.
mkCorsMiddleware :: CorsConfig -> Middleware
mkCorsMiddleware cfg = cors (corsPolicy cfg)
