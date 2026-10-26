-- | Bara laterală: șină verticală pe desktop, doc jos pe telefon.
-- |
-- | E elementul care dă structura aspectului din `bjj-frontend` — acolo conținutul stă între o șină
-- | la stânga și bara de sus, iar pe telefon navigarea coboară într-un doc. Fără ea, palmares avea
-- | doar o bară de sus și arăta ca altă aplicație, oricâte clase de stil ar fi împrumutat.
-- |
-- | __O FUNCȚIE PURĂ, nu o componentă.__ Varianta din bjj are 295 de linii cu `Query`, `Output`,
-- | `MonadDomEvent` și `preventDefaultEvent`, fiindcă trimite navigarea prin Halogen. Aici nu e
-- | nevoie: `App.SpaLinkInterceptor` prinde deja orice `<a href="/…">` și îl transformă în
-- | `history.pushState`, deci o ancoră obișnuită navighează fără reîncărcare. Rămân `forall w i`,
-- | zero stare, zero slot — și se poate randa din carcasă fără să treacă nimic prin ea.
-- |
-- | Iconițele vin din setul monocolor al lui bjj, iar `sidebar/README.md` de acolo le dă sursa, deci
-- | maparea nu e ghicită: „practitioners" e de fapt *organization* (oameni), „achievements" e
-- | *medal-alt* (o distincție acordată), „lineage" e un graf. Cele specifice BJJ — centuri, karate,
-- | academii — nu s-au luat.
-- |
-- | Colorarea trece prin mască CSS peste `currentColor`, nu prin `svgMaskStyle`: Tailwind 4 are
-- | utilitare de mască, deci stilul inline de 400 de caractere al lui bjj devine o clasă.
module Components.Layout.Sidebar
  ( render
  ) where

import Prelude

import Data.Array (take)
import Route.GovQueries
  ( emptyActivityFilters
  , emptyDRepFilters
  , emptyGraphFilters
  , emptyMethodologyFilters
  , emptyRegistryFilters
  , emptyWriteFilters
  )
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Route (Route(..))
import Route.Codec (printRoute)

type Entry =
  { route :: Route
  , label :: String
  -- Clasa de mască ÎNTREAGĂ, literal. Nu numele iconiței plus o concatenare — vezi `icon`.
  , mask :: String
  }

-- | Ordinea e cea din bara de sus, fiindcă două ordini diferite pentru aceleași destinații sunt
-- | două hărți mentale. Registrul întâi, guvernanța după — exact ierarhia cerută de owner.
entries :: Array Entry
entries =
  [ { route: Home, label: "Home", mask: "[mask-image:url(/images/sidebar/home.svg)]" }
  , { route: ProfileList emptyRegistryFilters
    , label: "Profiles"
    , mask: "[mask-image:url(/images/sidebar/practitioners.svg)]"
    }
  , { route: AttestationList emptyRegistryFilters
    , label: "Vouches"
    , mask: "[mask-image:url(/images/sidebar/achievements.svg)]"
    }
  , { route: DisputeList emptyRegistryFilters
    , label: "Challenges"
    , mask: "[mask-image:url(/images/sidebar/bell.svg)]"
    }
  , { route: Write emptyWriteFilters, label: "Actions", mask: "[mask-image:url(/images/edit.svg)]" }
  , { route: DRepList emptyDRepFilters
    , label: "Governance"
    , mask: "[mask-image:url(/images/sidebar/dashboard.svg)]"
    }
  , { route: Activity emptyActivityFilters
    , label: "Activity"
    , mask: "[mask-image:url(/images/sidebar/activity.svg)]"
    }
  , { route: Graph emptyGraphFilters
    , label: "Graph"
    , mask: "[mask-image:url(/images/sidebar/lineage.svg)]"
    }
  , { route: Methodology emptyMethodologyFilters
    , label: "Method"
    , mask: "[mask-image:url(/images/sidebar/about.svg)]"
    }
  ]

-- | Pe telefon docul ține cinci, ca în bjj: mai multe și fiecare ar fi sub pragul de atingere.
-- | Restul rămân în hamburgerul barei de sus, care le listează oricum plat.
dockEntries :: Array Entry
dockEntries = take 5 entries

