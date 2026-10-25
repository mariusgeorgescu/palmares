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

import Capabilities.Delay (class MonadDelay)
import Capabilities.DomEvent (class MonadDomEvent, preventDefaultEvent)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov)
import Cardano.Capabilities.Wallet.MonadCIP30 (class MonadCIP30)
import Components.Layout.SearchBox as SearchBox
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
import Route.GovQueries
  ( defaultVoteFilters
  , emptyDRepFilters
  , emptyGovActionFilters
  , emptyMethodologyFilters
  )
import Store as Store
import Type.Proxy (Proxy(..))
import Web.UIEvent.MouseEvent (MouseEvent, toEvent)

type Slot = H.Slot Query Output Unit

_navbar :: Proxy "navbar"
_navbar = Proxy

type Input = Route

type Query :: forall k. k -> Type
type Query = Const Void

data Output
  = WalletConnected
  | WalletDisconnected

type Slots =
  ( walletConnectComponent :: WC.Slot
  , searchBox :: SearchBox.Slot
  )

type State =
  { route :: Route
  -- Meniul de pe telefon e controlat din stare, nu din `<details>`: un `details` necontrolat rămâne
  -- deschis după ce navighezi, pentru că nodul DOM supraviețuiește schimbării de rută.
  , menuOpen :: Boolean
  }

data Action
  = NavLinkClicked Route MouseEvent
  | Receive Input
  | ToggleMenu
  | HandleWalletConnect WC.Output

component
  :: forall m
   . MonadAff m
  => MonadCIP30 m
  => MonadDomEvent m
  => MonadDelay m
  => MonadQueryGov m
  => MonadRouter Route m
  => MonadStore Store.Action Store.Store m
  => H.Component Query Input Output m
component =
  H.mkComponent
    { initialState: \route -> { route, menuOpen: false }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , receive = Just <<< Receive
        }
    }
  where
  -- `flex-wrap` nu e decor. Măsurat la 390px: marcă 119px + cele cinci linkuri + căutare 176px +
  -- butonul de wallet 160px se terminau la x=505 pe un ecran de 390 — adică toată pagina derula
  -- orizontal, pe FIECARE ecran, pentru că bara e în shell. Linkurile intră într-un meniu de
  -- telefon, câmpul de căutare se îngustează, iar ce tot nu încape trece pe al doilea rând în loc
  -- să iasă din ecran.
  render st =
    HH.div [ HP.class_ (HH.ClassName "navbar bg-base-200 shadow-sm sticky top-0 z-30 flex-wrap gap-y-1") ]
      -- FĂRĂ `min-w-0` aici, și e intenționat: cu el, containerul mărcii se micșora la 52px în timp
      -- ce linkul dinăuntru rămânea 103px (un `btn` nu-și rupe textul), iar hamburgerul se desena
      -- PESTE cuvântul „Palmares". Fără el, marca își ține lățimea și ce nu mai încape trece pe
      -- rândul al doilea — ceea ce e tot ce voiam de la `flex-wrap`.
      [ HH.div [ HP.class_ (HH.ClassName "flex-1") ]
          [ HH.a
              [ HP.href (printRoute Home)
              , HE.onClick (NavLinkClicked Home)
              , HP.class_ (HH.ClassName "btn btn-ghost text-xl normal-case px-2")
              ]
              [ HH.text "Palmares" ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex-none flex items-center gap-1 sm:gap-2") ]
          [ menuButton st
          , HH.ul [ HP.class_ (HH.ClassName "menu menu-horizontal px-1 hidden lg:flex") ] navItems
          , HH.slot_ SearchBox._searchBox unit SearchBox.component unit
          , HH.slot WC._walletConnect unit WC.component walletConnectInput HandleWalletConnect
          ]
      , if st.menuOpen then
          HH.ul
            [ HP.class_ (HH.ClassName "menu bg-base-200 w-full rounded-box lg:hidden")
            , HP.id "navbar-menu"
            ]
            navItems
        else HH.text ""
      ]
    where
    navItems =
      [ navLink st.route Home "Home"
      , navLink st.route (DRepList emptyDRepFilters) "DReps"
      , navLink st.route (ActionList emptyGovActionFilters) "Actions"
      , navLink st.route (VoteList defaultVoteFilters) "Votes"
      , navLink st.route (Methodology emptyMethodologyFilters) "Methodology"
      ]

  menuButton st =
    HH.button
      [ HP.class_ (HH.ClassName "btn btn-ghost btn-sm lg:hidden")
      , HP.type_ HP.ButtonButton
      , HE.onClick (const ToggleMenu)
      , HP.attr (HH.AttrName "aria-expanded") (if st.menuOpen then "true" else "false")
      , HP.attr (HH.AttrName "aria-controls") "navbar-menu"
      , HP.attr (HH.AttrName "aria-label") "Main menu"
      ]
      -- Hamburgerul e desenat din trei linii, nu luat dintr-un pachet de iconițe: trei `div`-uri
      -- costă zero kilobytes și nu adaugă o dependență pentru o formă de 16px.
      [ HH.div [ HP.class_ (HH.ClassName "flex flex-col gap-1") ]
          [ bar, bar, bar ]
      ]

  bar = HH.div [ HP.class_ (HH.ClassName "w-4 h-0.5 bg-current rounded") ] []

  -- Secțiunea activă se vede. Un link de detaliu de DRep marchează „DReps": pagina aceea E în
  -- secțiunea aceea, iar cineva care se uită în bară vrea să știe unde se află, nu pe ce a dat clic.
  navLink currentRoute route label =
    HH.li_
      [ HH.a
          [ HP.href (printRoute route)
          , HE.onClick (NavLinkClicked route)
          , HP.class_
              ( HH.ClassName
                  ( if sameSection currentRoute route then "menu-active font-semibold text-primary"
                    else ""
                  )
              )
          , HP.attr (HH.AttrName "aria-current")
              (if sameSection currentRoute route then "page" else "false")
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
      -- Meniul de telefon se închide la navigare. Fără asta rămâne deschis peste ecranul nou.
      H.modify_ _ { menuOpen = false }
      navigate route
    Receive route -> H.modify_ _ { route = route }
    ToggleMenu -> H.modify_ \st -> st { menuOpen = not st.menuOpen }
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

-- | Două rute sunt în aceeași secțiune dacă bara de navigare trebuie să le marcheze la fel.
-- | Detaliul unui DRep aparține secțiunii „DReps", iar filtrele nu schimbă secțiunea.
sameSection :: Route -> Route -> Boolean
sameSection a b = section a == section b
  where
  section = case _ of
    Home -> "home"
    DRepList _ -> "dreps"
    DRepDetail _ -> "dreps"
    ActionList _ -> "actions"
    ActionDetail _ -> "actions"
    VoteList _ -> "votes"
    Methodology _ -> "methodology"
    NotFound -> "none"
