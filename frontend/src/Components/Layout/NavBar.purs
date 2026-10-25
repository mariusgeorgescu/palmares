-- | Sticky top navbar: brand + route links + wallet connect.
-- |
-- | Slots `Components.WalletConnectComponent` and mirrors connect/disconnect
-- | events into the global Store so any component can read `walletApi`.
module Components.Layout.NavBar
  ( Slot
  , _navbar
  , Query
  , Output(..)
  , Input
  , component
  ) where

import Prelude

import Capabilities.DomEvent (class MonadDomEvent, preventDefaultEvent)
import Cardano.Capabilities.Wallet.MonadCIP30 (class MonadCIP30)
import Components.WalletConnectComponent as WC
import Components.WalletConnectComponent (FiatOnrampBehavior(..), RenderMode(..))
import Data.Const (Const)
import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter, navigate)
import Halogen.Store.Monad (class MonadStore, updateStore)
import Route (Route(..))
import Route.Codec (printRoute)
import Route.GovQueries (defaultVoteFilters, emptyDRepFilters, emptyGovActionFilters)
import Store as Store
import Type.Proxy (Proxy(..))
import Web.UIEvent.MouseEvent (MouseEvent, toEvent)

type Slot = H.Slot Query Output Unit

_navbar :: Proxy "navbar"
_navbar = Proxy

type Input = Unit

type Query :: forall k. k -> Type
type Query = Const Void

data Output
  = WalletConnected
  | WalletDisconnected

type Slots = (walletConnectComponent :: WC.Slot)

type State = Unit

data Action
  = NavLinkClicked Route MouseEvent
  | HandleWalletConnect WC.Output

component
  :: forall m
   . MonadAff m
  => MonadCIP30 m
  => MonadDomEvent m
  => MonadRouter Route m
  => MonadStore Store.Action Store.Store m
  => H.Component Query Input Output m
component =
  H.mkComponent
    { initialState: const unit
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        }
    }
  where
  render _ =
    HH.div [ HP.class_ (HH.ClassName "navbar bg-base-200 shadow-sm sticky top-0 z-30") ]
      [ HH.div [ HP.class_ (HH.ClassName "flex-1") ]
          [ HH.a
              [ HP.href (printRoute Home)
              , HE.onClick (NavLinkClicked Home)
              , HP.class_ (HH.ClassName "btn btn-ghost text-xl normal-case")
              ]
              [ HH.text "Palmares" ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex-none gap-2") ]
          [ HH.ul [ HP.class_ (HH.ClassName "menu menu-horizontal px-1") ]
              [ navLink Home "Home"
              , navLink (DRepList emptyDRepFilters) "DReps"
              , navLink (ActionList emptyGovActionFilters) "Actions"
              , navLink (VoteList defaultVoteFilters) "Votes"
              ]
          , HH.slot WC._walletConnect unit WC.component walletConnectInput HandleWalletConnect
          ]
      ]

  navLink route label =
    HH.li_
      [ HH.a
          [ HP.href (printRoute route)
          , HE.onClick (NavLinkClicked route)
          ]
          [ HH.text label ]
      ]

  -- No custom buttons; rely on the component's built-in connect/disconnect UI.
  -- Icon URLs are intentionally empty — wire your own SVG/PNG paths once you
  -- have brand assets in `public/`.
  -- RenderMode.Standalone keeps the connect button independent of any profile
  -- system; FiatOnrampDefault Nothing hides the fiat-on-ramp item.
  walletConnectInput :: WC.Input
  walletConnectInput =
    { buttons: []
    , assets:
        { connectIcon: ""
        , disconnectIcon: ""
        , onrampIcon: ""
        , copyIcon: ""
        }
    , renderMode: Standalone
    , utxosConfig: Nothing
    , fiatOnramp: FiatOnrampDefault Nothing
    }

  handleAction = case _ of
    NavLinkClicked route ev -> do
      preventDefaultEvent (toEvent ev)
      navigate route
    HandleWalletConnect WC.WalletConnectedEvent -> do
      -- Pull the API out of the child component and stash it in the Store so any
      -- consumer can call CIP-30 operations against it.
      mApi <- H.request WC._walletConnect unit WC.GetWalletApi
      case mApi >>= identity of
        Just api -> do
          updateStore (Store.Connect api)
          H.raise WalletConnected
        Nothing -> pure unit
    HandleWalletConnect WC.WalletDisconnectedEvent -> do
      updateStore Store.Disconnect
      H.raise WalletDisconnected
    -- Other WC outputs (custom buttons, profile/action events, fiat on-ramp,
    -- copy address) are no-ops in the template — extend as your dApp grows.
    HandleWalletConnect _ -> pure unit
