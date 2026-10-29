-- | Disputele: `GET /disputes`.
-- |
-- | O dispută e o contestare a unei atestări, cu un DEPOZIT blocat pînă la închidere: de-aia
-- | depozitul e o coloană și nu o notă de subsol — e singurul lucru care deosebește o contestare de
-- | o părere. Blocat, nu riscat: validatorul cere întoarcerea lui pe ORICE verdict, deci nu există
-- | verdict care îl confiscă.
-- |
-- | `verdict` lipsește cît timp disputa e deschisă, iar `staleAfter` e momentul după care o
-- | dispută nedecisă poate fi închisă de oricine. Amândouă descriu un proces în curs, nu date
-- | lipsă, deci se scriu ca atare.
module Components.Explorer.DisputeList
  ( Slot
  , Output
  , _disputeList
  , component
  , verdictClass
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getAttestations, getDisputes)
import Capabilities.Query.Gov.Types (AttestationPage(..), AttestationRow(..), DisputePage(..), DisputeRow(..))
import Components.Shared.DRepIdentity (shortId)
import Components.Shared.Refresh (subscribeRefresh)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), isJust)
import Data.Tuple (Tuple(..))
import Format (formatAda, formatDay, humanize, matchLine)
import Halogen as H
import AppEnv as AppEnv
import Components.Shared.OnchainId as OnchainId
import Components.Shared.Pager as Pager
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Halogen.Store.Monad (class MonadStore)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries
  ( RegistryFilters
  , disputeDetailHrefFor
  , disputeListHrefFor
  , emptyRegistryFilters
  , writeHrefFor
  )
import Store as Store
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_disputeList :: Proxy "disputeList"
_disputeList = Proxy

type Input = RegistryFilters

type State =
  { filters :: RegistryFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError DisputePage
  -- Numele atestărilor contestate, după id. „Against: 648c6a…1f4a3f" nu spune împotriva a CE s-a
  -- deschis disputa, ceea ce e singurul lucru pe care îl caută cineva în tabelul ăsta.
  , names :: Map String String
  }

data Action
  = Initialize
  | Retry
  | Receive Input

-- | Verde pentru disputa respinsă (atestarea rămîne), roșu pentru cea confirmată (atestarea cade).
-- | Culoarea urmărește ATESTAREA, nu disputa, pentru că ăsta e lucrul despre care cititorul vrea să
-- | afle.
-- |
-- | Enumul de pe sîrmă are exact trei valori — `upheld` | `rejected` | `expired` — iar `Nothing`
-- | înseamnă „încă deschisă". Al patrulea cuvînt nu există, deci nu se inventează unul. `expired`
-- | primește o insignă neutră fiindcă o expirare NU e o constatare împotriva nimănui: n-are voie să
-- | arate nici ca un verdict, nici ca o dispută nedecisă.
verdictClass :: Maybe String -> String
verdictClass = case _ of
  Just "upheld" -> "badge-error"
  Just "rejected" -> "badge-success"
  Just "expired" -> "badge-outline"
  _ -> "badge-warning"

