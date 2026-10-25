-- | Delegările de putere de vot: `GET /delegations`.
-- |
-- | Trei lucruri pe care forma datelor le impune ecranului, toate măsurate pe 200 de rînduri:
-- |
-- |   * __ținta nu e întotdeauna un DRep.__ `always_abstain` și `always_no_confidence` sînt
-- |     alegeri standard ale protocolului, nu reprezentanți, deci nu au pagină și nu se linkează;
-- |   * __suma lipsește la 43 din 200.__ Vine din `epoch_stake`, iar epoca poate să n-aibă rîndul;
-- |   * __numele ținte lipsește la 182 din 200.__ Numele e excepția, nu regula, deci coloana e
-- |     construită în jurul identificatorului și pune numele deasupra lui cînd există.
module Components.Explorer.DelegationList
  ( Slot
  , Output
  , _delegationList
  , component
  , isStandingChoice
  , standingLabel
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDelegations)
import Capabilities.Query.Gov.Types (ChainPoint(..), DelegationPage(..), DelegationRow(..))
import Components.Shared.DRepIdentity (shortId)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Format (formatAda, formatDay, matchLine, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries (DelegationFilters, delegationListHrefFor, drepDetailHrefFor)
import Type.Proxy (Proxy(..))

-- | Cele două alegeri standard ale protocolului NU sînt DRep-i: n-au pagină, deci nu primesc link.
-- |
-- | Valorile sînt cele MĂSURATE, nu cele din design: serverul scrie `drep_always_abstain`, cu
-- | prefix. Fără prefix verificarea nu prinde nimic, iar ecranul linkează 124 din 200 de rînduri
-- | către o pagină de DRep care nu există.
isStandingChoice :: String -> Boolean
isStandingChoice t = t == "drep_always_abstain" || t == "drep_always_no_confidence"

-- | Numele în cuvinte. Identificatorul din protocol e corect dar nu se citește.
standingLabel :: String -> String
standingLabel = case _ of
  "drep_always_abstain" -> "always abstain"
  "drep_always_no_confidence" -> "always no confidence"
  other -> other

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_delegationList :: Proxy "delegationList"
_delegationList = Proxy

type Input = DelegationFilters

type State =
  { filters :: DelegationFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError DelegationPage
  }

data Action
  = Initialize
  | Retry
  | Receive Input

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
    res <- getDelegations st.filters
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
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Delegations" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "Who handed their voting power to whom, and when. A delegation can also go to one of \
              \the two standing choices — abstain, or no confidence — which are not representatives."
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-2 items-center") ]
          [ currentToggle st
          , case st.filters.drep_id of
              Nothing -> HH.text ""
              Just d ->
                HH.a
                  [ HP.href (delegationListHrefFor (st.filters { drep_id = Nothing, offset = Nothing }))
                  , HP.class_ (HH.ClassName "btn btn-sm btn-ghost")
                  ]
                  [ HH.text ("Showing one DRep only · " <> shortId d <> " ✕") ]
          ]
      ]

  -- „Doar cele în vigoare" e întrebarea obișnuită, dar istoricul e motivul pentru care există
  -- ecranul, deci comutatorul e vizibil, nu un filtru ascuns într-o bară laterală.
  currentToggle st =
    let
      on = st.filters.is_current == Just "true"
      href = delegationListHrefFor (st.filters { is_current = if on then Nothing else Just "true", offset = Nothing })
    in
      HH.a
        [ HP.href href
        , HP.class_ (HH.ClassName ("btn btn-sm " <> if on then "btn-primary" else "btn-ghost"))
        ]
        [ HH.text (if on then "Current delegations only" else "Show current only") ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading delegations…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The delegations could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(DelegationPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "delegation")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState st else table st page
      , if null p.items then HH.text "" else pager st page
      ]

  emptyState st =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
          [ HH.p_
              [ HH.text
                  ( if hasAnyFilter st.filters then "No delegations match these filters."
                    else "No delegations have been recorded yet."
                  )
              ]
          , if hasAnyFilter st.filters then
              HH.a
                [ HP.href (delegationListHrefFor { drep_id: Nothing, is_current: Nothing, order_by: Nothing, sort_order: Nothing, limit: Nothing, offset: Nothing })
                , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
                ]
                [ HH.text "Clear the filters" ]
            else HH.text ""
          ]
      ]

  hasAnyFilter f = f.drep_id /= Nothing || f.is_current /= Nothing

  table st (DelegationPage p) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ sortHeader st "stake_address" "Delegator" ""
                          , HH.th_ [ HH.text "Delegated to" ]
                          , sortHeader st "lovelace" "Amount" "text-right"
                          , sortHeader st "at" "When" "text-right"
                          , HH.th_ [ HH.text "Still in force" ]
                          ]
                      ]
                  , HH.tbody_ (map row p.items)
                  ]
              ]
          ]
      ]

  sortHeader st key label align =
    let
      active = st.filters.order_by == Just key
      dir = fromMaybe "desc" st.filters.sort_order
      nextDir = if active && dir == "desc" then "asc" else "desc"
      arrow = if active then (if dir == "desc" then " ↓" else " ↑") else ""
      href = delegationListHrefFor (st.filters { order_by = Just key, sort_order = Just nextDir, offset = Nothing })
    in
      HH.th [ HP.class_ (HH.ClassName align) ]
        [ HH.a
            [ HP.href href
            , HP.class_ (HH.ClassName ("link link-hover" <> if active then " font-bold" else ""))
            , HP.attr (HH.AttrName "aria-sort")
                (if active then (if dir == "desc" then "descending" else "ascending") else "none")
            ]
            [ HH.text (label <> arrow) ]
        ]

  row (DelegationRow d) =
    let
      ChainPoint at = d.at
    in
      HH.tr_
        [ HH.td [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ] [ HH.text d.stakeAddress ]
        , HH.td_ [ targetCell d ]
        -- „unknown", nu „0 ADA": suma lipsește pentru că epoca n-are rîndul, nu pentru că omul a
        -- delegat zero.
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
            [ HH.text (maybe "unknown" formatAda d.lovelace) ]
        , HH.td [ HP.class_ (HH.ClassName "text-right text-sm whitespace-nowrap") ]
            [ HH.div_ [ HH.text ("epoch " <> show at.epoch) ]
            , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text (formatDay at.time) ]
            ]
        , HH.td_
            [ HH.span
                [ HP.class_ (HH.ClassName ("badge badge-sm " <> if d.isCurrent then "badge-success" else "badge-outline")) ]
                [ HH.text (if d.isCurrent then "yes" else "superseded") ]
            ]
        ]

  -- Cele două opțiuni standard NU sînt DRep-i: nu au pagină, deci nu primesc link. Un link mort
  -- către `/dreps/always_abstain` ar fi o pagină de eroare pentru 85% din puterea delegată.
  targetCell d =
    if isStandingChoice d.target then
      HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ]
        [ HH.text (standingLabel d.target) ]
    else
      HH.div_
        [ case d.targetName of
            Nothing -> HH.text ""
            Just n -> HH.div_ [ HH.text n ]
        , HH.a
            [ HP.href (drepDetailHrefFor d.target)
            , HP.class_ (HH.ClassName "link link-hover font-mono text-xs break-all")
            ]
            [ HH.text d.target ]
        ]

  pager st (DelegationPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = delegationListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
        [ pagerLink prev hrefFor "Previous"
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text
                ( case next of
                    Just _ -> pluralize p.total "delegation" <> " in total"
                    Nothing ->
                      if p.offset + length p.items >= p.total then "End of results."
                      else "Deeper pages are refused past offset " <> show offsetCeiling <> "."
                )
            ]
        , pagerLink next hrefFor "Next"
        ]

  pagerLink target hrefFor label = case target of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off -> HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]
