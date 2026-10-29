-- | Sticky top navbar: brand + route links + wallet connect.
-- |
-- | Slotuiește `Components.WalletConnectComponent` și RAPORTEAZĂ conectarea mai sus, cu cheia
-- | wallet-ului. Nu decide nimic despre ea: ce poate face un wallet pe lanțul ăsta e politica
-- | învelișului, iar o bară de navigare care ar negocia extensii de guvernanță ar fi al doilea loc
-- | din aplicație care știe ce înseamnă „poate scrie".
module Components.Layout.NavBar
  ( Slot
  , _navbar
  , Query
  , Output(..)
  , Input
  , component
  ) where

import Prelude

import Data.Foldable (any)
import Data.Tuple (Tuple(..))

import Capabilities.Delay (class MonadDelay)
import Capabilities.DomEvent (class MonadDomEvent, preventDefaultEvent)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov)
import Cardano.Capabilities.Wallet.MonadCIP30 (class MonadCIP30)
import Components.Layout.SearchBox as SearchBox
import Components.WalletConnectComponent as WC
import Components.WalletConnectComponent (FiatOnrampBehavior(..), RenderMode(..))
import Components.Shared.DRepIdentity (shortId)
import Format (enumLabel)
import Halogen.Store.Monad (class MonadStore, emitSelected, getStore)
import Halogen.Store.Select (selectAll)
import Capabilities.Query.Gov.Types (ProfileRow(..))
import Network.RemoteData (RemoteData(..))
import Store as Store
import Cardano.Wallet.Cip30 (WalletName)
import Data.Const (Const)
import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter, navigate)
import Route (Route(..), section)
import Route.Codec (printRoute)
import Route.GovQueries
  ( defaultVoteFilters
  , emptyDRepFilters
  , emptyGovActionFilters
  , emptyMethodologyFilters
  , emptySpoFilters
  , emptyWithdrawalFilters
  , emptyDelegationFilters
  , emptyActivityFilters
  , emptyRegistryFilters
  , emptyGraphFilters
  , emptyWriteFilters
  )
import Type.Proxy (Proxy(..))
import Web.UIEvent.MouseEvent (MouseEvent, toEvent)

type Slot = H.Slot Query Output Unit

_navbar :: Proxy "navbar"
_navbar = Proxy

type Input = Route

type Query :: forall k. k -> Type
type Query = Const Void

data Output
  -- | Cheia CIP-30 a wallet-ului conectat — `lace`, `eternl` —, nu numele afișat.
  = WalletConnected WalletName
  | WalletDisconnected
  -- | S-a ales un profil din comutator. Identitatea cu care lucrezi e a sesiunii, nu a unui
  -- | formular — învelișul o pune în `Store` și toate ecranele o citesc de acolo.
  | ProfileSelected String
  | CreateProfileRequested
  | MyProfileRequested
  -- | `enable` a eșuat, cel mai des pentru că omul a închis prompt-ul wallet-ului. E un
  -- | rezultat, nu o eroare, și trebuie SPUS: altfel butonul arată ca unul mort.
  | WalletConnectFailed String

type Slots =
  ( walletConnectComponent :: WC.Slot
  , searchBox :: SearchBox.Slot
  )

type State =
  { route :: Route
  -- Oglinda a ce deține portofelul și cu ce profil lucrezi. `render` nu poate citi din `Store`
  -- (e pur), deci oglinda stă în stare — aceeași cusătură ca în ecranul de scriere.
  , owned :: Array ProfileRow
  , active :: Maybe ProfileRow
  -- Meniul de pe telefon e controlat din stare, nu din `<details>`: un `details` necontrolat rămâne
  -- deschis după ce navighezi, pentru că nodul DOM supraviețuiește schimbării de rută.
  , menuOpen :: Boolean
  }

