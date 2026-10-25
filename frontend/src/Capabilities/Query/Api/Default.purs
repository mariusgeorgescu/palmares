-- | HTTP (production) implementation of `MonadQueryApi`. AppM delegates here.
-- | Each function takes the part of the reader env it needs via `HasApiEnv`.
module Capabilities.Query.Api.Default
  ( getItemsPageDefault
  ) where

import Prelude

import Affjax.ResponseFormat as ResponseFormat
import Affjax.Web as AX
import Capabilities.Query.Api.Env (HasApiEnv)
import Capabilities.Query.Api.Types (ItemsPage, ItemsQuery)
import Data.Argonaut.Decode (decodeJson, printJsonDecodeError)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff, liftAff)

-- | GET <apiBaseUrl>/items?limit&offset&search. Returns Left on transport or
-- | decode failure. The mock implementation provides the same shape offline.
getItemsPageDefault
  :: forall m r
   . MonadAff m
  => Record (HasApiEnv r)
  -> ItemsQuery
  -> m (Either String ItemsPage)
getItemsPageDefault env query = liftAff do
  let url = env.apiBaseUrl <> "/items?" <> renderQuery query
  res <- AX.get ResponseFormat.json url
  case res of
    Left err -> pure (Left (AX.printError err))
    Right { body } -> pure (lmap printJsonDecodeError (decodeJson body))
  where
  renderQuery q =
    "limit=" <> show q.limit
      <> "&offset="
      <> show q.offset
      <> case q.search of
        Just s -> "&search=" <> s
        Nothing -> ""
