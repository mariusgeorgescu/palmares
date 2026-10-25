-- | Sertarul de activitate: un buton flotant și un panou care intră din dreapta cu ce s-a întîmplat
-- | recent pe lanț.
-- |
-- | Portat din `bjj-frontend/src/Components/Home.purs` (`renderActivityDrawerHeader`,
-- | `renderActivityDrawerToggle`). CSS-ul lui — `activity-fab-pulse`, `feed-live-dot`,
-- | `feed-item-enter` — era deja portat; lipsea componenta.
-- |
-- | __L-am respins o dată, pe o premisă pe care n-am verificat-o:__ că butonul flotant de la
-- | `bottom-24 right-4` s-ar bate cu docul de pe telefon. Codul lui bjj spune contrariul — el
-- | stivuiește butoanele la `bottom-24` și `bottom-40` TOCMAI fiindcă are și el un doc jos. Adică
-- | tiparul rezolvase deja coliziunea pe care o invocam. Pe desktop coboară la `bottom-6`, unde nu
-- | mai e niciun doc de ocolit.
-- |
-- | De ce un sertar și nu încă un ecran: `/activity` există deja și e paginat pe cursor. Sertarul
-- | răspunde la altă întrebare — „ce s-a întîmplat chiar acum, fără să plec de unde sînt" — iar
-- | asta e exact ce face un registru să pară viu și nu o arhivă.
module Components.Layout.ActivityDrawer
  ( Slot
  , _activityDrawer
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getActivity)
import Capabilities.Query.Gov.Types (ActivityEvent(..), ActivityPage(..), ChainPoint(..))
import Data.Array (null, take)
import Data.Const (Const)
import Data.Maybe (Maybe(..))
import Effect.Class (class MonadEffect, liftEffect)
import Data.Either (Either(..))
import Format (formatDay, humanize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Route.GovQueries (emptyActivityFilters)
import Type.Proxy (Proxy(..))
import Web.HTML.HTMLElement as HTMLElement
import Web.UIEvent.KeyboardEvent as KE

type Slot = H.Slot (Const Void) Void Unit

drawerRef :: H.RefLabel
drawerRef = H.RefLabel "activityDrawer"

_activityDrawer :: Proxy "activityDrawer"
_activityDrawer = Proxy

type State =
  { open :: Boolean
  , page :: RemoteData ApiErrorLike ActivityPage
  }

-- | Eroarea nu se arată în sertar, deci nu-i trebuie forma: un sertar care explică un 503 e un
-- | sertar care cere atenție pentru ceva ce utilizatorul n-a cerut. Dacă nu se încarcă, nu se
-- | deschide nimic și bara rămîne cum era.
type ApiErrorLike = String

data Action
  = Toggle
  | Close
  | KeyPressed KE.KeyboardEvent

-- | Cîte evenimente încap într-un sertar înainte să devină o listă. Zece: restul e la `/activity`,
-- | iar sertarul are un link acolo.
shown :: Int
shown = 10

component
  :: forall q i o m
   . MonadQueryGov m
  => MonadEffect m
  => H.Component q i o m
component =
  H.mkComponent
    { initialState: \_ -> { open: false, page: NotAsked }
    , render
    , eval: H.mkEval H.defaultEval { handleAction = handleAction }
    }
  where
  handleAction = case _ of
    Close -> H.modify_ _ { open = false }

    KeyPressed ev -> when (KE.key ev == "Escape") (H.modify_ _ { open = false })

    -- Se încarcă la DESCHIDERE, nu la montare: altfel fiecare pagină ar plăti un apel pentru un
    -- panou pe care poate nimeni nu-l deschide.
    Toggle -> do
      st <- H.get
      if st.open then H.modify_ _ { open = false }
      else do
        H.modify_ _ { open = true, page = Loading }
        -- FOCUSUL pe panou, la deschidere. Fără el `Escape` nu ajunge nicăieri: tasta merge la
        -- elementul focalizat, iar acela rămâne butonul de sub strat. E și regula pentru un
        -- `role="dialog"` — un dialog care se deschide fără focus lasă cititorul de ecran în
        -- pagina de dedesubt.
        H.getHTMLElementRef drawerRef >>= case _ of
          Nothing -> pure unit
          Just el -> liftEffect (HTMLElement.focus el)
        res <- getActivity emptyActivityFilters
        H.modify_ _
          { page = case res of
              Left _ -> Failure "could not load"
              Right p -> Success p
          }

  render st =
    HH.div_
      [ fab st
      , if st.open then drawer st else HH.text ""
      ]

  -- Butonul flotant, cu inelul care pulsează. `bottom-24` pe telefon ca să treacă peste doc,
  -- `md:bottom-6` pe desktop unde nu există doc — exact pozițiile din bjj, și din același motiv.
  fab st =
    HH.div
      [ HP.class_
          ( HH.ClassName
              ( "fixed bottom-24 right-4 md:bottom-6 md:right-6 z-20 "
                  <> (if st.open then "hidden" else "block")
              )
          )
      ]
      [ HH.div [ HP.class_ (HH.ClassName "relative") ]
          [ HH.span
              [ HP.class_
                  ( HH.ClassName
                      "absolute inset-0 rounded-full bg-primary/40 activity-fab-pulse \
                      \pointer-events-none"
                  )
              , HP.attr (HH.AttrName "aria-hidden") "true"
              ]
              []
          , HH.button
              [ HP.type_ HP.ButtonButton
              , HP.class_ (HH.ClassName "btn btn-primary btn-circle shadow-lg relative")
              , HE.onClick \_ -> Toggle
              , HP.attr (HH.AttrName "aria-label") "Show recent activity"
              ]
              [ HH.span
                  [ HP.class_
                      ( HH.ClassName
                          "w-5 h-5 inline-block bg-current [mask-image:url(/images/sidebar/activity.svg)] \
                          \[mask-size:contain] [mask-position:center] [mask-repeat:no-repeat]"
                      )
                  , HP.attr (HH.AttrName "aria-hidden") "true"
                  ]
                  []
              ]
          ]
      ]

  drawer st =
    HH.div
      [ HP.ref drawerRef
      , HP.class_ (HH.ClassName "fixed inset-0 z-40")
      , HP.attr (HH.AttrName "role") "dialog"
      , HP.attr (HH.AttrName "aria-modal") "true"
      , HP.attr (HH.AttrName "aria-label") "Recent activity"
      , HP.tabIndex 0
      , HE.onKeyDown KeyPressed
      ]
      [ HH.div
          [ HP.class_ (HH.ClassName "absolute inset-0 bg-black/40")
          , HE.onClick \_ -> Close
          ]
          []
      , HH.div
          [ HP.class_
              ( HH.ClassName
                  "absolute right-0 top-0 h-full w-full sm:w-96 bg-base-100 shadow-2xl \
                  \overflow-y-auto animate-slide-in-right"
              )
          ]
          [ header
          , content st
          ]
      ]

  header =
    HH.div
      [ HP.class_
          ( HH.ClassName
              "sticky top-0 z-10 flex items-center justify-between p-4 border-b \
              \border-base-300 bg-base-100/90 backdrop-blur"
          )
      ]
      [ HH.div [ HP.class_ (HH.ClassName "flex items-center gap-2") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "text-base font-bold") ] [ HH.text "Activity" ]
          , HH.div
              [ HP.class_
                  ( HH.ClassName
                      "flex items-center gap-1.5 text-xs font-semibold text-success uppercase \
                      \tracking-wider"
                  )
              ]
              [ HH.span [ HP.class_ (HH.ClassName "feed-live-dot") ] []
              , HH.text "Live"
              ]
          ]
      , HH.button
          [ HP.type_ HP.ButtonButton
          , HP.class_ (HH.ClassName "btn btn-sm btn-circle btn-ghost")
          , HE.onClick \_ -> Close
          , HP.attr (HH.AttrName "aria-label") "Close recent activity"
          ]
          [ HH.text "×" ]
      ]

  content st = case st.page of
    NotAsked -> note "Nothing loaded yet."
    Loading ->
      HH.div [ HP.class_ (HH.ClassName "p-4") ]
        [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-sm") ] [] ]
    Failure _ -> note "The activity feed did not load. The register itself is unaffected."
    Success (ActivityPage p) ->
      if null p.items then note "Nothing has happened yet."
      else
        HH.div_
          [ HH.ul [ HP.class_ (HH.ClassName "divide-y divide-base-300") ]
              (map row (take shown p.items))
          , HH.div [ HP.class_ (HH.ClassName "p-4") ]
              [ HH.a
                  [ HP.href "/activity", HP.class_ (HH.ClassName "btn btn-sm btn-block btn-ghost") ]
                  [ HH.text "See the whole feed" ]
              ]
          ]

  note t = HH.p [ HP.class_ (HH.ClassName "p-4 text-sm opacity-70") ] [ HH.text t ]

  -- Fiecare rînd intră alunecînd, ca în bjj. E singurul loc din produs unde o animație spune ceva:
  -- un flux care se mișcă arată că registrul e viu, iar unul static arată ca o arhivă.
  row (ActivityEvent e) =
    let
      ChainPoint at = e.at
    in
      HH.li [ HP.class_ (HH.ClassName "px-4 py-3 feed-item-enter") ]
        [ HH.div [ HP.class_ (HH.ClassName "flex items-baseline gap-2 flex-wrap") ]
            [ HH.span [ HP.class_ (HH.ClassName "badge badge-sm") ]
                [ HH.text (humanize e.eventType) ]
            , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70 whitespace-nowrap") ]
                [ HH.text ("epoch " <> show at.epoch <> " · " <> formatDay at.time) ]
            ]
        ]