data Action
  = Initialize
  | NavLinkClicked Route MouseEvent
  | Receive Input
  | ToggleMenu
  | StoreChanged Store.Store
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
    { initialState: \route -> { route, owned: [], active: Nothing, menuOpen: false }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
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
    HH.nav
      [ HP.class_ (HH.ClassName "navbar bg-base-200 shadow-sm sticky top-0 z-30 flex-wrap gap-y-1")
      , HP.attr (HH.AttrName "aria-label") "Main"
      ]
      -- FĂRĂ `min-w-0` aici, și e intenționat: cu el, containerul mărcii se micșora la 52px în timp
      -- ce linkul dinăuntru rămânea 103px (un `btn` nu-și rupe textul), iar hamburgerul se desena
      -- PESTE cuvântul „Testatum". Fără el, marca își ține lățimea și ce nu mai încape trece pe
      -- rândul al doilea — ceea ce e tot ce voiam de la `flex-wrap`.
      [ HH.div [ HP.class_ (HH.ClassName "flex-1") ]
          [ HH.a
              [ HP.href (printRoute Home)
              , HE.onClick (NavLinkClicked Home)
              , HP.class_ (HH.ClassName "btn btn-ghost text-xl normal-case px-2")
              ]
              [ HH.text "Testatum" ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex-none flex items-center gap-1 sm:gap-2") ]
          [ menuButton st
          , HH.ul [ HP.class_ (HH.ClassName "menu menu-horizontal px-1 hidden lg:flex") ] desktopItems
          , HH.slot_ SearchBox._searchBox unit SearchBox.component unit
          , HH.slot WC._walletConnect unit WC.component (walletConnectInput st) HandleWalletConnect
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
    -- Bara orizontală ține patru destinații plus „More" și metodologia. Ecranele nu se opresc
    -- aici — urmează activitatea, profilurile, atestările, disputele — iar o bară care le
    -- înșiruie pe toate se rupe pe al doilea rând exact pe lățimile de laptop. Pe telefon nu
    -- există submeniu: hamburgerul le listează plat, pentru că acolo e deja o coloană care se
    -- derulează și un al doilea nivel ar cere două atingeri pentru fiecare ecran.
    -- Ordinea barei e ordinea produsului: registrul întâi, explorerul de guvernanță al doilea.
    -- Înainte era invers, și un vizitator care citea doar bara pleca cu impresia că site-ul e un
    -- explorer de guvernanță care are și niște profiluri pe undeva.
    primaryItems =
      [ navLink st.route Home "Home"
      , navLink st.route (ProfileList emptyRegistryFilters) "Profiles"
      , navLink st.route (AttestationList emptyRegistryFilters) "Vouches"
      , navLink st.route (DisputeList emptyRegistryFilters) "Challenges"
      -- Scrierea stă în linie: e singura secțiune care schimbă ceva, iar dacă cineva o caută și
      -- n-o găsește, concluzia e că produsul doar citește.
      , navLink st.route (Write emptyWriteFilters) "Actions"
      ]

    desktopItems =
      primaryItems
        <> [ moreMenu st ]
        <> [ navLink st.route (Methodology emptyMethodologyFilters) "Methodology" ]

    navItems =
      primaryItems
        <> map (\(Tuple r label) -> navLink st.route r label) (moreTargetsOf st)
        <> [ navLink st.route (Methodology emptyMethodologyFilters) "Methodology" ]

  -- `details`/`summary`, nu un dropdown cu stare: se deschide și se închide fără JavaScript, e
  -- navigabil de la tastatură din construcție, și nu adaugă un al doilea `menuOpen` care poate
  -- rămâne desincronizat de ruta curentă.
  moreMenu st =
    HH.li_
      [ HH.details_
          [ HH.summary
              [ HP.class_
                  ( HH.ClassName
                      (if anyActive st then "font-semibold text-primary" else "")
                  )
              ]
              -- „More" nu spunea nimic despre ce e înăuntru. „Governance" spune, și e și
              -- distincția care contează: ce e în meniu e explorerul, ce e în linie e registrul.
              [ HH.text "Governance" ]
          , HH.ul [ HP.class_ (HH.ClassName "bg-base-200 rounded-box z-40 w-48 p-2 shadow") ]
              (map (\(Tuple r label) -> navLink st.route r label) (moreTargetsOf st))
          ]
      ]

  moreTargetsOf _ =
    [ Tuple (DRepList emptyDRepFilters) "Representatives"
    , Tuple (SpoList emptySpoFilters) "Stake pools"
    , Tuple Committee "Committee"
    , Tuple (ActionList emptyGovActionFilters) "Proposals"
    , Tuple (VoteList defaultVoteFilters) "Votes"
    , Tuple (TreasuryList emptyWithdrawalFilters) "Treasury"
    , Tuple (DelegationList emptyDelegationFilters) "Delegations"
    , Tuple (Graph emptyGraphFilters) "Delegation graph"
    , Tuple (Activity emptyActivityFilters) "Activity"
    ]

  -- „More" se marchează când ecranul curent e unul dintre cele dinăuntru: altfel bara nu spune
  -- unde te afli exact pe jumătate din site.
  anyActive st =
    any (\(Tuple r _) -> sameSection st.route r) (moreTargetsOf st)

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
  walletConnectInput :: State -> WC.Input
  walletConnectInput st =
    { buttons: []
    -- Cele patru erau string-uri goale, adică patru sloturi goale pe deploy. Fișierele vin din
    -- `bjj-frontend/public/images`, care le avea de mult — lipsea doar copierea lor.
    , assets:
        { connectIcon: "/images/walletsymbol.svg"
        , disconnectIcon: "/images/disconnectsymbol.svg"
        , onrampIcon: "/images/onramp.svg"
        , copyIcon: "/images/copy-icon.svg"
        }
    -- `Unified`, nu `Standalone`: widget-ul devine și comutatorul de profil, iar asta e tot rostul —
    -- „cu ce identitate lucrez" se alege o dată, sus, și o știe toată aplicația. Cît timp nu e
    -- niciun portofel conectat, biblioteca randează oricum butonul de conectare (`Standalone`).
    --
    -- `thumbnailUri` e o iconiță LOCALĂ, nu imaginea pe care profilul o pretinde: n-avem poartă
    -- IPFS, iar o imagine încărcată de pe gazda altcuiva ar trimite IP-ul vizitatorului acolo —
    -- vezi `Format.imageRef`. Ce pretinde profilul se vede pe pagina lui, ca adresă.
    , renderMode: Unified
        { profiles: map profileInfo st.owned
        , activeProfile: map profileInfo st.active
        , actions:
            [ { id: myProfileAction
              , label: "My profile"
              , iconSrc: "/images/sidebar/practitioners.svg"
              , classes: []
              }
            ]
        , pendingCount: 0
        , createProfileLabel: "Claim a profile"
        }
    , utxosConfig: Nothing
    , fiatOnramp: FiatOnrampDefault Nothing
    }

  -- Ce arată widget-ul despre un profil. Subtitlul e felul de actor plus id-ul scurtat: două
  -- profiluri pot avea același nume, iar id-ul e singurul lucru care le deosebește.
  profileInfo (ProfileRow r) =
    { id: r.id
    , name: r.name
    , subtitle: enumLabel r.kind <> " · " <> shortId r.id
    , thumbnailUri: "/images/fingerprint.svg"
    }

  handleAction = case _ of
    -- FĂRĂ ASTA WIDGET-UL NU VEDE NICIUN WALLET, oricâte ar fi instalate.
    --
    -- Componenta de wallet nu enumeră extensiile la montare: singurul loc unde își umple
    -- `availableWalletExtensions` e `handleQuery (SetWalletApi …)`. Deci lista rămâne goală până
    -- când gazda îi trimite întrebarea aceea — iar palmares n-o trimitea niciodată, fiindcă
    -- `NavBar` n-avea deloc `initialize`. Rezultatul, pe deploy: bara de sus scria „You do not have
    -- any wallet installed yet !" în timp ce `/write` conecta același wallet fără probleme, fiindcă
    -- ecranul acela nu folosește componenta, ci `getAvailableWallets` direct din `purescript-cip30`.
    --
    -- `bjj-frontend` o trimite în propriul `Initialize`, și de aceea la el merge. Aceeași bibliotecă,
    -- aceeași versiune de API, doar că acolo cineva a chemat întrebarea.
    --
    -- `Nothing`: la montare nu există încă nicio conexiune. Interogarea nu e despre API, e despre
    -- efectul ei secundar — enumerarea.
    Initialize -> do
      store <- getStore
      H.modify_ _ { owned = ownedRows store.owned, active = store.active }
      emitter <- emitSelected selectAll
      void (H.subscribe (StoreChanged <$> emitter))
      void (H.tell WC._walletConnect unit (WC.SetWalletApi Nothing))

    StoreChanged store ->
      H.modify_ _ { owned = ownedRows store.owned, active = store.active }

    NavLinkClicked route ev -> do
      preventDefaultEvent (toEvent ev)
      -- Meniul de telefon se închide la navigare. Fără asta rămâne deschis peste ecranul nou.
      H.modify_ _ { menuOpen = false }
      navigate route
    Receive route -> H.modify_ _ { route = route }
    ToggleMenu -> H.modify_ \st -> st { menuOpen = not st.menuOpen }
    HandleWalletConnect WC.WalletConnectedEvent -> do
      -- Cheia, nu numele afișat: învelișul reia `enable` cu extensiile de guvernanță, iar
      -- `enable` cere cheia. Componenta o păstrează de acum (`GetConnectedWalletKey`); înainte
      -- dădea doar ce întorsese `getName`, iar inversarea acelei funcții era o ghicitoare cînd
      -- două extensii raportau același nume.
      mKey <- H.request WC._walletConnect unit WC.GetConnectedWalletKey
      case mKey >>= identity of
        Just key -> H.raise (WalletConnected key)
        Nothing -> pure unit
    HandleWalletConnect WC.WalletDisconnectedEvent -> H.raise WalletDisconnected
    HandleWalletConnect (WC.ProfileSelectedEvent pid) -> H.raise (ProfileSelected pid)
    HandleWalletConnect WC.CreateProfileEvent -> H.raise CreateProfileRequested
    HandleWalletConnect (WC.ActionItemEvent aid)
      | aid == myProfileAction -> H.raise MyProfileRequested
      | otherwise -> pure unit
    HandleWalletConnect (WC.WalletConnectFailedEvent detail) -> H.raise (WalletConnectFailed detail)
    -- Other WC outputs (custom buttons, profile/action events, fiat on-ramp,
    -- copy address) are no-ops in the template — extend as your dApp grows.
    HandleWalletConnect _ -> pure unit

-- | Două rute sunt în aceeași secțiune dacă bara de navigare trebuie să le marcheze la fel.
-- | Maparea e `Route.section`, singurul loc unde se scrie în ce secțiune cade o rută.
sameSection :: Route -> Route -> Boolean
sameSection a b = section a == section b

-- | Id-ul singurei acțiuni din comutator. Un șir, fiindcă așa îl cere biblioteca; o constantă,
-- | fiindcă altfel ar fi scris de două ori și comparat o dată.
myProfileAction :: String
myProfileAction = "my-profile"

-- | Rîndurile deținute, din starea lor de încărcare. Cît timp se citesc sau n-au putut fi citite,
-- | comutatorul n-are ce arăta — iar un comutator gol e mai onest decît unul care clipește.
ownedRows :: RemoteData String (Array ProfileRow) -> Array ProfileRow
ownedRows = case _ of
  Success rows -> rows
  _ -> []