component
  :: forall q m
   . MonadQueryGov m
  => MonadStore Store.Action Store.Store m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, page: NotAsked, refreshing: false, names: Map.empty }
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
    Initialize -> do
      -- O scriere confirmată schimbă ce arată ecranul ăsta, iar proiecția vine ~45s după
      -- tranzacție — deci nu se poate încărca o dată și gata.
      subscribeRefresh Retry
      void (H.fork load)
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
    res <- getDisputes st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }
    -- Ca la atestări: o singură cerere, iar eșecul ei lasă identificatorii pe ecran în loc să
    -- strice tabelul.
    when (Map.isEmpty st.names) do
      atts <- getAttestations (emptyRegistryFilters { limit = Just "200" })
      case atts of
        Left _ -> pure unit
        Right (AttestationPage ap) ->
          H.modify_ _ { names = Map.fromFoldable (map (\(AttestationRow a) -> Tuple a.id a.name) ap.items) }

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Challenges" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "Challenges against vouches. Opening one locks a deposit until the challenge \
                  \closes, which is what separates a challenge from an opinion. The deposit comes \
                  \back on every outcome: contesting costs network fees and nothing else."
              ]
          ]
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading challenges…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The challenges could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(DisputePage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "challenge")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState st else table st p.items
      , if null p.items then HH.text "" else pager st page
      ]

  -- Propoziția despre „cazul liniștit" e o afirmație despre REGISTRUL ÎNTREG — „every vouch so far
  -- stands unchallenged" — deci are voie să apară doar cînd lista n-a fost îngustată. Arătată cuiva
  -- care a filtrat și n-a găsit nimic, era pur și simplu falsă, și făcea ecranul să pară rupt în loc
  -- de filtrat.
  emptyState st =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
          ( if hasAnyFilter st.filters then
              [ HH.p_ [ HH.text "No challenges match these filters." ]
              , HH.a
                  [ HP.href (disputeListHrefFor emptyRegistryFilters)
                  , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
                  ]
                  [ HH.text "Clear the filters" ]
              ]
            else
              [ HH.p_ [ HH.text "No challenges have been opened yet." ]
              , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                  [ HH.text "That is the quiet case, not an empty one: every vouch so far stands unchallenged." ]
              ]
          )
      ]

  -- „Filtrat" înseamnă `kind`, `subject` sau `issuer` — singurele care schimbă CE se potrivește.
  -- `order_by`/`sort_order` doar reordonează, iar `limit`/`offset` sînt o fereastră peste
  -- potriviri: o pagină goală de la capătul listei nu e un filtru care n-a prins nimic.
  hasAnyFilter f = isJust f.kind || isJust f.subject || isJust f.issuer

  table st items =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ HH.th_ [ HH.text "Challenge" ]
                          , HH.th_ [ HH.text "Against" ]
                          , HH.th_ [ HH.text "Opened" ]
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Deposit" ]
                          , HH.th_ [ HH.text "Outcome" ]
                          , HH.th_ [ HH.text "Act" ]
                          ]
                      ]
                  , HH.tbody_ (map (row st) items)
                  ]
              ]
          ]
      ]

  target st i = case Map.lookup i st.names of
    Nothing -> idChip i
    Just n ->
      HH.div_
        [ HH.div [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text n ]
        , HH.div [ HP.class_ (HH.ClassName "opacity-70") ] [ idChip i ]
        ]

  -- Un `title` promitea valoarea întreagă „pentru copiat", dar textul unui tooltip nativ nu e
  -- selectabil. Chipul o deschide cu adevărat, cu link și copiere.
  idChip i =
    OnchainId.withChip
      { value: i, shown: shortId i, kind: OnchainId.Asset, explorerBase: AppEnv.explorerBase }

  row st (DisputeRow d) =
    HH.tr_
      [ HH.td_
          -- Numele duce la pagina provocarii. §5.5 din harta API->ecran o cerea ca „the target of
          -- a notification or a shared URL" — pina acum nu exista nicio adresa de dat cuiva.
          [ HH.div_
              [ HH.a
                  [ HP.href (disputeDetailHrefFor d.id)
                  , HP.class_ (HH.ClassName "link link-hover")
                  ]
                  [ HH.text d.name ]
              ]
          , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text d.description ]
          ]
      , HH.td_ [ target st d.target ]
      , HH.td [ HP.class_ (HH.ClassName "text-sm whitespace-nowrap") ]
          [ HH.div [ HP.title d.openedAt ] [ HH.text (formatDay d.openedAt) ]
          , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70"), HP.title d.staleAfter ]
              [ HH.text ("stale after " <> formatDay d.staleAfter) ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ] [ HH.text (formatAda d.deposit) ]
      -- „Still open" e o stare a procesului, nu o valoare lipsă.
      , HH.td_
          [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> verdictClass d.verdict)) ]
              [ HH.text (maybe' d.verdict) ]
          ]
      -- Doar pe disputele încă deschise: a oferi „rezolvă" pe una deja judecată ar fi un buton
      -- care duce la un refuz al serverului.
      , HH.td [ HP.class_ (HH.ClassName "whitespace-nowrap") ]
          [ case d.verdict of
              Just _ -> HH.text ""
              Nothing ->
                HH.span_
                  [ HH.a
                      [ HP.href (writeHrefFor { flow: Just "resolve-dispute", subject: Just d.id })
                      , HP.class_ (HH.ClassName "link link-hover text-xs mr-2")
                      ]
                      [ HH.text "Resolve" ]
                  , HH.a
                      [ HP.href (writeHrefFor { flow: Just "expire-dispute", subject: Just d.id })
                      , HP.class_ (HH.ClassName "link link-hover text-xs")
                      ]
                      [ HH.text "Expire" ]
                  ]
          ]
      ]

  maybe' = case _ of
    Nothing -> "still open"
    Just v -> humanize v

  pager st (DisputePage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = disputeListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      Pager.render
        { total: p.total
        , offset: p.offset
        , shown: length p.items
        , ceiling: offsetCeiling
        , prev
        , next
        , hrefFor
        , noun: "challenge"
        }

