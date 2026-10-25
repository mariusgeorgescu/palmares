-- | Root component: subscribes to the path-based router, mounts the NavBar,
-- | and renders the active page in the main slot.
module Components.Home
  ( component
  ) where

import Prelude

import Capabilities.Delay (class MonadDelay)
import Capabilities.DomEvent (class MonadDomEvent)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov)
import Cardano.Capabilities.Wallet.MonadCIP30 (class MonadCIP30)
import Components.Explorer.Dashboard as Dashboard
import Components.Layout.NavBar as NavBar
import Components.Shared.StatusChip as StatusChip
import Data.Const (Const)
import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter, emitMatched)
import Halogen.Store.Monad (class MonadStore)
import Route (Route(..))
import Route.Codec (printRoute)
import Store as Store

type Input = Unit
type Output = Void

type Query :: forall k. k -> Type
type Query = Const Void

type State = { route :: Route }

data Action
  = Initialize
  | RouteChanged Route
  | HandleNavBar NavBar.Output

type Slots =
  ( navbar :: NavBar.Slot
  , statusChip :: StatusChip.Slot
  , dashboard :: Dashboard.Slot
  )

component
  :: forall m
   . MonadAff m
  => MonadCIP30 m
  => MonadDomEvent m
  => MonadDelay m
  => MonadRouter Route m
  => MonadStore Store.Action Store.Store m
  => MonadQueryGov m
  => H.Component Query Input Output m
component =
  H.mkComponent
    { initialState: const { route: Home }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  handleAction = case _ of
    Initialize -> do
      emitter <- emitMatched
      _ <- H.subscribe (RouteChanged <$> emitter)
      pure unit
    RouteChanged route -> H.modify_ _ { route = route }
    HandleNavBar _ -> pure unit

  render st =
    HH.div [ HP.class_ (HH.ClassName "min-h-screen bg-base-100") ]
      [ HH.slot NavBar._navbar unit NavBar.component unit HandleNavBar
      -- Chip-ul stă în afara slotului de rută, nu în fiecare pagină: prospețimea e o proprietate a
      -- datelor, nu a ecranului, și un singur apel o acoperă pe toate.
      , HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 pt-4") ]
          [ HH.slot_ StatusChip._statusChip unit StatusChip.component unit ]
      , HH.main [ HP.class_ (HH.ClassName "min-h-[80vh]") ]
          [ renderRoute st.route ]
      ]

  renderRoute = case _ of
    Home -> HH.slot_ Dashboard._dashboard unit Dashboard.component unit
    NotFound -> renderNotFound

  renderNotFound =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto p-12 text-center space-y-4") ]
      [ HH.h1 [ HP.class_ (HH.ClassName "text-4xl font-bold") ] [ HH.text "Not found" ]
      , HH.p_ [ HH.text "That route doesn't exist." ]
      , HH.a
          [ HP.href (printRoute Home)
          , HP.class_ (HH.ClassName "btn btn-primary")
          ]
          [ HH.text "Go home" ]
      ]
