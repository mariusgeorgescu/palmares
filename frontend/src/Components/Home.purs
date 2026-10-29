-- | Root component: subscribes to the path-based router, mounts the NavBar,
-- | and renders the active page in the main slot.
-- |
-- | Învelișul ține DOUĂ lucruri care nu pot trăi într-un ecran, fiindcă supraviețuiesc navigării:
-- |
-- |   * __politica de wallet.__ Bara de sus raportează ce s-a conectat, aici se negociază poarta
-- |     de guvernanță (CIP-95/142) o dată, și rezultatul intră în `Store`. Toate ecranele citesc
-- |     de acolo, deci nu mai există două stări de wallet care se contrazic;
-- |   * __urmărirea tranzacțiilor trimise.__ Confirmarea vine în minute, iar omul pleacă de pe
-- |     ecranul de scriere între timp. Un ecran care și-ar urmări singur tranzacția ar pierde chiar
-- |     răspunsul pentru care a așteptat, fiindcă starea lui moare la demontare.
module Components.Home
  ( component
  ) where

import Prelude

import Capabilities.Delay (class MonadDelay, delayMs)
import Capabilities.DomEvent (class MonadDomEvent)
import AppEnv (Env)
import Capabilities.Interaction.MonadInteract (class MonadInteract, txStatus)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov)
import Capabilities.Wallet.Governance (class MonadGovWallet, BlockReason(..), GateVerdict(..), blockMessage, connectGovernance)
import Control.Monad.Reader (class MonadAsk)
import Cardano.Capabilities.Wallet.MonadCIP30 (class MonadCIP30)
import Components.Explorer.Committee as Committee
import Components.Explorer.Activity as Activity
import Components.Explorer.AttestationDetail as AttestationDetail
import Components.Explorer.AttestationList as AttestationList
import Components.Explorer.DisputeDetail as DisputeDetail
import Components.Explorer.DisputeList as DisputeList
import Components.Embed as Embed
import Components.Write.Runner as WriteRunner
import Components.Explorer.Graph as Graph
import Components.Explorer.Dashboard as Dashboard
import Components.Explorer.DelegationList as DelegationList
import Components.Explorer.ActionDetail as ActionDetail
import Components.Explorer.ActionList as ActionList
import Components.Explorer.DRepDetail as DRepDetail
import Components.Explorer.DRepList as DRepList
import Components.Explorer.Methodology as Methodology
import Components.Explorer.ProfileDetail as ProfileDetail
import Components.Explorer.ProfileList as ProfileList
import Components.Explorer.SpoList as SpoList
import Components.Explorer.TreasuryList as TreasuryList
import Components.Explorer.VoteList as VoteList
import Components.Layout.NavBar as NavBar
import Components.Layout.ActivityDrawer as ActivityDrawer
import Components.Layout.Sidebar as Sidebar
import Capabilities.Interaction.Types (confirmPollDelayMs, confirmPollMax)
import Components.Shared.DRepIdentity (shortId)
import Components.Shared.StatusChip as StatusChip
import Components.Shared.Toast as Toast
import Format (pluralize)
import Data.Array (cons, filter, null)
import Data.Array as Array
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Milliseconds(..))
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter, current, emitMatched)
import Halogen.Store.Monad (class MonadStore, updateStore)
import Route (Route(..))
import Route.Codec (printRoute)
import Store as Store
import Web.HTML (window)
import Web.HTML.HTMLDocument (setTitle)
import Web.HTML.Window (document)

type Input = Unit
type Output = Void

type Query :: forall k. k -> Type
type Query = Const Void

type State =
  { route :: Route
  , toasts :: Array Toast.Toast
  -- Tranzacțiile trimise pentru care încă se așteaptă confirmarea. Se arată pe orice ecran, fiindcă
  -- faptul că una e în zbor nu e o proprietate a ecranului de scriere.
  , watching :: Array { txId :: String, label :: String }
  }

data Action
  = Initialize
  | RouteChanged Route
  | HandleNavBar NavBar.Output
  | HandleWrite WriteRunner.Output
  | Notify Toast.Level String

