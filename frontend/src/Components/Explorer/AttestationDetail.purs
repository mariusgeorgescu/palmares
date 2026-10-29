-- | Pagina unui singur vouch: `GET /attestations/{id}`.
-- |
-- | Serverul trimite atestarea ÎMPREUNĂ cu disputele ei, deci ecranul e o singură cerere. Asta e
-- | si motivul pentru care pagina exista separat de lista: in lista, numarul de provocari e un
-- | contor intr-o celula, iar ca sa vezi CE s-a contestat trebuia sa te duci pe alt ecran si sa
-- | filtrezi. Aici provocarea sta sub afirmatia pe care o ataca.
-- |
-- | Ce aduce in plus fata de rindul din lista: partile ca LINKURI (lista arata id-uri trunchiate
-- | cu elipsa), dovada de pe lant (`tx_hash`), si intervalul revendicat — scris ca pretentie,
-- | fiindca nimic pe lant nu-l stabileste.
module Components.Explorer.AttestationDetail
  ( Slot
  , Output
  , _attestationDetail
  , component
  ) where

import Prelude

import AppEnv as AppEnv
import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getAttestation, getProfiles)
import Capabilities.Query.Gov.Types
  ( AttestationDetail(..)
  , AttestationRow(..)
  , DisputeRow(..)
  , ProfilePage(..)
  , ProfileRow(..)
  )
