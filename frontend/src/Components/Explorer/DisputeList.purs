-- | Disputele: `GET /disputes`.
-- |
-- | O dispută e o contestare a unei atestări, cu un DEPOZIT pus la bătaie: cine o deschide riscă
-- | bani, și de-aia depozitul e o coloană și nu o notă de subsol — e singurul lucru care
-- | deosebește o contestare de o părere.
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
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDisputes)
import Capabilities.Query.Gov.Types (DisputePage(..), DisputeRow(..))
import Components.Shared.DRepIdentity (shortId)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Format (formatAda, formatDay, formatInt, humanize, matchLine)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries (RegistryFilters, disputeListHrefFor)
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
  }

data Action
  = Initialize
  | Retry
  | Receive Input

-- | Verde pentru disputa care a căzut (atestarea rămîne), roșu pentru cea confirmată (atestarea
-- | cade). Culoarea urmărește ATESTAREA, nu disputa, pentru că ăsta e lucrul despre care cititorul
-- | vrea să afle.
verdictClass :: Maybe String -> String
verdictClass = case _ of
  Just "upheld" -> "badge-error"
  Just "dismissed" -> "badge-success"
  Just "stale" -> "badge-outline"
  _ -> "badge-warning"

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
    Initialize -> load
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

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Disputes" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "Challenges against attestations. Opening one costs a deposit, which is what \
                  \separates a challenge from an opinion."
              ]
          ]
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading disputes…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The disputes could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(DisputePage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "dispute")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState else table p.items
      , if null p.items then HH.text "" else pager st page
      ]

  emptyState =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "No disputes have been opened yet." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "That is the quiet case, not an empty one: every attestation so far stands unchallenged." ]
          ]
      ]

  table items =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ HH.th_ [ HH.text "Dispute" ]
                          , HH.th_ [ HH.text "Against" ]
                          , HH.th_ [ HH.text "Opened" ]
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Deposit" ]
                          , HH.th_ [ HH.text "Outcome" ]
                          ]
                      ]
                  , HH.tbody_ (map row items)
                  ]
              ]
          ]
      ]

  row (DisputeRow d) =
    HH.tr_
      [ HH.td_
          [ HH.div_ [ HH.text d.name ]
          , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text d.description ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "font-mono text-xs"), HP.title d.target ] [ HH.text (shortId d.target) ]
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
      HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
        [ pagerLink prev hrefFor "Previous"
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text (formatInt p.total <> " in total") ]
        , pagerLink next hrefFor "Next"
        ]

  pagerLink target hrefFor label = case target of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off -> HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]