type Slots =
  ( navbar :: NavBar.Slot
  , statusChip :: StatusChip.Slot
  , dashboard :: Dashboard.Slot
  , drepList :: DRepList.Slot
  , drepDetail :: DRepDetail.Slot
  , actionList :: ActionList.Slot
  , actionDetail :: ActionDetail.Slot
  , spoList :: SpoList.Slot
  , committee :: Committee.Slot
  , treasuryList :: TreasuryList.Slot
  , delegationList :: DelegationList.Slot
  , activity :: Activity.Slot
  , profileDetail :: ProfileDetail.Slot
  , profileList :: ProfileList.Slot
  , attestationDetail :: AttestationDetail.Slot
  , attestationList :: AttestationList.Slot
  , disputeDetail :: DisputeDetail.Slot
  , disputeList :: DisputeList.Slot
  , graph :: Graph.Slot
  , embed :: Embed.Slot
  , writeRunner :: WriteRunner.Slot
  , voteList :: VoteList.Slot
  , methodology :: Methodology.Slot
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
  => MonadInteract m
  => MonadGovWallet m
  => MonadAsk Env m
  => H.Component Query Input Output m
component =
  H.mkComponent
    { initialState: const { route: Home, toasts: [], watching: [] }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  handleAction = case _ of
    Initialize -> do
      -- Ruta curentă se citește, nu se așteaptă. `mkRouter` notifică prima potrivire în
      -- `runAppBase`, înainte ca rădăcina să se aboneze, deci acel prim eveniment se pierde: fără
      -- linia asta, orice URL deschis direct — un link dat mai departe, un refresh, un bookmark —
      -- randa pagina de pornire. Template-ul avea același defect; nu se vedea, pentru că avea o
      -- singură rută cu conținut.
      -- `Nothing` înseamnă „calea nu se parsează", nu „nu știu încă": `current` e o parsare pură a
      -- adresei curente, iar „/" se parsează ca `Home`. Deci un URL necunoscut e `NotFound`, și
      -- fără linia asta ar fi randat dashboard-ul — ceea ce e mai rău decât o pagină de eroare,
      -- pentru că arată ca un succes.
      current >>= case _ of
        Just r -> setRoute r
        Nothing -> setRoute NotFound
      emitter <- emitMatched
      _ <- H.subscribe (RouteChanged <$> emitter)
      pure unit
    RouteChanged route -> setRoute route

    -- Poarta de guvernanță se negociază O DATĂ, la conectare, și nu la fiecare intrare pe ecranul
    -- de scriere: extensiile se cer la `enable`, deci un `Api` obținut fără ele nu e bun de scris,
    -- iar unul cu ele n-are de ce să fie re-negociat. Momentul potrivit pentru o întrebare a
    -- wallet-ului e cînd omul tocmai a cerut să se conecteze.
    HandleNavBar (NavBar.WalletConnected key) -> do
      verdict <- connectGovernance key
      updateStore (Store.Connect verdict)
      -- Refuzul se spune ACUM, nu cînd cineva ajunge pe „Actions" și găsește un formular care nu
      -- se desenează. Motivul ÎNTREG stă în matricea de pe „Actions", nu aici: un mesaj care trece pe lîngă om
      -- în șase secunde nu e locul unde se explică de ce o extensie lipsește. Aici se spune doar
      -- că scrierea nu va merge, ca să nu afle cînd dă pe un formular care nu se desenează.
      case verdict of
        Allowed _ -> pure unit
        Blocked _ caps ->
          handleAction
            ( Notify Toast.Warning
                ( caps.walletName <>
                    " is connected for reading, but will not be able to sign the \
                    \nine actions here. Open Actions to see why."
                )
            )

    -- Un `enable` eșuat e aproape întotdeauna cineva care a închis prompt-ul. Se spune, fiindcă
    -- altfel apăsarea pe „Connect" n-ar avea NICIUN efect vizibil.
    HandleNavBar (NavBar.WalletConnectFailed detail) ->
      handleAction (Notify Toast.Warning (blockMessage (WalletDeclined detail)))

    HandleNavBar NavBar.WalletDisconnected -> updateStore Store.Disconnect

    Notify level message -> do
      ts <- H.gets _.toasts
      H.modify_ _ { toasts = Toast.toast level message `cons` ts }
      -- Ceasul pornește cu primul mesaj și se oprește cu ultimul. Un tic pe secundă pornit la
      -- încărcarea paginii ar bate pe veci pe un sit care, cea mai mare parte a timpului, doar
      -- citește date — iar dacă lista era deja plină, ceasul umblă deja.
      when (null ts) (void (H.fork toastLoop))

    HandleWrite (WriteRunner.TxSubmitted tx) -> do
      H.modify_ \st -> st { watching = tx `cons` st.watching }
      handleAction (Notify Toast.Info (tx.label <> " submitted. Waiting for the chain to confirm it."))
      void (H.fork (watch 0 tx))

  -- Titlul documentului se schimbă cu ruta. Într-un SPA nimeni nu-l schimbă în locul tău, iar un
  -- titlu identic pe toate ecranele face inutilizabile exact lucrurile pentru care cineva deschide
  -- mai multe taburi: istoricul, bookmark-urile și lista de taburi.
  setRoute route = do
    H.modify_ _ { route = route }
    liftEffect (window >>= document >>= setTitle (documentTitle route))

  -- Ceasul notificărilor: un tic pe secundă cît timp e ceva de arătat, și se oprește singur.
  toastLoop = do
    delayMs (Milliseconds 1000.0)
    H.modify_ \st -> st { toasts = Toast.tick st.toasts }
    ts <- H.gets _.toasts
    unless (null ts) toastLoop

  -- O tranzacție, urmărită pînă la confirmare sau pînă se termină programul. Ritmul stă în
  -- `Capabilities.Interaction.Types`, fiindcă e o afirmație despre cît durează un bloc, nu despre
  -- ecrane.
  --
  -- Ce se spune la capăt e „n-am văzut-o", NU „a eșuat": tranzacția a fost trimisă, iar singurul
  -- lucru care s-a terminat e răbdarea noastră. De aceea mesajul duce id-ul cu el.
  watch n tx = do
    delayMs (Milliseconds (confirmPollDelayMs n))
    res <- txStatus tx.txId
    case res of
      Right true -> do
        forget tx.txId
        -- Ecranele montate reinterogheaza. Pînă acum nimeni nu știa CÎND se confirmă o scriere,
        -- deci registrul rămînea cel dinaintea ei pe ecranul la care omul se uita.
        updateStore Store.Refresh
        handleAction (Notify Toast.Success (tx.label <> " is confirmed on chain."))
        -- Dacă ecranul de scriere mai e montat, își schimbă cardul; dacă nu, notificarea a spus
        -- deja tot. Un `tell` către un slot demontat nu face nimic, și e exact ce trebuie.
        void (H.tell WriteRunner._writeRunner unit (WriteRunner.MarkConfirmed tx.txId))
      _
        | n < confirmPollMax - 1 -> watch (n + 1) tx
        | otherwise -> do
            forget tx.txId
            handleAction
              ( Notify Toast.Warning
                  ( tx.label
                      <>
                        " is submitted, but has not been seen on chain yet. Nothing is \
                        \lost — its id is "
                      <> tx.txId
                      <> "."
                  )
              )

  forget txId = H.modify_ \st -> st { watching = filter (\w -> w.txId /= txId) st.watching }

  -- Că o tranzacție e în zbor se vede pe ORICE ecran: cine pleacă de pe „Actions" ca să se uite la
  -- profilul pe care l-a atestat trebuie să poată vedea că încă se așteaptă.
  watchingBanner st =
    if null st.watching then HH.text ""
    else
      HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 pt-2 relative z-10") ]
        [ HH.div [ HP.class_ (HH.ClassName "alert alert-info py-2 text-sm") ]
            [ HH.span_
                [ HH.text
                    ( pluralize (Array.length st.watching) "transaction"
                        <> " waiting for the chain. You can keep browsing — you will be told when it lands."
                    )
                ]
            ]
        ]

  -- Fișa de încorporat se randează FĂRĂ cadru: fără bară, fără bandă de prospețime, fără linkul
  -- de sărire. Ce se pune pe site-ul altcuiva trebuie să fie fapta, nu produsul nostru în
  -- miniatură — iar o bară de navigare într-un cadru de 380px e doar zgomot pe care nimeni nu-l
  -- poate folosi.
  render { route: Embed filters } =
    HH.div [ HP.class_ (HH.ClassName "bg-base-100") ]
      [ HH.slot_ Embed._embed unit Embed.component filters ]

  render st =
    HH.div [ HP.class_ (HH.ClassName "min-h-screen bg-base-100") ]
      -- Linkul de sărire e primul lucru tabulabil din pagină și se vede doar când îl ții cu
      -- tastatura. Fără el, pe fiecare navigare se trec la Tab brandul, cinci linkuri, căutarea și
      -- butonul de wallet înainte de primul rând de date.
      [ HH.a
          [ HP.href "#main"
          , HP.class_
              (HH.ClassName "sr-only focus:not-sr-only focus:absolute focus:z-50 focus:m-2 btn btn-sm btn-primary")
          ]
          [ HH.text "Skip to content" ]
      -- Cele trei straturi de fundal, fixe și pe toate paginile, exact cum le pune `bjj-frontend`:
      -- overlay-ul dă adâncime și contrast barei de navigare, iar cele două lumini pulsează decalat
      -- ca să nu bată în ritm. `pointer-events-none` fiindcă sunt decor, nu suprafață.
      --
      -- Dedesubt, în locul fotografiei lui bjj: marca Cardano, uriașă și la 3% opacitate, derivând
      -- lent. O fotografie de stoc aleasă de mine ar fi fost și o decizie de gust, și una de
      -- licență; asta e ceva ce proiectul deține deja și care spune adevărul despre el. Se
      -- înlocuiește cu o fotografie schimbând o regulă din CSS.
      -- Luminile sunt ascunse pe telefon: pe un ecran mic ocupă jumătate din el.
      , HH.div [ HP.class_ (HH.ClassName "fixed inset-0 pointer-events-none hero-bg-image z-0") ] []
      , HH.div [ HP.class_ (HH.ClassName "fixed inset-0 pointer-events-none global-bg-overlay z-0") ] []
      , HH.div [ HP.class_ (HH.ClassName "fixed inset-0 pointer-events-none hero-neon-glow-left z-0 hidden sm:block") ] []
      , HH.div [ HP.class_ (HH.ClassName "fixed inset-0 pointer-events-none hero-neon-glow-right z-0 hidden sm:block") ] []
      , HH.slot NavBar._navbar unit NavBar.component st.route HandleNavBar
      -- Notificările stau în înveliș, deasupra tuturor: ele sînt singurul lucru care trebuie să
      -- ajungă la om și după ce a plecat de pe ecranul care le-a produs.
      , Toast.render st.toasts
      , watchingBanner st
      -- Chip-ul stă în afara slotului de rută, nu în fiecare pagină: prospețimea e o proprietate a
      -- datelor, nu a ecranului, și un singur apel o acoperă pe toate.
      -- Înălțimea e rezervată, nu descoperită: banda crește de la o pastilă („checking…") la
      -- câteva fapte când răspunde `/status`, iar fără rezervare tot ce e sub ea — titlul,
      -- cardurile, primul tabel — sare în jos exact când utilizatorul a început să citească.
      -- Șina și docul. O funcție pură, nu un slot: navigarea merge prin ancore, pe care
      -- `SpaLinkInterceptor` le prinde oricum.
      , Sidebar.render st.route
      -- Sertarul de activitate: butonul flotant stă deasupra docului pe telefon și coboară pe
      -- desktop, exact ca în bjj. Se încarcă abia la deschidere.
      , HH.slot_ ActivityDrawer._activityDrawer unit ActivityDrawer.component unit
      -- `md:pl-24` lasă loc șinei fixe, `pb-20` docului de pe telefon. Fără al doilea, ultimul rând
      -- al oricărui tabel stă sub doc și nu se poate citi.
      , HH.div [ HP.class_ (HH.ClassName "md:pl-24 pb-20 md:pb-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 pt-4 min-h-14 sm:min-h-10 relative z-10") ]
              [ HH.slot_ StatusChip._statusChip unit StatusChip.component unit ]
          , HH.main [ HP.id "main", HP.class_ (HH.ClassName "min-h-[80vh] relative z-10") ]
              [ renderRoute st.route ]
          ]
      ]

  renderRoute = case _ of
    Home -> HH.slot_ Dashboard._dashboard unit Dashboard.component unit
    DRepList filters -> HH.slot_ DRepList._drepList unit DRepList.component filters
    DRepDetail drepId -> HH.slot_ DRepDetail._drepDetail unit DRepDetail.component drepId
    ActionList filters -> HH.slot_ ActionList._actionList unit ActionList.component filters
    ActionDetail actionId -> HH.slot_ ActionDetail._actionDetail unit ActionDetail.component actionId
    VoteList filters -> HH.slot_ VoteList._voteList unit VoteList.component filters
    SpoList filters -> HH.slot_ SpoList._spoList unit SpoList.component filters
    Committee -> HH.slot_ Committee._committee unit Committee.component unit
    TreasuryList filters -> HH.slot_ TreasuryList._treasuryList unit TreasuryList.component filters
    DelegationList filters -> HH.slot_ DelegationList._delegationList unit DelegationList.component filters
    Activity filters -> HH.slot_ Activity._activity unit Activity.component filters
    ProfileDetail pid -> HH.slot_ ProfileDetail._profileDetail unit ProfileDetail.component pid
    ProfileList filters -> HH.slot_ ProfileList._profileList unit ProfileList.component filters
    AttestationDetail aid -> HH.slot_ AttestationDetail._attestationDetail unit AttestationDetail.component aid
    AttestationList filters -> HH.slot_ AttestationList._attestationList unit AttestationList.component filters
    DisputeDetail did -> HH.slot_ DisputeDetail._disputeDetail unit DisputeDetail.component did
    DisputeList filters -> HH.slot_ DisputeList._disputeList unit DisputeList.component filters
    Graph filters -> HH.slot_ Graph._graph unit Graph.component filters
    Write filters -> HH.slot WriteRunner._writeRunner unit WriteRunner.component filters HandleWrite
    Embed filters -> HH.slot_ Embed._embed unit Embed.component filters
    Methodology filters -> HH.slot_ Methodology._methodology unit Methodology.component filters
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

-- | Titlul per ecran. Numele produsului merge la __sfârșit__: într-un tab îngust browserul taie
-- | coada, deci ce distinge ecranul trebuie să fie în față.
documentTitle :: Route -> String
documentTitle = case _ of
  Home -> "Testatum — proof of who controls a Cardano governance credential"
  DRepList _ -> "DReps — Testatum"
  DRepDetail drepId -> shortId drepId <> " — Testatum"
  ActionList _ -> "Governance actions — Testatum"
  ActionDetail _ -> "Proposal — Testatum"
  VoteList _ -> "Votes — Testatum"
  SpoList _ -> "Stake pool operators — Testatum"
  Committee -> "Constitutional committee — Testatum"
  TreasuryList _ -> "Treasury withdrawals — Testatum"
  DelegationList _ -> "Delegations — Testatum"
  Activity _ -> "Activity — Testatum"
  -- Numele profilului nu se stie cind se pune titlul, deci id-ul scurtat, ca la DRep.
  ProfileDetail pid -> shortId pid <> " — Testatum"
  ProfileList _ -> "Profiles — Testatum"
  AttestationDetail aid -> shortId aid <> " — Testatum"
  AttestationList f ->
    if f.kind == Just "credential_claim" then "Verified credentials — Testatum"
    else "Vouches — Testatum"
  DisputeDetail did -> shortId did <> " — Testatum"
  DisputeList _ -> "Challenges — Testatum"
  Graph _ -> "Delegation graph — Testatum"
  Embed _ -> "Testatum governance record"
  Write _ -> "Act on chain — Testatum"
  Methodology _ -> "Methodology — Testatum"
  NotFound -> "Not found — Testatum"
