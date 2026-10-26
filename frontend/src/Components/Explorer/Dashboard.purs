-- | Ecranul de pornire: un singur apel la `/pages/dashboard`, din care se randează tot.
-- |
-- | E și hub: cardurile de navigare stau pe aceeași pagină, nu într-o componentă separată. Un „hub"
-- | fără cifre e un meniu, iar cifrele fără un drum spre ecranul care le explică sunt un afiș.
-- |
-- | Trei decizii pe care forma datelor le impune:
-- |
-- |   * cifra de 204 DRep-i activi+inactivi __nu__ e `total_dreps` (294). Linkul de sub ea poartă
-- |     exact filtrul din care a ieșit cifra, altfel utilizatorul numără altceva decât a citit;
-- |   * trezoreria sunt două numere — cerut și adoptat. Unul singur ar spune că s-au plătit 656 de
-- |     milioane de ADA, când adoptat era 0;
-- |   * cifrele de putere se etichetează cu `power_epoch`, nu cu epoca curentă.
-- |
-- | Linkurile spre ecranele care nu există încă sunt scrise ca șiruri aici. Când taskurile 6–11 adaugă
-- | rutele, se înlocuiesc cu `printRoute` — forma lor e deja cea pe care o va tipări codecul.
module Components.Explorer.Dashboard
  ( Slot
  , Output
  , _dashboard
  , component
  , drepListHref
  , activeInactive
  , participationSeries
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDashboard, getRegistrySummary)
import Capabilities.Query.Gov.Types (DRepSummary(..), DashboardPage(..), EpochPoint(..), GovActionSummary(..), Lovelace, RegistrySummary)
import Components.Chart.Series as Series
import Components.Shared.DRepIdentity as DRepIdentity
import Data.Array (mapMaybe, null)
import Data.FunctorWithIndex (mapWithIndex)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Foldable (maximum, minimum)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Tuple (Tuple(..))
import Format (formatAda, formatInt, formatPercent, humanize, pluralize)
import Route.GovQueries
  ( actionDetailHrefFor
  , actionListHrefFor
  , activityPath
  , attestationListPath
  , committeePath
  , defaultVoteFilters
  , delegationListPath
  , disputeListPath
  , drepDetailHrefFor
  , drepListHrefFor
  , emptyDRepFilters
  , emptyGovActionFilters
  , graphPath
  , methodologyPath
  , profileListPath
  , spoListPath
  , voteListHrefFor
  , withdrawalListPath
  , writePath
  )
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_dashboard :: Proxy "dashboard"
_dashboard = Proxy

type State =
  { page :: RemoteData ApiError DashboardPage
  -- Separat de `page` fiindcă e un alt apel și o altă secțiune: cifrele registrului nu depind de
  -- cele de guvernanță și nu trebuie să cadă împreună cu ele.
  , registry :: Maybe RegistrySummary
  }

data Action
  = Initialize
  | Retry

-- | Numărul de DRep-i pe care îl arată cardul, și filtrul din care a ieșit, într-un singur loc:
-- | cifra și linkul nu pot să se despartă.
activeInactive :: DashboardPage -> Int
activeInactive (DashboardPage p) = p.activeDreps + p.inactiveDreps

-- | Linkul se construiește din același codec care produce și ruta, nu dintr-un șir scris aici:
-- | cifra de pe card și lista pe care o deschide trebuie să vină din același filtru.
-- |
-- | `status` se repetă, nu se unește cu virgulă: API-ul citește parametrii repetabili ca listă, iar
-- | `status=active,inactive` ar fi un singur status necunoscut — măsurat, serverul îl refuză.
drepListHref :: String
drepListHref = drepListHrefFor (emptyDRepFilters { status = [ "active", "inactive" ] })

-- | Marginile seriei, ca textul de sub grafic să spună cât de mare e de fapt variația.
minimumRate :: DashboardPage -> Maybe Number
minimumRate (DashboardPage p) = minimum (mapMaybe (\(EpochPoint e) -> e.participationRate) p.participationByEpoch)

maximumRate :: DashboardPage -> Maybe Number
maximumRate (DashboardPage p) = maximum (mapMaybe (\(EpochPoint e) -> e.participationRate) p.participationByEpoch)

