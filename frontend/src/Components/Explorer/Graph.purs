-- | Graful delegărilor în jurul unui DRep: `GET /delegations?drep_id=…`.
-- |
-- | Ecranul răspunde la o întrebare pe care un tabel o răspunde prost: __cine stă în spatele
-- | acestei puteri de vot__. Un tabel de 300 de adrese de stake e o listă; aceeași informație ca
-- | stea arată dintr-o privire dacă puterea vine de la mulți delegatori mici sau de la trei mari.
-- |
-- | Fără un DRep ales graful n-are centru, deci nu se desenează unul gol: se explică la ce e și se
-- | dă drumul spre listă.
-- |
-- | Partea care decide CE se desenează — `buildGraph` — e pură și testată. Cytoscape primește doar
-- | noduri și muchii gata făcute.
module Components.Explorer.Graph
  ( Slot
  , Output
  , _graph
  , component
  , buildGraph
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDelegations)
import Capabilities.Query.Gov.Types (DelegationPage(..), DelegationRow(..))
import Components.Graph.FFI (GraphEdge, GraphInstance, GraphNode, destroyGraph, initGraph, setElements)
import Components.Shared.DRepIdentity (shortId)
import Data.Array (concatMap, length, nub, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Effect.Class (class MonadEffect, liftEffect)
import Format (formatAdaOnly, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Route (Route)
import Route.GovQueries (GraphFilters, drepDetailHrefFor, drepListPath)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_graph :: Proxy "graph"
_graph = Proxy

type Input = GraphFilters

type State =
  { filters :: GraphFilters
  , page :: RemoteData ApiError DelegationPage
  , instance :: Maybe GraphInstance
  }

data Action
  = Initialize
  | Finalize
  | Retry
  | Receive Input

-- | Din delegările unui DRep, nodurile și muchiile grafului.
-- |
-- | Rădăcina e DREP-ul, nu primul delegator: graful are un centru pentru că întrebarea are unul.
-- | Un delegator care apare de două ori — a delegat, a schimbat, a revenit — devine UN nod, altfel
-- | steaua ar număra oameni de două ori și ar arăta mai largă decât e.
buildGraph :: String -> Array DelegationRow -> { nodes :: Array GraphNode, edges :: Array GraphEdge }
buildGraph drepId rows =
  { nodes: map nodeOf (nub ([ drepId ] <> concatMap endpoints rows))
  , edges: map edgeOf rows
  }
  where
  -- AMBELE capete ale fiecărui rînd devin noduri, nu doar delegatorii. Altfel un rînd care arată
  -- spre altceva decît rădăcina produce o muchie fără țintă, iar Cytoscape aruncă „Can not create
  -- edge with nonexistant target" și rupe tot ciclul de inițializare al paginii — inclusiv
  -- titlul documentului, care se pune în aceeași secvență. Măsurat exact așa.
  endpoints (DelegationRow d) = [ d.stakeAddress, d.target ]

  nodeOf i = { id: i, label: shortId i, isRoot: i == drepId }

  -- Eticheta muchiei e suma, în ADA fără unitate: unitatea se scrie o dată, în legenda de sub graf,
  -- pentru că altfel „ADA" apare de trei sute de ori peste desen.
  edgeOf (DelegationRow d) =
    { id: d.stakeAddress <> "->" <> d.target
    , source: d.stakeAddress
    , target: d.target
    , label: maybe "" formatAdaOnly d.lovelace
    }

component
  :: forall q m
   . MonadQueryGov m
  => MonadEffect m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, page: NotAsked, instance: Nothing }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , finalize = Just Finalize
        , receive = Just <<< Receive
        }
    }
  where
  handleAction = case _ of
    Initialize -> load
    Retry -> load
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters }
        load
    -- Cytoscape ține un observer de redimensionare și un canvas. Fără `destroy` la ieșire, fiecare
    -- vizită pe ecran lasă în urmă unul.
    Finalize -> do
      st <- H.get
      case st.instance of
        Nothing -> pure unit
        Just cy -> liftEffect (destroyGraph cy)

  load = do
    st <- H.get
    case st.filters.drep of
      Nothing -> H.modify_ _ { page = NotAsked }
      Just drepId -> do
        H.modify_ _ { page = Loading }
        res <- getDelegations
          { drep_id: Just drepId
          , is_current: Just "true"
          , order_by: Just "lovelace"
          , sort_order: Just "desc"
          , limit: Just "200"
          , offset: Nothing
          }
        case res of
          Left e -> H.modify_ _ { page = Failure e }
          Right p -> do
            H.modify_ _ { page = Success p }
            draw drepId p

  -- Desenul se face DUPĂ ce starea e pusă, ca elementul să existe deja în DOM. `getHTMLElementRef`
  -- întoarce `Nothing` dacă ecranul s-a schimbat între timp, și atunci nu e nimic de desenat.
  draw drepId (DelegationPage p) = do
    mEl <- H.getHTMLElementRef canvasRef
    case mEl of
      Nothing -> pure unit
      Just el -> do
        st <- H.get
        cy <- case st.instance of
          Just existing -> pure existing
          Nothing -> do
            fresh <- liftEffect (initGraph el)
            H.modify_ _ { instance = Just fresh }
            pure fresh
        let g = buildGraph drepId p.items
        liftEffect (setElements cy g.nodes g.edges)

  canvasRef = H.RefLabel "graph-canvas"

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Delegation graph" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "Who stands behind a representative's voting power. The same rows as the \
                  \delegations table, drawn as a star, which answers at a glance whether the power \
                  \comes from many small holders or a few large ones."
              ]
          ]
      , case st.filters.drep of
          Nothing -> noRoot
          Just drepId -> withRoot st drepId
      ]

  -- Un graf fără centru nu e un graf gol, e o întrebare incompletă — deci se spune ce lipsește și
  -- se dă drumul exact spre locul de unde se alege.
  noRoot =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
          [ HH.p_ [ HH.text "Pick a representative first — the graph is drawn around one." ]
          , HH.a [ HP.href drepListPath, HP.class_ (HH.ClassName "btn btn-sm btn-primary") ]
              [ HH.text "Browse DReps" ]
          ]
      ]

  withRoot st drepId =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-3") ]
          [ HH.a
              [ HP.href (drepDetailHrefFor drepId)
              , HP.class_ (HH.ClassName "link link-hover font-mono text-sm")
              ]
              [ HH.text (shortId drepId) ]
          , case st.page of
              Success (DelegationPage p) ->
                HH.span [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                  [ HH.text (pluralize (length p.items) "current delegator" <> " drawn") ]
              _ -> HH.text ""
          ]
      , case st.page of
          Failure e -> failure e
          Success (DelegationPage p) | null p.items -> noDelegators
          _ -> HH.text ""
      -- Pînza rămîne în DOM în toate stările: Cytoscape se agață de un element care trebuie să
      -- existe cînd sosește răspunsul, iar un `if` care o scoate cît timp se încarcă ar face ca
      -- primul desen să n-aibă unde să se facă.
      , HH.div
          [ HP.ref canvasRef
          , HP.class_ (HH.ClassName "card bg-base-200 w-full h-[32rem]")
          ]
          []
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text "Edge labels are the delegated amount in ADA. Only delegations still in force are drawn." ]
      ]

  noDelegators =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "This representative has no delegations in force." ] ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The graph could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]
