-- | Transportul HTTP pentru suprafața de citire, și singurul loc care știe cum arată o eroare a
-- | acestui API.
-- |
-- | __De ce nu `ResponseFormat.json`, pe care îl folosea template-ul.__ Trei fapte măsurate pe
-- | serviciul care rulează fac parsarea necondiționată greșită:
-- |
-- |   * credențiale greșite pe interaction-api dau __403, nu 401__, și cu __corp gol__ — deci
-- |     `.json()` aruncă, iar utilizatorul vede o eroare despre JSON în loc de una despre
-- |     credențiale;
-- |   * `attest-sync` întoarce la 503 un `show` de Haskell, care nu e JSON deloc;
-- |   * restul suprafeței respectă `{code, message}` cu 24 de coduri, iar `code` e exact ce un UI
-- |     trebuie să ramifice pe el.
-- |
-- | Deci: corpul se citește ca `String`, JSON se parsează __doar pe 2xx__, și orice alt status trece
-- | prin `{code, message}` cu o cădere pe un cod derivat din status când nici asta nu se poate.
module Capabilities.Query.Gov.Http
  ( ApiError(..)
  , Freshness
  , emptyFreshness
  , classifyResponse
  , errorCodeForStatus
  , readFreshness
  , lookupHeader
  , getJson
  , getJsonWithFreshness
  , renderApiError
  , isRetryable
  ) where

import Prelude

import Affjax.ResponseFormat as ResponseFormat
import Affjax.ResponseHeader (ResponseHeader, name, value)
import Affjax.StatusCode (StatusCode(..))
import Affjax.Web as AX
import Data.Argonaut.Core (Json)
import Data.Argonaut.Decode (class DecodeJson, decodeJson, printJsonDecodeError)
import Data.Argonaut.Parser (jsonParser)
import Data.Array (find)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.String as String
import Data.String.CodeUnits as CU
import Effect.Aff.Class (class MonadAff, liftAff)

-- | Cele trei feluri în care o cerere poate să nu dea datele cerute. Sunt ținute distincte pentru că
-- | UI-ul le tratează diferit: `Transport` merită un buton de reîncercare, `Api` merită mesajul
-- | serverului, iar `Decode` e un bug al nostru și nu trebuie prezentat ca pe o problemă a
-- | utilizatorului.
data ApiError
  = Transport String
  | Api { code :: String, message :: String }
  | Decode String

derive instance Eq ApiError

instance Show ApiError where
  show = case _ of
    Transport m -> "Transport " <> show m
    Api r -> "Api " <> show r.code <> " " <> show r.message
    Decode m -> "Decode " <> show m

-- | Prospețimea datelor, citită din headere. Opt headere, toate opționale: cinci de la db-sync și
-- | trei de la proiectorul de atestări, care lipsesc cu totul pe un deploy doar-guvernanță. Numele
-- | sunt copiate din `Query/Gov.hs:638-664`, nu ghicite.
-- |
-- | Toate câmpurile sunt `Maybe` și pe un al doilea motiv: cross-origin, un browser vede doar
-- | headerele din `Access-Control-Expose-Headers`. Noi vorbim same-origin prin BFF, deci le vedem pe
-- | toate — dar un `Nothing` aici nu trebuie să însemne niciodată un ecran rupt.
type Freshness =
  { chainEpoch :: Maybe Int
  , chainSlot :: Maybe Int
  , chainBlockTime :: Maybe String
  , dataLagSeconds :: Maybe Int
  , dataSource :: Maybe String
  , attestSlot :: Maybe Int
  , attestLagSeconds :: Maybe Int
  , attestState :: Maybe String
  }

emptyFreshness :: Freshness
emptyFreshness =
  { chainEpoch: Nothing
  , chainSlot: Nothing
  , chainBlockTime: Nothing
  , dataLagSeconds: Nothing
  , dataSource: Nothing
  , attestSlot: Nothing
  , attestLagSeconds: Nothing
  , attestState: Nothing
  }

-- | Căutare case-insensitive: numele de headere HTTP sunt case-insensitive prin specificație, iar
-- | browserele le dau minuscule. O comparație exactă pe `X-Chain-Epoch` ar găsi zero headere în
-- | browser și toate în teste, care e cel mai prost fel de bug.
lookupHeader :: String -> Array ResponseHeader -> Maybe String
lookupHeader needle headers =
  value <$> find (\h -> String.toLower (name h) == String.toLower needle) headers

