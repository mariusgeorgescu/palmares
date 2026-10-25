-- | Transportul real către interaction-api, prin BFF.
-- |
-- | Rutele de scriere sunt sub BasicAuth, iar credențialele NU ajung niciodată în browser: BFF-ul
-- | le adaugă server-side. De aceea `interactionBaseUrl` e un prefix de pe originea noastră
-- | (`/api/interaction`), nu URL-ul serverului.
module Capabilities.Interaction.Default
  ( buildFlowDefault
  , submitSignedDefault
  , txStatusDefault
  , interactionStatusDefault
  ) where

import Prelude

import Capabilities.Interaction.Types (FlowRequest, InteractionStatus, SubmitParams, encodeFlow, encodeSubmit, flowPath)
import Capabilities.Query.Gov.Http (ApiError, getJson, postJson)
import Data.Either (Either)
import Effect.Aff.Class (class MonadAff)

type HasInteractEnv r = (interactionBaseUrl :: String | r)

-- | Construiește. Răspunsul e tranzacția nesemnată, pe care serverul o dă ca `String` — un hex
-- | CBOR, nu un obiect.
buildFlowDefault
  :: forall m r
   . MonadAff m
  => Record (HasInteractEnv r)
  -> FlowRequest
  -> m (Either ApiError String)
buildFlowDefault env req =
  postJson (env.interactionBaseUrl <> flowPath req) (encodeFlow req)

-- | Trimite. Singurul apel din tot clientul care schimbă ceva pe lanț.
submitSignedDefault
  :: forall m r
   . MonadAff m
  => Record (HasInteractEnv r)
  -> SubmitParams
  -> m (Either ApiError String)
submitSignedDefault env params =
  postJson (env.interactionBaseUrl <> "/submit-tx") (encodeSubmit params)

-- | Întreabă dacă s-a confirmat. Răspunsul e `{tx_id, confirmed}`; aici interesează doar al doilea,
-- | iar `false` înseamnă „încă nu", nu „a eșuat" — distincția e a ecranului, nu a transportului.
txStatusDefault
  :: forall m r
   . MonadAff m
  => Record (HasInteractEnv r)
  -> String
  -> m (Either ApiError Boolean)
txStatusDefault env txId = do
  res <- getJson (env.interactionBaseUrl <> "/tx-status/" <> txId)
  pure (map (\(r :: { confirmed :: Boolean }) -> r.confirmed) res)

-- | Starea serverului de scriere. Ruta e publică prin contractul de boot — nu e sub BasicAuth —
-- | pentru că un client trebuie să poată afla dacă protocolul e oprit fără să aibă credențiale.
interactionStatusDefault
  :: forall m r
   . MonadAff m
  => Record (HasInteractEnv r)
  -> m (Either ApiError InteractionStatus)
interactionStatusDefault env = getJson (env.interactionBaseUrl <> "/status")