participationSeries :: DashboardPage -> Array Series.Point
participationSeries (DashboardPage p) = map point p.participationByEpoch
  where
  point (EpochPoint e) =
    { label: "epoch " <> show e.epoch
    , value: fromMaybe 0.0 e.participationRate
    , hint: formatPercent e.participationRate
        <> " — "
        <> show e.drepsVoted
        <> " of "
        <> show e.drepsWithPower
        <> " DReps with power, "
        <> show e.votesCast
        <> " votes"
    }

component
  :: forall q i m
   . MonadQueryGov m
  => H.Component q i Output m
component =
  H.mkComponent
    { initialState: const { page: NotAsked, registry: Nothing }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  handleAction = case _ of
    -- `H.fork`, nu `load` direct: initializatorul unui copil ține deschisă inițializarea
    -- PĂRINTELUI, iar părintele e cel care pune titlul documentului. Măsurat pe deploy:
    -- `/activity` răspunde în 12 secunde pe baza vie, iar tab-ul scria titlul generic tot timpul
    -- ăla. Un ecran lent nu are voie să țină în loc cadrul aplicației.
    Initialize -> void (H.fork load)
    Retry -> load

  load = do
    H.modify_ _ { page = Loading }
    -- Registrul întâi, fiindcă el e subiectul paginii. Explorerul de guvernanță vine după, și
    -- dacă răspunde mai târziu nu ține în loc partea de sus.
    reg <- getRegistrySummary
    H.modify_ _
      { registry = case reg of
          Left _ -> Nothing
          Right r -> Just r
      }
    res <- getDashboard
    H.modify_ _
      { page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    -- Pagina de pornire NU se încadrează: la bjj eroul e pe toată lățimea, fără ramă, iar un erou
    -- într-un panou arată ca o secțiune oarecare. Restul ecranelor primesc `explorer-page`.
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-6") ]
      -- Hub-ul vine DUPĂ cifre, nu înaintea lor. Cifrele sunt motivul pentru care există pagina;
      -- patru carduri de navigare între titlu și ele cheltuiau primul ecran pe ceva ce bara de sus
      -- spune deja, iar „294 de DRep-i" ajungea sub linia de plutire.
      [ intro st
      , hubOf "Everything in the register" registryGroups
      -- Explorerul vine DUPĂ registru și sub propriul titlu, cu o propoziție care spune de ce
      -- există aici: nu e un al doilea produs, e felul în care un claim despre un reprezentant se
      -- poate verifica împotriva lanțului.
      , HH.div [ HP.class_ (HH.ClassName "space-y-2 pt-2") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "text-2xl font-bold") ] [ HH.text "The governance record" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "A profile can claim to be a Cardano representative. This is where that claim is \
                  \checked: every representative, every proposal, every vote, straight from the \
                  \chain."
              ]
          ]
      , case st.page of
          NotAsked -> skeleton "Loading governance figures…"
          Loading -> skeleton "Loading governance figures…"
          Failure e -> failure e
          Success p -> renderPage p
      , hubOf "Everything in the explorer" governanceGroups
      ]

  -- Prima pagină trebuie să răspundă, în ordinea asta, la: ce e ăsta, de ce m-ar interesa, ce pot
  -- face aici. Versiunea dinainte începea cu „A verifiable track record for Cardano governance" —
  -- adevărat, dar e o propoziție pe care o înțelege cineva care știe deja ce e guvernanța Cardano.
  -- Cine nu știe pleacă de la ea fără nimic.
  --
  -- Deci: o frază care spune ce se vede aici în cuvinte de zi cu zi, apoi trei lucruri pe care
  -- le poți face, apoi cele trei cuvinte din jargon pe care site-ul le folosește oricum. Cifrele
  -- vin după.
  -- EROUL, după tiparul din `bjj-frontend/src/Components/Home/ExplorerHub.purs`: o secțiune de
  -- înălțimea ecranului, centrată, cu marca plutind într-un inel luminos, titlul în gradient, și
  -- indicatorul de derulare jos. Intrările sînt decalate — 0s, 0,2s, 0,6s — ca pagina să se așeze,
  -- nu să apară dintr-o dată.
  --
  -- Marca e logo-ul Cardano, nu unul propriu: un registru de reputație pentru guvernanța Cardano
  -- spune din prima privire pe ce lanț trăiește. Cînd proiectul capătă semn propriu, se schimbă
  -- un `src`.
  intro st =
    HH.div_
      [ HH.section
          [ HP.id "hero"
          , HP.class_
              ( HH.ClassName
                  "w-full min-h-[82vh] relative overflow-hidden flex flex-col items-center justify-center"
              )
          ]
          [ HH.div [ HP.class_ (HH.ClassName "relative max-w-3xl mx-auto text-center px-4 space-y-5 sm:space-y-8") ]
              [ HH.div [ HP.class_ (HH.ClassName "flex justify-center mb-2 animate-scale-in hero-logo-float") ]
                  [ HH.div [ HP.class_ (HH.ClassName "animate-glow rounded-full p-3") ]
                      [ HH.img
                          [ HP.src "/images/cardano-logo.svg"
                          , HP.alt "Cardano"
                          , HP.class_ (HH.ClassName "w-16 h-16 sm:w-24 sm:h-24 opacity-90")
                          ]
                      ]
                  ]
              , HH.h1
                  [ HP.class_
                      ( HH.ClassName
                          "text-4xl sm:text-5xl lg:text-6xl font-black leading-tight animate-fade-in-up"
                      )
                  ]
                  [ HH.text "Who vouches for whom, "
                  , HH.span [ HP.class_ (HH.ClassName "gradient-text") ] [ HH.text "on chain" ]
                  ]
              , HH.p
                  [ HP.class_ (HH.ClassName "text-lg sm:text-xl text-base-content/70 max-w-xl mx-auto animate-fade-in-up")
                  , HP.style "animation-delay: 0.2s"
                  ]
                  [ HH.text
                      "Anyone can state something about someone else. The subject accepts it or \
                      \does not, and anyone who thinks it is false can put money behind the \
                      \challenge."
                  ]
              , HH.div
                  [ HP.class_ (HH.ClassName "flex flex-col sm:flex-row items-center justify-center gap-3 animate-fade-in-up")
                  , HP.style "animation-delay: 0.6s"
                  ]
                  [ HH.a [ HP.href "/attestations", HP.class_ (HH.ClassName "btn btn-primary btn-md sm:btn-lg") ]
                      [ HH.text "See who vouched for whom" ]
                  , HH.a [ HP.href "/write", HP.class_ (HH.ClassName "btn btn-ghost btn-sm sm:btn-md") ]
                      [ HH.text "Make a claim of your own" ]
                  ]
              , HH.p
                  [ HP.class_ (HH.ClassName "text-sm text-base-content/50 animate-fade-in-up")
                  , HP.style "animation-delay: 0.8s"
                  ]
                  [ HH.text "Nothing is deleted and nothing is anonymous." ]
              ]
          , HH.div [ HP.class_ (HH.ClassName "absolute bottom-8 left-1/2 -translate-x-1/2 scroll-indicator hidden sm:block") ]
              [ HH.div [ HP.class_ (HH.ClassName "w-6 h-10 rounded-full border-2 border-base-content/20 flex justify-center pt-2") ]
                  [ HH.div [ HP.class_ (HH.ClassName "w-1 h-2 bg-base-content/30 rounded-full") ] [] ]
              ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "section-divider") ] []
      , HH.div [ HP.class_ (HH.ClassName "space-y-4 pt-10") ]
          [ HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl scroll-reveal") ]
              [ HH.text
                  "Anyone can state something about someone else here: that they delivered a \
                  \milestone, passed an audit, hold a role. The claim is written on chain, the \
                  \subject can accept it, and anyone who thinks it is false can challenge it by \
                  \putting money behind the challenge."
              ]
          , HH.div [ HP.class_ (HH.ClassName "scroll-reveal stagger-1") ] [ registryFigures st ]
          , HH.div [ HP.class_ (HH.ClassName "grid gap-3 md:grid-cols-3 scroll-reveal stagger-2") ]
              (map useCase useCases)
          , HH.div [ HP.class_ (HH.ClassName "scroll-reveal stagger-3") ] [ glossary ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "section-divider mt-10") ] []
      , whyNotAWebsite
      , whatThisDoesNot
      ]

  -- OBIECȚIA PE CARE O ARE ORICE VIZITATOR, și la care pagina nu răspundea deloc: „de ce pe
  -- blockchain și nu o bază de date obișnuită?". Fără ea, restul paginii descrie un produs care pare
  -- că putea fi un site oarecare.
  --
  -- Fiecare punct e un CONTRAST cu echivalentul web2, nu o funcție: „nu există buton de ștergere" îi
  -- spune cuiva ceva, „append-only" nu.
  whyNotAWebsite =
    HH.div [ HP.class_ (HH.ClassName "space-y-4 pt-10") ]
      [ HH.h2 [ HP.class_ (HH.ClassName "text-2xl font-bold scroll-reveal") ]
          [ HH.text "Why not just a website?" ]
      , HH.div [ HP.class_ (HH.ClassName "grid gap-3 md:grid-cols-2") ]
          (mapWithIndex contrastCard contrasts)
      ]

  contrastCard i c =
    HH.div
      [ HP.class_
          (HH.ClassName ("card bg-base-200 explorer-card scroll-reveal stagger-" <> show (i + 1)))
      ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-1 p-4") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "font-semibold") ] [ HH.text c.title ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-80") ] [ HH.text c.body ]
          ]
      ]

  contrasts =
    [ { title: "Nobody can delete you from someone else's history."
      , body:
          "A normal database has a delete button. Whoever runs it can make an inconvenient claim \
          \disappear, and from outside you cannot tell never-happened from was-removed. Here that \
          \button does not exist, for anyone, including us. A challenged claim is shown beside its \
          \challenge, not instead of it."
      }
    , { title: "Consent cannot be faked by whoever runs it."
      , body:
          "On a normal site, accepted is a value the server writes, so whoever holds the database \
          \can write it. Here it is a signature only the subject can produce. Nobody can confirm a \
          \claim on your behalf, and the chain also refuses a claim issued about yourself."
      }
    , { title: "The identity is already the chain's."
      , body:
          "No invented accounts. Proving you control a governance key is cryptographic, checked by \
          \the ledger's own signature rule, and it works the same for a key and for a script, which \
          \is what committees and organisations actually are. So the record sits next to what that \
          \key did."
      }
    , { title: "Challenging a false claim is not a contact form."
      , body:
          "The deposit is what separates a challenge from an opinion. And an undecided challenge \
          \expires without needing anyone's permission, so nobody can block you by doing nothing."
      }
    ]

  -- Și limitele, imediat sub. Onestitatea despre ce NU face e cel mai ieftin semnal de încredere care
  -- există, iar un registru de reputație care și-ar ascunde limitele ar fi exact genul de lucru pe
  -- care produsul ăsta pretinde că-l repară.
  whatThisDoesNot =
    HH.div [ HP.class_ (HH.ClassName "pt-8") ]
      [ HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card scroll-reveal") ]
          [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2 p-4") ]
              [ HH.h3 [ HP.class_ (HH.ClassName "font-semibold") ]
                  [ HH.text "What this does not do" ]
              , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-80 max-w-3xl") ]
                  [ HH.text
                      "It does not make claims true. Nobody here verifies that the milestone \
                      \shipped or the audit passed, and no system can. What it guarantees is \
                      \narrower and harder: someone specific signed this, the subject agreed, \
                      \nobody can take it back, and anyone can check."
                  ]
              ]
          ]
      ]

  -- Cele trei numere ale registrului, sus, pentru că ele sunt produsul. Un „—" cît timp nu s-a
  -- încărcat, nu un zero: zero ar fi o afirmație despre registru.
  registryFigures st =
    HH.div [ HP.class_ (HH.ClassName "grid gap-3 sm:grid-cols-3") ]
      [ figureCard "Profiles" (countOf st _.profiles) "Identities anyone can look up."
          profileListPath
          "from-success to-info"
          "0"
      , figureCard "Vouches" (countOf st _.attestations) "Claims made about them."
          attestationListPath
          "from-info to-accent"
          "80"
      , figureCard "Challenges" (countOf st _.disputes) "Claims someone put money against."
          disputeListPath
          "from-accent to-warning"
          "160"
      ]

  countOf st f = case st.registry of
    Nothing -> "—"
    Just r -> formatInt (f r)

  -- După `renderHeroStatCard` din `bjj-frontend/src/Components/Shared/StatGrid.purs`: valoarea în
  -- gradient, o lumină care apare la hover peste tot cardul, colțuri mari și o intrare decalată.
  -- Cifrele registrului sunt primul lucru care se vede sub erou, deci merită tratamentul.
  --
  -- Gradientul diferă per card, iar ordinea nu e decorativă: profiluri → atestări → dispute merge
  -- de la verde spre portocaliu, adică de la „cine există" spre „ce e contestat".
  figureCard label value body href gradient delay =
    HH.a
      [ HP.href href
      , HP.class_
          ( HH.ClassName
              "group relative overflow-hidden rounded-2xl bg-base-200 shadow-md hover:shadow-lg \
              \transition-all duration-300 animate-fade-in-up block"
          )
      , HP.style ("animation-delay: " <> delay <> "ms")
      ]
      [ HH.div
          [ HP.class_
              ( HH.ClassName
                  ( "absolute inset-0 bg-gradient-to-br " <> gradient
                      <> " opacity-0 group-hover:opacity-10 transition-opacity duration-500"
                  )
              )
          ]
          []
      , HH.div [ HP.class_ (HH.ClassName "relative p-4 flex flex-col gap-1") ]
          [ HH.span
              [ HP.class_
                  (HH.ClassName "text-xs opacity-60 font-medium uppercase tracking-wider")
              ]
              [ HH.text label ]
          , HH.span
              [ HP.class_
                  ( HH.ClassName
                      ( "text-3xl sm:text-4xl font-black bg-gradient-to-r " <> gradient
                          <> " bg-clip-text text-transparent"
                      )
                  )
              ]
              [ HH.text value ]
          , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ HH.text body ]
          ]
      ]

  useCase u =
    HH.a
      [ HP.href u.href
      , HP.class_ (HH.ClassName "card bg-base-200 hover:bg-base-300 transition-colors")
      ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-4 gap-1") ]
          [ HH.span [ HP.class_ (HH.ClassName "font-semibold") ] [ HH.text u.title ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text u.body ]
          ]
      ]

  -- Trei cuvinte, o propoziție fiecare. Site-ul le folosește de sute de ori; a le explica o dată,
  -- aici, costă trei rânduri și scutește fiecare ecran de o paranteză.
  glossary =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-4 gap-2") ]
          [ HH.span [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-70") ]
              [ HH.text "Four words this site uses a lot" ]
          , HH.dl [ HP.class_ (HH.ClassName "grid gap-x-6 gap-y-2 sm:grid-cols-2 lg:grid-cols-4 text-sm") ]
              [ term "Profile" "An identity, held as a token. Whoever holds the token holds the profile."
              , term "Vouch" "A claim one profile makes about another. It is not binding until the subject accepts it."
              , term "Challenge" "An objection to a claim, with a deposit at stake. Lose the challenge, lose the deposit."
              , term "DRep" "A Cardano governance representative. A profile can prove it owns one — that is a credential claim."
              ]
          ]
      ]

  term label body =
    HH.div_
      [ HH.dt [ HP.class_ (HH.ClassName "font-semibold") ] [ HH.text label ]
      , HH.dd [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text body ]
      ]

  hubOf title groups =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ HH.h2 [ HP.class_ (HH.ClassName "text-xl font-bold") ] [ HH.text title ]
      , HH.div [ HP.class_ (HH.ClassName "grid gap-4 md:grid-cols-2") ] (map hubGroup groups)
      ]

  hubGroup group =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.h3 [ HP.class_ (HH.ClassName "text-sm uppercase tracking-wide opacity-70") ]
          [ HH.text group.title ]
      , HH.div [ HP.class_ (HH.ClassName "space-y-2") ] (map hubCard group.entries)
      ]

  hubCard entry =
    HH.a
      [ HP.href entry.href
      , HP.class_ (HH.ClassName "card bg-base-200 hover:bg-base-300 transition-colors")
      ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-4") ]
          -- `span`, nu `h3`: sunt patru LINKURI într-un hub, iar ca titluri săreau de la h1 direct
          -- la h3 și rupeau harta de titluri a paginii.
          [ HH.span [ HP.class_ (HH.ClassName "card-title text-base") ] [ HH.text entry.label ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text entry.description ]
          ]
      ]

  skeleton label =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text label ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ]
              [ HH.text "The governance figures could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          -- Un ecran de eroare fără nimic de apăsat e un fund de sac: singura ieșire rămâne
          -- reîncărcarea din browser, care pe ruta asta costă încă o dată cele ~30 de secunde de
          -- așteptare. `isRetryable` există deja în transport, dar nu-l folosea nimeni.
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm")
              , HP.type_ HP.ButtonButton
              , HE.onClick (const Retry)
              ]
              [ HH.text "Try again" ]
          ]
      ]

  renderPage page@(DashboardPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-6") ]
      -- Ordinea spune o poveste: cifrele, apoi ce are TERMEN (se închide în cinci epoci), apoi cine
      -- cântărește, apoi contextul. Desfășurările pe tip și pe rezultat sunt material de referință,
      -- nu titlu de primă pagină — înainte stăteau deasupra singurului bloc cu ceas pe el.
      [ statsRow page
      , closingSoon p
      , topDreps p
      , participation page
      , treasury p
      , HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-2") ]
          [ breakdown "Governance actions by type" "type" p.actionsByType
          , breakdown "Governance actions by outcome" "state" p.actionsByState
          ]
      ]

  statsRow page@(DashboardPage p) =
    HH.div [ HP.class_ (HH.ClassName "grid gap-4 sm:grid-cols-2 lg:grid-cols-4") ]
      -- Punctul despărțitor înaintea retrașilor nu e stilistic: cu virgule, cele trei cifre se
      -- citeau ca o descompunere a lui 294, iar 204+90+526 = 820. Retrașii nu fac parte din total.
      [ statCard "Registered DReps" (formatInt p.totalDreps)
          ( HH.span_
              [ HH.a [ HP.href drepListHref, HP.class_ (HH.ClassName "link link-hover font-medium") ]
                  [ HH.text (formatInt (activeInactive page) <> " active or inactive") ]
              , HH.text
                  ( ", " <> formatInt p.unknownDreps <> " unknown · "
                      <> formatInt p.retiredDreps
                      <> " more have retired"
                  )
              ]
          )
      , statCard "Voting power delegated" (formatAda p.drepPowerLovelace)
          (HH.text (powerAsOf p.powerEpoch))
      -- „Parked on always-abstain" era argou peste un nume de protocol. Cifra asta e 85% din toată
      -- puterea delegată; propoziția trebuie să spună cine a ales și ce a ales.
      , statCard "Delegated to always-abstain" (formatAda p.alwaysAbstainLovelace)
          ( HH.text
              ( "Ada whose holders chose a standing abstain instead of a representative. Plus "
                  <> formatAda p.alwaysNoConfidenceLovelace
                  <> " on always-no-confidence."
              )
          )
      -- „In flight" e idiom de aviație, iar aceeași stare avea patru nume în produs.
      , statCard "Open for voting" (formatInt p.actionsInFlight)
          ( HH.span_
              [ HH.a
                  [ HP.href (actionListHrefFor (emptyGovActionFilters { state = [ "proposed" ] }))
                  , HP.class_ (HH.ClassName "link link-hover font-medium")
                  ]
                  [ HH.text "see them" ]
              , HH.text (" · of " <> formatInt p.totalActions <> " ever proposed")
              ]
          )
      ]

  statCard title value desc =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-4 gap-1") ]
          [ HH.span [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text title ]
          , HH.span [ HP.class_ (HH.ClassName "text-2xl font-semibold") ] [ HH.text value ]
          , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ desc ]
          ]
      ]

  -- Două numere, nu unul. „Cerut" e ce au scris propunerile; „adoptat" e ce a plătit trezoreria. La
  -- măsurătoare, al doilea era zero — un singur număr ar fi spus exact pe dos.
  treasury p =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text "Treasury withdrawals" ]
          , HH.div [ HP.class_ (HH.ClassName "grid gap-4 sm:grid-cols-2") ]
              [ figure "Requested" (formatAda p.treasuryRequestedLovelace)
              , figure "Enacted" (formatAda p.treasuryEnactedLovelace)
              ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text
                  "Requested is what withdrawal proposals asked for. Enacted is what the treasury \
                  \actually paid out. They are different questions and the gap between them is the \
                  \point."
              ]
          ]
      ]

  figure label value =
    HH.div_
      [ HH.div [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text label ]
      , HH.div [ HP.class_ (HH.ClassName "text-2xl font-semibold") ] [ HH.text value ]
      ]

  participation page@(DashboardPage p) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ]
              [ HH.text "DRep participation by epoch" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "Share of DReps with voting power that cast at least one vote in the epoch." ]
          , Series.render (participationSeries page)
          -- Barele sunt relative la vârf, deci o serie aproape plată se desenează ca un bloc plin
          -- și nu spune nimic. Intervalul scris în clar face diferența între „n-a variat" și
          -- „graficul e stricat".
          , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
              [ HH.text
                  ( "Between "
                      <> formatPercent (minimumRate page)
                      <> " and "
                      <> formatPercent (maximumRate page)
                      <> " across these epochs. Latest epoch in range: "
                      <> show p.epoch
                      <> "."
                  )
              ]
          ]
      ]

  -- Fiecare rând e un link spre lista filtrată: cineva care citește „Expired 107" vrea cele 107,
  -- iar fără link trebuie să meargă la Actions și să reconstruiască filtrul de mână. Exact aceleași
  -- valori sunt deja linkuri în bara laterală a listei.
  breakdown title key pairs =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text title ]
          , if null pairs then HH.p [ HP.class_ (HH.ClassName "opacity-70 text-sm") ] [ HH.text "Nothing yet." ]
            else
              -- Containerul de derulare nu e decor: fără el, tabelul împinge toată pagina pe
              -- derulare orizontală la lățime de telefon.
              HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
                [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                    [ HH.tbody_ (map (pairRow key) pairs) ]
                ]
          ]
      ]

  pairRow key (Tuple label count) =
    let
      href =
        if key == "type" then actionListHrefFor (emptyGovActionFilters { type_ = [ label ] })
        else actionListHrefFor (emptyGovActionFilters { state = [ label ] })
    in
      HH.tr [ HP.class_ (HH.ClassName "hover:bg-base-300") ]
        [ HH.td_
            [ HH.a [ HP.href href, HP.class_ (HH.ClassName "link link-hover") ]
                [ HH.text (humanize label) ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt count) ]
        ]

  closingSoon p =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text "Closing soon" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "Open actions whose voting window ends within five epochs." ]
          , if null p.closingSoon then
              HH.p [ HP.class_ (HH.ClassName "opacity-70 text-sm") ] [ HH.text "Nothing closing soon." ]
            else HH.ul [ HP.class_ (HH.ClassName "divide-y divide-base-300") ] (map actionRow p.closingSoon)
          ]
      ]

  actionRow (GovActionSummary a) =
    HH.li [ HP.class_ (HH.ClassName "py-2 flex flex-wrap items-baseline justify-between gap-2") ]
      [ HH.a
          [ HP.href (actionDetailHrefFor a.id)
          , HP.class_ (HH.ClassName "min-w-0 space-y-0.5 hover:underline")
          ]
          [ HH.div [ HP.class_ (HH.ClassName "font-medium truncate") ]
              [ HH.text (fromMaybe "Untitled proposal" a.title) ]
          , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 truncate"), HP.title a.id ]
              [ HH.text a.bech32 ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "text-sm text-right space-y-0.5") ]
          [ HH.div_ [ HH.text (humanize a.type_) ]
          , HH.div [ HP.class_ (HH.ClassName "opacity-70") ]
              [ HH.text
                  ( maybe "" (\e -> "last votable epoch " <> show e <> " · ") a.lastVotableEpoch
                      <> pluralize a.votesCast "vote"
                      <> treasuryNote a.treasuryAmount
                  )
              ]
          ]
      ]

  -- Distribuția de putere vine cu o epocă întîrziere față de lanț, deci `power_epoch` lipsește
  -- cît timp ledgerul n-a publicat încă una. Atunci toate cifrele de putere de deasupra sînt zero,
  -- și singurul lucru onest de scris lîngă ele e de ce.
  powerAsOf :: Maybe Int -> String
  powerAsOf = case _ of
    Just e -> "as of epoch " <> show e
    Nothing -> "not published yet"

  treasuryNote :: Maybe Lovelace -> String
  treasuryNote = case _ of
    Nothing -> ""
    Just amount -> " · " <> formatAda amount <> " requested"

  topDreps p =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text "Largest DReps by voting power" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text ("Voting power " <> powerAsOf p.powerEpoch <> ".") ]
          , HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ HH.th_ [ HH.text "DRep" ]
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Voting power" ]
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Delegators" ]
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Participation" ]
                          ]
                      ]
                  , HH.tbody_ (map drepRow p.topDrepsByPower)
                  ]
              ]
          ]
      ]

  drepRow (DRepSummary d) =
    HH.tr_
      [ HH.td [ HP.class_ (HH.ClassName "max-w-xs") ]
          [ HH.a [ HP.href (drepDetailHrefFor d.id), HP.class_ (HH.ClassName "hover:underline") ]
              [ DRepIdentity.render { givenName: d.givenName, drepId: d.id, hasScript: d.hasScript } ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
          [ HH.text (formatAda d.votingPower) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt d.delegatorCount) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatPercent d.participationRate) ]
      ]