-- | Secțiunea curentă, pe constructor. Un `Eq` pe `Route` ar compara și filtrele, iar atunci
-- | `/profiles?kind=auditor` n-ar mai lumina „Profiles" — ceea ce e exact pe dos.
sameSection :: Route -> Route -> Boolean
sameSection current target = case current, target of
  Home, Home -> true
  ProfileList _, ProfileList _ -> true
  ProfileDetail _, ProfileList _ -> true
  AttestationList _, AttestationList _ -> true
  AttestationDetail _, AttestationList _ -> true
  DisputeList _, DisputeList _ -> true
  Write _, Write _ -> true
  Activity _, Activity _ -> true
  Graph _, Graph _ -> true
  Methodology _, Methodology _ -> true
  -- „Governance" acoperă tot explorerul, nu doar lista de reprezentanți: cineva care s-a dus la
  -- propuneri sau la voturi e tot în secțiunea aia, iar o șină care nu luminează nimic îl lasă fără
  -- reper.
  DRepList _, DRepList _ -> true
  DRepDetail _, DRepList _ -> true
  ActionList _, DRepList _ -> true
  ActionDetail _, DRepList _ -> true
  VoteList _, DRepList _ -> true
  SpoList _, DRepList _ -> true
  Committee, DRepList _ -> true
  TreasuryList _, DRepList _ -> true
  DelegationList _, DRepList _ -> true
  _, _ -> false

-- | Iconița, colorată prin mască peste un fundal de culoare.
-- |
-- | __Clasa de mască vine ÎNTREAGĂ din `entries`, nu construită aici.__ Prima variantă o compunea —
-- | `"[mask-image:url(/images/sidebar/" <> name <> ".svg)]"` — și a ieșit un rând de pătrate pline:
-- | Tailwind scanează TEXTUL surselor, iar o clasă asamblată la runtime nu există nicăieri în text,
-- | deci regula nu se generează, masca nu se aplică, și rămâne doar fundalul colorat. Singura care
-- | mergea era `edit`, scrisă literal pe ramura cealaltă a lui `if`.
-- |
-- | Capcana e generală, nu a acestei componente: orice clasă Tailwind compusă dinamic dispare tăcut.
icon :: forall w i. Boolean -> String -> HH.HTML w i
icon active mask =
  HH.span
    [ HP.class_
        ( HH.ClassName
            ( "w-6 h-6 inline-block shrink-0 [mask-size:contain] [mask-position:center] \
              \[mask-repeat:no-repeat] "
                <> (if active then "bg-primary" else "bg-info/70")
                <> " "
                <> mask
            )
        )
    , HP.attr (HH.AttrName "aria-hidden") "true"
    ]
    []

item :: forall w i. Route -> Entry -> HH.HTML w i
item current e =
  HH.a
    [ HP.href (printRoute e.route)
    , HP.class_
        ( HH.ClassName
            ( "flex flex-col items-center justify-center gap-1 rounded-lg px-2 py-2 "
                <> "transition-colors min-w-0 flex-1 md:flex-none "
                <> if active then "bg-base-100/60 text-primary font-semibold" else "hover:bg-base-100/40"
            )
        )
    , HP.attr (HH.AttrName "aria-current") (if active then "page" else "false")
    ]
    [ icon active e.mask
    , HH.span [ HP.class_ (HH.ClassName "text-[0.65rem] leading-tight truncate max-w-full") ]
        [ HH.text e.label ]
    ]
  where
  active = sameSection current e.route

-- | Șina (md+) și docul (sub md), amândouă fixe.
-- |
-- | `top-16` pe desktop: bara de sus e lipicioasă și are înălțimea aia, iar o șină care pornește de
-- | la zero ar trece pe sub ea. `z-20` stă sub bara de sus (`z-30`) și peste straturile de fundal.
render :: forall w i. Route -> HH.HTML w i
render current =
  HH.div_
    [ HH.nav
        [ HP.class_
            ( HH.ClassName
                "hidden md:flex md:flex-col md:fixed md:left-0 md:top-16 md:w-24 \
                \md:h-[calc(100vh-4rem)] md:py-4 md:gap-1 md:overflow-y-auto \
                \bg-base-200/70 backdrop-blur border-r border-base-content/10 z-20"
            )
        , HP.attr (HH.AttrName "aria-label") "Sections"
        ]
        (map (item current) entries)
    , HH.nav
        [ HP.class_
            ( HH.ClassName
                "md:hidden fixed bottom-0 inset-x-0 flex items-stretch gap-0.5 px-1 py-1 \
                \bg-base-200/90 backdrop-blur border-t border-base-content/10 z-20"
            )
        , HP.attr (HH.AttrName "aria-label") "Sections"
        ]
        (map (item current) dockEntries)
    ]