readFreshness :: Array ResponseHeader -> Freshness
readFreshness hs =
  { chainEpoch: int "X-Chain-Epoch"
  , chainSlot: int "X-Chain-Slot"
  , chainBlockTime: str "X-Chain-Block-Time"
  , dataLagSeconds: int "X-Data-Lag-Seconds"
  , dataSource: str "X-Data-Source"
  , attestSlot: int "X-Attest-Slot"
  , attestLagSeconds: int "X-Attest-Lag-Seconds"
  , attestState: str "X-Attest-State"
  }
  where
  str n = lookupHeader n hs
  int n = lookupHeader n hs >>= Int.fromString

-- | Codul publicat pentru un status care nu poartă un corp `{code, message}`. Valorile sunt cele pe
-- | care le folosește și serverul, ca un `case` pe `code` să nu trebuiască să știe de unde a venit
-- | eroarea.
errorCodeForStatus :: Int -> String
errorCodeForStatus = case _ of
  400 -> "bad_request"
  401 -> "unauthorized"
  403 -> "forbidden"
  404 -> "not_found"
  406 -> "not_acceptable"
  429 -> "rate_limited"
  503 -> "db_unavailable"
  s -> "http_" <> show s

-- | `true` doar pentru ce chiar merită o a doua încercare.
-- |
-- | `db_unavailable` e __exclus intenționat__: pe acest serviciu înseamnă aproape mereu „prea lent",
-- | nu „picat" — măsurat, `/drep/{id}` dădea 503 la 30,3 s în timp ce `/dreps` răspundea în 0,69 s.
-- | Un query abandonat de client macină mai departe în Postgres, deci reîncercările compun sarcina
-- | care a produs timeout-ul.
isRetryable :: ApiError -> Boolean
isRetryable = case _ of
  Transport _ -> true
  Api _ -> false
  Decode _ -> false

-- | Partea pură, și singura care are nevoie de teste: din status plus corp, ori `Json` ori eroarea
-- | potrivită.
classifyResponse :: Int -> String -> Either ApiError Json
classifyResponse status body
  | status >= 200 && status < 300 = lmap Decode (jsonParser body)
  | otherwise = Left (apiErrorFromBody status body)

apiErrorFromBody :: Int -> String -> ApiError
apiErrorFromBody status body =
  case jsonParser body of
    Right json -> case decodeJson json of
      Right (r :: { code :: String, message :: String }) -> Api r
      Left _ -> fallback
    Left _ -> fallback
  where
  fallback = Api { code: errorCodeForStatus status, message: fallbackMessage status body }

-- | Mesajul când serverul n-a dat unul. Corpul e tăiat la 200 de caractere pentru că un `show` de
-- | Haskell sau o pagină de eroare a unui proxy pot fi arbitrar de lungi, și un mesaj de eroare nu e
-- | locul unde se randează text necontrolat la lungime necontrolată.
fallbackMessage :: Int -> String -> String
fallbackMessage status body =
  case String.trim body of
    "" -> "The service answered " <> show status <> " with an empty body."
    trimmed -> clamp200 trimmed
  where
  clamp200 s
    | String.length s <= 200 = s
    | otherwise = CU.take 197 s <> "..."

-- | Mesaj pentru om. Engleză, pentru că produsul e infrastructură publică pentru ecosistemul
-- | Cardano; comentariile și commit-urile rămân în română.
renderApiError :: ApiError -> String
renderApiError = case _ of
  Transport m -> "Could not reach the service: " <> m
  Api r -> r.message
  Decode m -> "The service returned a response this app could not read: " <> m

getJson :: forall m a. MonadAff m => DecodeJson a => String -> m (Either ApiError a)
getJson url = map (map _.body) (getJsonWithFreshness url)

getJsonWithFreshness
  :: forall m a
   . MonadAff m
  => DecodeJson a
  => String
  -> m (Either ApiError { body :: a, freshness :: Freshness })
getJsonWithFreshness url = liftAff do
  res <- AX.get ResponseFormat.string url
  pure case res of
    Left err -> Left (Transport (AX.printError err))
    Right r -> case classifyResponse (statusOf r.status) r.body of
      Left e -> Left e
      Right json -> case decodeJson json of
        Left e -> Left (Decode (printJsonDecodeError e))
        Right b -> Right { body: b, freshness: readFreshness r.headers }
  where
  statusOf (StatusCode s) = s
