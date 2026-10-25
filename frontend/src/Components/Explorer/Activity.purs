-- | Fluxul de activitate: `GET /activity`.
-- |
-- | Singurul ecran care se paginează pe CURSOR, și singurul fără un total. Nu e o scăpare a
-- | serverului: un flux pe cursor n-ar putea număra ce urmează fără să scaneze tot, iar `D-18`
-- | spune explicit că `total` vine `null` aici. Deci nu există „pagina 3 din 40" și nu se poate
-- | sări înapoi cu un offset — se merge înainte, din cursor în cursor, și se poate reveni la
-- | început. Ăsta e contractul, și ecranul îl spune în loc să-l ascundă.
-- |
-- | Patru din unsprezece feluri de eveniment măsurate n-au nici tranzacție nici actor: sunt
-- | evenimente de GRANIȚĂ DE EPOCĂ — o acțiune care expiră, un DRep care devine inactiv — pe care
-- | nu le-a provocat nimeni. Rîndul lor arată altfel, pentru că asta ESTE altceva.
module Components.Explorer.Activity
  ( Slot
  , Output
  , _activity
  , component
  , eventKinds
  , eventClass
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getActivity)
import Capabilities.Query.Gov.Types (ActivityEvent(..), ActivityPage(..), ChainPoint(..))
import Components.Shared.DRepIdentity (shortId)
import Data.Array (elem, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..), isJust, maybe)
import Data.String as String
import Format (formatDay, humanize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Route (Route)
import Components.Explorer.DelegationList (isStandingChoice, standingLabel)
import Route.GovQueries (ActivityFilters, activityHrefFor, emptyActivityFilters, toggleIn)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_activity :: Proxy "activity"
_activity = Proxy

type Input = ActivityFilters

type State =
  { filters :: ActivityFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError ActivityPage
  }

data Action
  = Initialize
  | Retry
  | Receive Input

-- | Cele treisprezece feluri pe care feed-ul le produce, în ordinea ciclului de viață. Două dintre
-- | ele nu s-au întîmplat niciodată pe preprod, și rămîn în listă: un filtru care întoarce zero e
-- | un răspuns, iar un filtru care lipsește e o întrebare pe care nu o poți pune.
eventKinds :: Array String
eventKinds =
  [ "drep_registered"
  , "drep_updated"
  , "drep_retired"
  , "delegation_changed"
  , "vote_cast"
  , "gov_action_proposed"
  , "gov_action_ratified"
  , "gov_action_enacted"
  , "gov_action_expired"
  , "gov_action_dropped"
  , "committee_authorized"
  , "committee_resigned"
  , "treasury_withdrawal_enacted"
  ]

-- | Culoarea spune ce fel de lucru s-a întîmplat, nu dacă e bun: verde pentru ce a intrat în
-- | vigoare, roșu pentru ce s-a încheiat fără rezultat, neutru pentru restul.
eventClass :: String -> String
eventClass = case _ of
  "gov_action_enacted" -> "badge-success"
  "gov_action_ratified" -> "badge-success"
  "treasury_withdrawal_enacted" -> "badge-success"
  "gov_action_expired" -> "badge-error"
  "gov_action_dropped" -> "badge-error"
  "drep_retired" -> "badge-error"
  "committee_resigned" -> "badge-error"
  "vote_cast" -> "badge-info"
  _ -> "badge-outline"

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, page: NotAsked, refreshing: false }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
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
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters }
        load

  load = do
    st <- H.get
    H.modify_ \s0 -> case s0.page of
      Success _ -> s0 { refreshing = true }
      _ -> s0 { page = Loading }
    res <- getActivity st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ header st
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  header st =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Activity" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "Everything governance did on this chain, newest first — registrations, delegations, \
              \votes, and the epoch boundaries where proposals quietly expire."
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-1") ] (map (kindChip st) eventKinds)
      ]

  -- Filtrele sunt pastile, nu o bară laterală: sunt treisprezece valori fără numere lîngă ele
  -- (feed-ul n-are faceturi), iar o bară laterală pentru treisprezece comutatoare ar costa un
  -- ecran de derulat înainte de primul eveniment.
  kindChip st kind =
    let
      on = elem kind st.filters.event_type
      next = st.filters { event_type = toggleIn kind st.filters.event_type, before = Nothing }
    in
      HH.a
        [ HP.href (activityHrefFor next)
        , HP.class_ (HH.ClassName ("badge badge-sm cursor-pointer " <> if on then "badge-primary" else "badge-outline"))
        ]
        [ HH.text (humanize kind) ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading activity…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The activity feed could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st (ActivityPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ if st.refreshing then
          HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
            [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs mr-2") ] []
            , HH.text "Updating…"
            ]
        else HH.text ""
      , if null p.items then emptyState st
        else
          HH.ul [ HP.class_ (HH.ClassName "card bg-base-200 card-body gap-0 divide-y divide-base-300") ]
            (map eventRow p.items)
      , cursorPager st p
      ]

  emptyState st =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
          [ HH.p_
              [ HH.text
                  ( if null st.filters.event_type then "Nothing has happened yet."
                    else "No events of these kinds have happened yet."
                  )
              ]
          , if null st.filters.event_type then HH.text ""
            else
              HH.a
                [ HP.href (activityHrefFor emptyActivityFilters)
                , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
                ]
                [ HH.text "Show every kind" ]
          ]
      ]

  eventRow (ActivityEvent e) =
    let
      ChainPoint at = e.at
    in
      HH.li [ HP.class_ (HH.ClassName "py-2 flex flex-wrap items-baseline gap-x-3 gap-y-1") ]
        [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> eventClass e.eventType)) ]
            [ HH.text (humanize e.eventType) ]
        , HH.span [ HP.class_ (HH.ClassName "text-sm") ] [ actorText e ]
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70 whitespace-nowrap") ]
            [ HH.text ("epoch " <> show at.epoch <> " · " <> formatDay at.time) ]
        -- Un eveniment de graniță de epocă nu are tranzacție, și se SPUNE: altfel pare că lipsește
        -- un link pe care l-ar fi putut avea.
        , case at.txHash of
            Nothing ->
              HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
                [ HH.text "at the epoch boundary, no transaction" ]
            Just h ->
              HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70 font-mono break-all") ]
                [ HH.text ("tx " <> shortId h) ]
        ]

  -- Actorul și ținta se leagă doar cînd se poate: un `stake_address` n-are pagină în produs, o
  -- acțiune și un DRep au.
  actorText e = case e.actorId, e.targetId of
    Nothing, _ -> HH.span [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "no actor — the chain did this on its own" ]
    Just a, Nothing -> idLink a
    Just a, Just t ->
      HH.span_ [ idLink a, HH.text " → ", idLink t ]

  -- Ce poartă feed-ul în `actor_id`/`target_id` depinde de felul evenimentului, iar SQL-ul care îl
  -- produce o spune: „un credential în hex, o adresă de stake în bech32, sau un id de acțiune de
  -- guvernanță". Măsurat, nici unul din cele trei nu e linkabil aici:
  --
  --   * DRep-ii vin ca hash de credential în hex (56 de caractere), nu ca `drep1…`, iar forma
  --     bech32 cere să știm dacă e cheie sau script — informație pe care rîndul n-o poartă;
  --   * acțiunile vin ca id INTERN al indexului (131, 109), nu ca `txhash#index`, deci nu se pot
  --     cere de la `/gov-action/{id}`;
  --   * adresele de stake n-au pagină în produs.
  --
  -- Deci nimic nu se linkează, și fiecare se NUMEȘTE în schimb — un „131" singur pe rînd s-ar citi
  -- ca o epocă sau ca un număr de voturi. Când feed-ul va purta identificatori publici, linkurile
  -- se adaugă aici și nicăieri altundeva.
  idLink i
    | isStandingChoice i = HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ] [ HH.text (standingLabel i) ]
    | isDigits i =
        HH.span
          [ HP.class_ (HH.ClassName "text-xs opacity-70")
          , HP.title "The index's own id for this proposal. The feed does not carry the on-chain action id."
          ]
          [ HH.text ("proposal " <> i) ]
    | String.take 5 i == "stake" =
        HH.span [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70"), HP.title i ] [ HH.text (shortId i) ]
    | otherwise =
        HH.span [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70"), HP.title i ]
          [ HH.text ("credential " <> shortId i) ]

  isDigits = isJust <<< Int.fromString

  -- Nu „Previous/Next": cu un cursor nu există înapoi, doar „de la început". A desena un buton
  -- „Previous" dezactivat ar promite o navigare care nu există în contract.
  cursorPager st p =
    HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-center justify-between gap-2") ]
      [ case st.filters.before of
          Nothing -> HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text "Newest first." ]
          Just _ ->
            HH.a
              [ HP.href (activityHrefFor (st.filters { before = Nothing })), HP.class_ (HH.ClassName "btn btn-sm") ]
              [ HH.text "Back to newest" ]
      , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text (maybe "End of the feed." (const "This feed is paged by cursor, so there is no page count.") p.nextCursor) ]
      , case p.nextCursor of
          Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text "Older" ]
          Just c ->
            HH.a
              [ HP.href (activityHrefFor (st.filters { before = Just c })), HP.class_ (HH.ClassName "btn btn-sm") ]
              [ HH.text "Older" ]
      ]