-- | Cele trei lucruri pentru care deschide cineva site-ul. Toate trei sunt despre registru; al
-- | treilea duce în explorer, pentru că acolo se verifică dacă cel care pretinde ceva chiar votează.
useCases :: Array { href :: String, title :: String, body :: String }
useCases =
  [ { href: attestationListPath
    , title: "See who vouched for whom"
    , body: "Every claim on the register: who made it, about whom, whether it was accepted, and whether anyone fought it."
    }
  , { href: writePath
    , title: "Make a claim of your own"
    , body: "Mint a profile, vouch for someone's work, or challenge a claim you believe is false. You sign every transaction yourself."
    }
  , { href: drepListHref
    , title: "Check it against the chain"
    , body: "A profile can claim a governance credential. The explorer shows whether that representative actually votes."
    }
  ]

-- | Indexul, în două jumătăți: întâi registrul — care e produsul — apoi explorerul de guvernanță,
-- | care e contextul în care claim-urile registrului se pot verifica.
-- |
-- | Bara de sus ține cinci destinații în linie și restul într-un meniu, ceea ce e corect pentru o
-- | bară; pagina de pornire e singurul loc unde încape tot, iar asta face meniul o scurtătură în
-- | loc de singura cale.
registryGroups :: Array { title :: String, entries :: Array { href :: String, label :: String, description :: String } }
registryGroups =
  [ { title: "The register"
    , entries:
        [ { href: profileListPath
          , label: "Profiles"
          , description: "Identities. Each one is a token, and whoever holds the token holds the profile."
          }
        , { href: attestationListPath
          , label: "Vouches"
          , description: "Claims about those identities, and whether the subject accepted them."
          }
        , { href: disputeListPath
          , label: "Challenges"
          , description: "Claims someone challenged, with a deposit at stake on the outcome."
          }
        ]
    }
  , { title: "Taking part"
    , entries:
        [ { href: writePath
          , label: "Take action on the register"
          , description: "The nine things you can do here. You sign every transaction yourself."
          }
        , { href: methodologyPath
          , label: "Methodology"
          , description: "Every number on this site resolves to a published formula and its query."
          }
        ]
    }
  ]

