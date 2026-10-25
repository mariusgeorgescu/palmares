-- | Pagina unei acțiuni de guvernanță: un apel la `/pages/gov-action/{id}`.
-- |
-- | Ecranul are o singură obligație grea: să nu transforme o necunoaștere în verdict. Pragul de
-- | ratificare se calculează pe putere de vot, iar pe o acțiune reală măsurată `ratio` era `null`
-- | deși se exprimaseră 43 de voturi — puterea de ambele părți era zero. „0% din 67%" ar fi spus că
-- | propunerea a fost respinsă de comunitate; adevărul e că raportul nu există.
module Components.Explorer.ActionDetail
  ( Slot
  , Output
  , _actionDetail
  , component
  , tallyVerdict
  , lifecyclePath
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getGovActionDetail)
import Capabilities.Query.Gov.Types
  ( ActionAnchor(..)
  , ChainPoint(..)
  , GovActionDetail(..)
  , GovActionSummary(..)
  , Lifecycle(..)
  , ParamChange(..)
  , Proposer(..)
  , Tally(..)
  , Withdrawal(..)
  )
import Components.Explorer.ActionList (stateClass)
import Components.Shared.Anchor as Anchor
import Data.Array (catMaybes, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String as String
import Format (formatAda, formatInt, formatPercent, humanize, pluralize, roleLabel)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Route.GovQueries (actionListHrefFor, emptyGovActionFilters)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_actionDetail :: Proxy "actionDetail"
_actionDetail = Proxy

type Input = String

type State =
  { actionId :: String
  , page :: RemoteData ApiError GovActionDetail
  }

data Action
  = Initialize
  | Receive Input

-- | Verdictul unei numărători, în cuvinte.
-- |
-- | Când `ratio` lipsește, nu se compară nimic: nu „sub prag", ci „nu se poate calcula". Când
-- | există, se spune și raportul și pragul, ca cititorul să vadă comparația, nu doar concluzia.
tallyVerdict :: Tally -> String
tallyVerdict (Tally t) = case t.ratio, t.threshold of
  Nothing, _ -> "ratio not computable"
  Just r, Nothing -> formatPercent (Just r) <> " in favour, no threshold recorded"
  Just r, Just th ->
    formatPercent (Just r)
      <> " in favour against a "
      <> formatPercent (Just th)
      <> " threshold — "
      <> (if r >= th then "met" else "not met")

-- | Drumul prin ciclul de viață, ca listă de pași cu epoca lor. O acțiune măsurată avea și
-- | `expired_epoch` 304 și `dropped_epoch` 305: starea e un cuvânt, drumul are mai mulți pași.
lifecyclePath :: Lifecycle -> Array String
lifecyclePath (Lifecycle lc) =
  catMaybes
    [ map (\e -> "ratified in epoch " <> show e) lc.ratifiedEpoch
    , map (\e -> "enacted in epoch " <> show e) lc.enactedEpoch
    , map (\e -> "expired in epoch " <> show e) lc.expiredEpoch
    , map (\e -> "dropped in epoch " <> show e) lc.droppedEpoch
    ]

component
  :: forall q m
   . MonadQueryGov m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \actionId -> { actionId, page: NotAsked }
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
    Receive actionId -> do
      st <- H.get
      when (actionId /= st.actionId) do
        H.modify_ _ { actionId = actionId }
        load

  load = do
    st <- H.get
    H.modify_ _ { page = Loading }
    res <- getGovActionDetail st.actionId
    H.modify_ _
      { page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ HH.a
          [ HP.href (actionListHrefFor emptyGovActionFilters)
          , HP.class_ (HH.ClassName "link link-hover text-sm")
          ]
          [ HH.text "← All governance actions" ]
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure st.actionId e
          Success p -> renderDetail p
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading this proposal…" ]
          ]
      ]

  failure actionId e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "This proposal could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ] [ HH.text actionId ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          ]
      ]

  renderDetail (GovActionDetail d) =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ headerCard d.action d.proposer
      , talliesCard d.tallies
      , if null d.withdrawals then HH.text "" else withdrawalsCard d.withdrawals
      , if null d.paramChanges then HH.text "" else paramsCard d.paramChanges
      , documentCard d.action d.anchorContent
      ]

  headerCard (GovActionSummary a) proposer =
    let
      ChainPoint at = a.proposedAt
      Lifecycle lc = a.lifecycle
    in
      HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
        [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
            [ HH.h1 [ HP.class_ (HH.ClassName "text-2xl font-bold") ]
                [ HH.text (fromMaybe "Untitled proposal" a.title) ]
            , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-center gap-2 text-sm") ]
                [ HH.span [ HP.class_ (HH.ClassName "badge badge-outline") ] [ HH.text (humanize a.type_) ]
                , HH.span [ HP.class_ (HH.ClassName ("badge " <> stateClass lc.state)) ]
                    [ HH.text (humanize lc.state) ]
                , HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
                    [ HH.text ("proposed in epoch " <> show at.epoch <> " · " <> at.time) ]
                ]
            , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-60 break-all") ]
                [ HH.text a.bech32 ]
            , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-50 break-all") ]
                [ HH.text ("tx " <> at.txHash) ]
            , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-6 pt-2") ]
                [ figure "Votes cast" (formatInt a.votesCast) ""
                , figure "Expires" ("epoch " <> show a.expiresEpoch)
                    ("votable to epoch " <> show a.lastVotableEpoch)
                , figure "Deposit" (maybe "not recorded" formatAda a.deposit) "refunded to the return address"
                , figure "Asked for" (maybe "nothing" formatAda a.treasuryAmount) ""
                ]
            , if null (lifecyclePath a.lifecycle) then HH.text ""
              else
                HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                  [ HH.text (String.joinWith ", then " (lifecyclePath a.lifecycle) <> ".") ]
            , case lc.formulaId of
                Nothing -> HH.text ""
                Just fid ->
                  HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                    [ HH.text ("Outcome decided by formula " <> fid <> ".") ]
            , case proposer of
                Nothing -> HH.text ""
                Just (Proposer p) ->
                  HH.p [ HP.class_ (HH.ClassName "text-sm") ]
                    [ HH.text "Proposed by "
                    , HH.span [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ]
                        [ HH.text p.stakeAddress ]
                    , HH.text (", who has submitted " <> pluralize p.actionsCount "proposal" <> " in total.")
                    ]
            , case a.returnAddress of
                Nothing -> HH.text ""
                Just addr ->
                  HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60 break-all") ]
                    [ HH.text ("deposit returns to " <> addr) ]
            ]
        ]

  figure title value hint =
    HH.div_
      [ HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-60") ] [ HH.text title ]
      , HH.div [ HP.class_ (HH.ClassName "text-xl font-semibold") ] [ HH.text value ]
      , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ HH.text hint ]
      ]

  talliesCard tallies =
    card "Votes"
      [ if null tallies then
          HH.p [ HP.class_ (HH.ClassName "text-sm opacity-60") ]
            [ HH.text "No tally has been computed for this action." ]
        else HH.div [ HP.class_ (HH.ClassName "space-y-4") ] (map tallyBlock tallies)
      ]

  tallyBlock tally@(Tally t) =
    HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
      [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
          [ HH.span [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text (roleLabel t.role) ]
          , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
              [ HH.text ("as of epoch " <> show t.epoch) ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
          [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
              [ HH.thead_
                  [ HH.tr_
                      [ HH.th_ [ HH.text "" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Voters" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Power" ]
                      ]
                  ]
              , HH.tbody_
                  [ tallyRow "Yes" t.yesCount t.yesPower
                  , tallyRow "No" t.noCount t.noPower
                  , tallyRow "Abstain" t.abstainCount t.abstainPower
                  ]
              ]
          ]
      , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (tallyVerdict tally) ]
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
          [ HH.text
              ( "Threshold parameter: " <> fromMaybe "not recorded" t.thresholdParam
                  <> ". Counted on: "
                  <> maybe "not recorded" humanize t.basis
                  <> "."
                  <> maybe "" (\f -> " Formula: " <> f <> ".") t.formulaId
              )
          ]
      ]

  tallyRow label count power =
    HH.tr_
      [ HH.td_ [ HH.text label ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt count) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ] [ HH.text (formatAda power) ]
      ]

  withdrawalsCard withdrawals =
    card "Treasury withdrawals"
      [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
          [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
              [ HH.thead_
                  [ HH.tr_
                      [ HH.th_ [ HH.text "Beneficiary" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Amount" ]
                      , HH.th_ [ HH.text "Paid" ]
                      ]
                  ]
              , HH.tbody_ (map withdrawalRow withdrawals)
              ]
          ]
      ]

  withdrawalRow (Withdrawal w) =
    HH.tr_
      [ HH.td [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ] [ HH.text w.beneficiary ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ] [ HH.text (formatAda w.amount) ]
      , HH.td [ HP.class_ (HH.ClassName "text-sm") ]
          [ case w.enactedAt of
              Nothing -> HH.text "not paid"
              Just (ChainPoint at) -> HH.text ("epoch " <> show at.epoch <> " · " <> at.time)
          -- `paid_heuristic` e cinstea serverului: plata nu se poate citi direct pentru fiecare caz.
          -- Ecranul spune același lucru în loc să prezinte o deducție ca pe o observație.
          , if w.paidHeuristic then
              HH.div [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                [ HH.text "inferred, not read from a payment on chain" ]
            else HH.text ""
          ]
      ]

  paramsCard changes =
    card "Protocol parameters touched"
      [ HH.ul [ HP.class_ (HH.ClassName "list-disc list-inside space-y-1 text-sm") ]
          (map paramRow changes)
      ]

  paramRow (ParamChange c) =
    HH.li_
      [ HH.span [ HP.class_ (HH.ClassName "font-mono") ] [ HH.text c.param ]
      , case c.group of
          Nothing -> HH.text ""
          Just g -> HH.span [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text (" · threshold group " <> g) ]
      ]

  documentCard (GovActionSummary a) content =
    card "Proposal document"
      [ case content of
          Just c@(ActionAnchor _) -> Anchor.renderAction c
          Nothing -> Anchor.renderUnavailable { anchorStatus: a.anchorStatus, anchorUrl: Nothing }
      ]

  card title children =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
          ([ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text title ] ] <> children)
      ]
