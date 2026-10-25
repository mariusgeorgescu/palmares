-- | Căutarea unificată, în bara de sus: un câmp, un apel, șase grupuri.
-- |
-- | Nu e o paletă modală. Un câmp vizibil face același lucru cu mai puțin cod decât un strat modal
-- | cu capcană de focus și cu propria stare de deschis/închis — și scurtătura rămâne: `⌘K` (sau
-- | `Ctrl-K`) pune focusul aici, `Esc` golește.
-- |
-- | Apelul e amânat cu 250 ms după ultima tastă. Fără asta, „intersect" ar fi zece interogări pe un
-- | API al cărui `/search` lovește aceeași bază de date din care se servesc ecranele.
module Components.Layout.SearchBox
  ( Slot
  , Output
  , _searchBox
  , component
  , hrefForHit
  , debounceMs
  ) where

import Prelude

import Capabilities.Delay (class MonadDelay, delayMs)
import Capabilities.DomEvent (class MonadDomEvent, preventDefaultEvent)
import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, searchAll)
import Capabilities.Query.Gov.Types (SearchGroup(..), SearchHit(..), SearchResults(..))
import Data.Array (filter, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Data.String as String
import Effect.Class (class MonadEffect, liftEffect)
import Format (formatInt, humanize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Subscription as HS
import Network.RemoteData (RemoteData(..))
import Route.GovQueries (actionDetailHrefFor, drepDetailHrefFor)
import Type.Proxy (Proxy(..))
import Web.Event.EventTarget (addEventListener, eventListener)
import Web.HTML (window)
import Web.HTML.HTMLElement as HTMLElement
import Web.HTML.Window as Window
import Web.UIEvent.KeyboardEvent as KE
import Web.UIEvent.KeyboardEvent.EventTypes as KET

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_searchBox :: Proxy "searchBox"
_searchBox = Proxy

-- | Cât se așteaptă după ultima tastă. 250 ms e sub pragul la care un om simte o pauză, și peste
-- | durata unei tastări rapide.
debounceMs :: Milliseconds
debounceMs = Milliseconds 250.0

inputRef :: H.RefLabel
inputRef = H.RefLabel "searchInput"

type State =
  { draft :: String
  , results :: RemoteData ApiError SearchResults
  , open :: Boolean
  -- Jetonul de debounce: fiecare tastă îl incrementează, iar interogarea pornește doar dacă n-a
  -- mai apărut alta în timpul așteptării. Fără el, fiecare tastă ar ajunge la server.
  , seq :: Int
  }

data Action
  = Initialize
  | DraftChanged String
  | Fire Int
  | KeyPressed KE.KeyboardEvent
  | GlobalKey KE.KeyboardEvent
  | Close
  | Dismiss

-- | Unde duce un rezultat. Doar două feluri au ecran livrat; restul se arată fără link, în loc să
-- | ducă la „not found".
hrefForHit :: SearchHit -> Maybe String
hrefForHit (SearchHit h) = case h.targetKind of
  "drep" -> Just (drepDetailHrefFor h.targetId)
  "gov_action" -> Just (actionDetailHrefFor h.targetId)
  _ -> Nothing

component
  :: forall q i m
   . MonadEffect m
  => MonadDelay m
  => MonadDomEvent m
  => MonadQueryGov m
  => H.Component q i Output m
component =
  H.mkComponent
    { initialState: const { draft: "", results: NotAsked, open: false, seq: 0 }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  handleAction = case _ of
    Initialize -> do
      -- Un singur ascultător pe fereastră, ca `⌘K` să funcționeze de oriunde din pagină.
      emitter <- liftEffect do
        { emitter, listener } <- HS.create
        target <- Window.toEventTarget <$> window
        l <- eventListener \ev -> case KE.fromEvent ev of
          Nothing -> pure unit
          Just ke -> HS.notify listener ke
        addEventListener KET.keydown l false target
        pure emitter
      _ <- H.subscribe (GlobalKey <$> emitter)
      pure unit

    GlobalKey ev ->
      when ((KE.metaKey ev || KE.ctrlKey ev) && String.toLower (KE.key ev) == "k") do
        preventDefaultEvent (KE.toEvent ev)
        H.getHTMLElementRef inputRef >>= case _ of
          Nothing -> pure unit
          Just el -> liftEffect (HTMLElement.focus el)

    DraftChanged draft -> do
      st <- H.get
      let next = st.seq + 1
      H.modify_ _ { draft = draft, seq = next, open = draft /= "" }
      if String.length (String.trim draft) < 2 then
        H.modify_ _ { results = NotAsked }
      else handleAction (Fire next)

    -- Așteaptă, apoi verifică dacă între timp a mai venit o tastă. Dacă da, cererea asta e moartă.
    Fire token -> do
      delayMs debounceMs
      st <- H.get
      when (st.seq == token) do
        H.modify_ _ { results = Loading }
        res <- searchAll (String.trim st.draft)
        latest <- H.get
        when (latest.seq == token) do
          H.modify_ _
            { results = case res of
                Left e -> Failure e
                Right r -> Success r
            }

    -- Escape ÎNCHIDE, nu golește: „vreau să văd pagina de sub panou" nu înseamnă „aruncă ce am
    -- scris". Golirea rămâne pentru clicul pe un rezultat, unde oricum pleci de pe ecran.
    KeyPressed ev ->
      when (KE.key ev == "Escape") (handleAction Close)

    Close -> H.modify_ _ { open = false }

    Dismiss -> H.modify_ _ { draft = "", results = NotAsked, open = false }

  render st =
    -- `onKeyDown` stă și pe înveliș, nu doar pe câmp: după un Tab în panou, Escape trebuie să
    -- închidă tot de acolo, nu doar cât timp focusul e în input.
    HH.div [ HP.class_ (HH.ClassName "relative"), HE.onKeyDown KeyPressed ]
      [ HH.input
          [ HP.type_ HP.InputSearch
          , HP.ref inputRef
          , HP.class_ (HH.ClassName "input input-bordered input-sm w-28 sm:w-48 lg:w-64 lg:pr-12")
          , HP.placeholder "Search"
          , HP.value st.draft
          , HE.onValueInput DraftChanged
          , HE.onKeyDown KeyPressed
          ]
      -- Scurtătura se arată ca tastă, nu ca text în placeholder: pe telefon nu există ⌘, iar un
      -- placeholder care spune „Search  ⌘K" acolo e o instrucțiune pentru o tastatură inexistentă.
      -- `pointer-events-none` ca eticheta să nu fure clicul pe câmp.
      , HH.span
          [ HP.class_
              (HH.ClassName "hidden lg:flex absolute right-2 top-1/2 -translate-y-1/2 pointer-events-none opacity-70 text-xs")
          , HP.attr (HH.AttrName "aria-hidden") "true"
          ]
          [ HH.text "⌘K" ]
      , if st.open then panel st else HH.text ""
      ]

  panel st =
    HH.div
      [ HP.class_
          ( HH.ClassName
              -- Pe telefon panoul se ancorează de ECRAN, nu de câmp: câmpul alunecă spre stânga
              -- când linkurile intră în meniu, iar un panou de lățime fixă ancorat `right-0` ar
              -- ieși din ecran exact acolo unde nu există derulare orizontală.
              "fixed inset-x-2 top-28 w-auto sm:absolute sm:inset-x-auto sm:right-0 sm:top-full \
              \sm:w-96 sm:mt-1 max-h-96 overflow-y-auto z-50 card bg-base-100 shadow-xl \
              \border border-base-300"
          )
      ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-2 gap-1") ]
          [ case st.results of
              NotAsked ->
                HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70 p-2") ]
                  [ HH.text "Type at least two characters." ]
              Loading ->
                HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70 p-2") ] [ HH.text "Searching…" ]
              Failure e ->
                HH.p [ HP.class_ (HH.ClassName "text-xs p-2") ] [ HH.text (renderApiError e) ]
              Success r -> results r
          ]
      ]

  results (SearchResults r) =
    let
      groups =
        [ { label: "DReps", group: r.dreps }
        , { label: "Governance actions", group: r.govActions }
        , { label: "Stake pools", group: r.spos }
        , { label: "Committee members", group: r.committeeMembers }
        , { label: "Profiles", group: r.profiles }
        , { label: "Attestations", group: r.attestations }
        ]

      nonEmpty = filter (\g -> case g.group of SearchGroup s -> not (null s.items)) groups
    in
      if null nonEmpty then
        HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70 p-2") ] [ HH.text "Nothing matches." ]
      else HH.div [ HP.class_ (HH.ClassName "space-y-2") ] (map groupBlock nonEmpty)

  groupBlock g = case g.group of
    SearchGroup s ->
      HH.div_
        [ HH.div [ HP.class_ (HH.ClassName "flex items-baseline justify-between px-2 pt-1") ]
            [ HH.span [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-70") ]
                [ HH.text g.label ]
            -- Numărul vine din grup, nu din totalul de sus: grupul poate fi tăiat de
            -- `limit_per_group`, iar „3 din 12" e altceva decât „3".
            , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
                [ HH.text (formatInt s.total) ]
            ]
        , HH.div_ (map hitRow s.items)
        ]

  hitRow hit@(SearchHit h) =
    let
      body =
        [ HH.div [ HP.class_ (HH.ClassName "text-sm truncate") ]
            [ HH.text (fromMaybe h.id h.title) ]
        , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 truncate") ]
            [ HH.text (fromMaybe h.id h.subtitle) ]
        , if null h.badges && h.status == Nothing then HH.text ""
          else
            HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-1 pt-0.5") ]
              ( map badge h.badges
                  <>
                    ( case h.status of
                        Nothing -> []
                        Just s -> [ badge s ]
                    )
              )
        ]
    in
      case hrefForHit hit of
        Just href ->
          HH.a
            [ HP.href href
            , HP.class_ (HH.ClassName "block rounded px-2 py-1 hover:bg-base-200")
            , HE.onClick (const Dismiss)
            ]
            body
        -- Un fel de obiect fără ecran nu devine link spre „not found": se arată, inert.
        Nothing ->
          HH.div [ HP.class_ (HH.ClassName "block rounded px-2 py-1 opacity-70") ] body

  badge t =
    HH.span [ HP.class_ (HH.ClassName "badge badge-xs badge-outline") ] [ HH.text (humanize t) ]