governanceGroups :: Array { title :: String, entries :: Array { href :: String, label :: String, description :: String } }
governanceGroups =
  [ { title: "Who votes"
    , entries:
        [ { href: drepListHref
          , label: "Representatives"
          , description: "Everyone registered to vote on behalf of others."
          }
        , { href: spoListPath
          , label: "Stake pools"
          , description: "Pools vote too, on a smaller set of proposals."
          }
        , { href: committeePath
          , label: "Constitutional committee"
          , description: "The body that judges whether a proposal is constitutional."
          }
        ]
    }
  , { title: "What is being decided"
    , entries:
        [ { href: actionListHrefFor emptyGovActionFilters
          , label: "Proposals"
          , description: "Every governance action ever submitted, and what happened to it."
          }
        , { href: voteListHrefFor defaultVoteFilters
          , label: "Votes"
          , description: "Each vote on its own, with the reasoning when one was published."
          }
        , { href: withdrawalListPath
          , label: "Treasury"
          , description: "What was asked of the treasury, and what it actually paid."
          }
        ]
    }
  , { title: "Who stands behind whom"
    , entries:
        [ { href: delegationListPath
          , label: "Delegations"
          , description: "Who handed their voting power to whom, and when."
          }
        , { href: graphPath
          , label: "Delegation graph"
          , description: "The same thing drawn as a picture, around one representative."
          }
        , { href: activityPath
          , label: "Activity"
          , description: "Everything governance did on this chain, newest first."
          }
        ]
    }
  ]