import Components.Explorer.DisputeList (verdictClass)
import Components.Shared.DRepIdentity (shortId)
import Components.Shared.OnchainId as OnchainId
import Data.Array (null)
import Data.Const (Const)
import Data.Either (Either(..), either)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Tuple (Tuple(..))
import Format (formatAda, formatDay, humanize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Route (Route)
import Route.GovQueries (disputeDetailHrefFor, emptyRegistryFilters, profileDetailHrefFor, writeHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_attestationDetail :: Proxy "attestationDetail"
_attestationDetail = Proxy

type Input = String

type State =
  { attestationId :: String
  , detail :: RemoteData ApiError AttestationDetail
  , names :: Map String String
  }

data Action
  = Initialize
  | Retry
  | Receive Input

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \attestationId -> { attestationId, detail: NotAsked, names: Map.empty }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  handleAction = case _ of
    Initialize -> void (H.fork load)
    Retry -> load
    Receive aid -> do
      st <- H.get
      when (aid /= st.attestationId) do
        H.modify_ _ { attestationId = aid }
        load

  load = do
    st <- H.get
    H.modify_ _ { detail = Loading }
    res <- getAttestation st.attestationId
    H.modify_ _ { detail = either Failure Success res }
    -- Aceeași regulă ca în liste: numele se cer o dată, iar eșecul lor NU strică ecranul — fără
    -- ele se arată identificatorii, care sînt oricum lucrul verificabil.
    when (Map.isEmpty st.names) do
      profiles <- getProfiles (emptyRegistryFilters { limit = Just "200" })
      case profiles of
        Left _ -> pure unit
        Right (ProfilePage pp) ->
          H.modify_ _ { names = Map.fromFoldable (map (\(ProfileRow r) -> Tuple r.id r.name) pp.items) }

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
      [ case st.detail of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure "The vouch could not be loaded." e
          Success d -> HH.div [ HP.class_ (HH.ClassName "space-y-4") ] [ header st d, challenges d ]
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading the vouch…" ]
          ]
      ]

  failure msg e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text msg ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  header st (AttestationDetail d) =
    let
      AttestationRow a = d.attestation
    in
      HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
        [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
            [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text a.name ]
            , HH.span [ HP.class_ (HH.ClassName "badge badge-outline") ] [ HH.text (humanize a.kind) ]
            , HH.span
                [ HP.class_
                    (HH.ClassName ("badge " <> if a.accepted then "badge-success" else "badge-outline"))
                ]
                [ HH.text (if a.accepted then "accepted" else "not yet") ]
            ]
        , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ] [ HH.text a.description ]
        -- Propoziția care spune ce e un vouch, pe ecranul unde cineva se uită la UNUL. Fără ea,
        -- o afirmație necontrasemnată arată ca un fapt constatat.
        , if a.accepted then
            HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "The subject countersigned this. It cannot be un-accepted." ]
          else
            HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text
                  "Stated, but the subject has not countersigned it. That is not the same as denied."
              ]
        -- Gasit construind ecranul: o afirmatie poate arata `accepted` si avea dedesubt o
        -- provocare `upheld`, fara nimic care sa lege cele doua. Textul fluxului de scriere spune
        -- „Upheld means the vouch falls", deci ecranul care le arata pe amindoua trebuie sa spuna
        -- ce s-a intimplat. Nu se sterge nimic: o afirmatie contestata se arata LINGA provocarea
        -- ei, nu in locul ei.
        , if a.upheldDisputeCount > 0 then
            HH.p [ HP.class_ (HH.ClassName "alert alert-warning text-sm") ]
              [ HH.text
                  "A challenge against this was upheld. The claim and its acceptance stay in the \
                  \register — nothing here is deleted — but it did not survive the objection."
              ]
          else HH.text ""
        , HH.dl [ HP.class_ (HH.ClassName "grid gap-x-6 gap-y-1 sm:grid-cols-2 text-sm pt-1") ]
            ( [ party st "About" a.subject
              , party st "Stated by" a.issuer
              , field "On" (formatDay a.date)
              , HH.div_
                  [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Written by transaction" ]
                  , HH.dd [ HP.class_ (HH.ClassName "font-mono") ]
                      [ HH.text (shortId d.txHash)
                      , OnchainId.chip
                          { value: d.txHash, kind: OnchainId.Tx, explorerBase: AppEnv.explorerBase }
                      ]
                  ]
              ]
                <> credentialField d
                <> periodField d
            )
        , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-3 pt-1") ]
            [ if a.accepted then HH.text ""
              else
                HH.a
                  [ HP.href (writeHrefFor { flow: Just "accept-attestation", subject: Just a.id })
                  , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
                  ]
                  [ HH.text "Accept" ]
            , HH.a
                [ HP.href (writeHrefFor { flow: Just "open-dispute", subject: Just a.id })
                , HP.class_ (HH.ClassName "link link-hover text-sm self-center")
                ]
                [ HH.text "Challenge this vouch" ]
            ]
        ]

  field label value =
    HH.div_
      [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text label ]
      , HH.dd_ [ HH.text value ]
      ]

  -- Partea e un LINK către profil. În listă e un id trunchiat cu elipsă, deci ca să ajungi la
  -- cineva trebuia să copiezi șaizeci de caractere dintr-un chip.
  party st label pid =
    HH.div_
      [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text label ]
      , HH.dd_
          [ HH.a
              [ HP.href (profileDetailHrefFor pid), HP.class_ (HH.ClassName "link link-hover") ]
              [ HH.text (fromMaybe (shortId pid) (Map.lookup pid st.names)) ]
          ]
      ]

  credentialField d = case d.credential of
    Nothing -> []
    Just c ->
      [ HH.div_
          [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Credential named" ]
          , HH.dd [ HP.class_ (HH.ClassName "font-mono") ]
              [ HH.text (shortId c)
              , OnchainId.chip { value: c, kind: OnchainId.DRep, explorerBase: AppEnv.explorerBase }
              ]
          ]
      ]

  -- Intervalul e AUTODECLARAT: nimic pe lanț nu-l stabilește, iar harta API→ecran o spune
  -- textual. Deci se scrie ca pretenție, nu ca fapt, altfel ecranul promite o verificare pe care
  -- nu o face nimeni.
  periodField d = case d.claimedPeriod of
    Nothing -> []
    Just period ->
      [ HH.div_
          [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Period claimed" ]
          , HH.dd_
              [ HH.text (maybe "—" identity (bounds period))
              , HH.span [ HP.class_ (HH.ClassName "opacity-60") ]
                  [ HH.text " — self-reported, nothing on chain establishes it." ]
              ]
          ]
      ]
    where
    bounds p = case p of
      [ from, to ] -> Just (formatDay from <> " → " <> formatDay to)
      _ -> Nothing

  challenges (AttestationDetail d) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text "Challenges" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text
                  "An objection with a deposit locked until it closes. The deposit comes back on \
                  \every outcome, so contesting costs network fees and nothing else. A challenged \
                  \claim is shown beside its challenge, not instead of it."
              ]
          , if null d.disputes then
              HH.p [ HP.class_ (HH.ClassName "text-sm") ]
                [ HH.text "Nobody has challenged this. That is the quiet case, not an empty one." ]
            else HH.ul [ HP.class_ (HH.ClassName "space-y-1") ] (map challenge d.disputes)
          ]
      ]

  challenge (DisputeRow c) =
    HH.li [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2 text-sm") ]
      [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> verdictClass c.verdict)) ]
          [ HH.text (fromMaybe "still open" c.verdict) ]
      -- Numele duce la pagina provocării. Pînă acum provocarea se vedea aici dar nu se putea
      -- deschide: ca să-i citești motivarea trebuia să te întorci în listă și să o cauți.
      , HH.a
          [ HP.href (disputeDetailHrefFor c.id)
          , HP.class_ (HH.ClassName "link link-hover font-medium")
          ]
          [ HH.text c.name ]
      , HH.span [ HP.class_ (HH.ClassName "font-mono opacity-70") ] [ HH.text (formatAda c.deposit) ]
      , HH.span [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text ("opened " <> formatDay c.openedAt) ]
      , case c.verdict of
          Nothing ->
            HH.span [ HP.class_ (HH.ClassName "opacity-60") ]
              [ HH.text ("· anyone may close it after " <> formatDay c.staleAfter) ]
          Just _ -> HH.text ""
      ]
