-- | Pagina unui DRep: un singur apel la `/pages/drep/{id}`.
-- |
-- | E ecranul cel mai predispus la N+1 din tot produsul — identitate, metrici, putere pe epoci,
-- | delegatori, istoria înregistrării și documentul de metadate — și de asta compozitul există.
-- | Sfatul de a chema patru rute separate e mort.
-- |
-- | Ce nu e aici, intenționat: istoricul de voturi. `/votes` filtrat după acest DRep e propriul
-- | ecran, cu propria paginare; lipit aici, ar fi exact adâncimea pe care serverul o servește în
-- | douăsprezece secunde.
module Components.Explorer.DRepDetail
  ( Slot
  , Output
  , _drepDetail
  , component
  , rationaleBreakdown
  , latencyLabel
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDRepDetail)
import Capabilities.Query.Gov.Types
  ( AnchorContent(..)
  , ChainPoint(..)
  , DRepDetail(..)
  , DRepMetrics(..)
  , DRepSummary(..)
  , DRepUpdate(..)
  , Delegator(..)
  , DelegatorStats(..)
  , FinalVotes(..)
  , PowerPoint(..)
  , VoteTypeStats(..)
  )
import Components.Chart.Series as Series
import Components.Shared.Anchor as Anchor
import Components.Shared.DRepIdentity as DRepIdentity
import Components.Shared.MetricInfo as MetricInfo
import Data.Array (concatMap, last, null, uncons)
import Data.Foldable (maximum, minimum)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Data.String as String
import Data.Tuple (Tuple(..))
import Format (formatAda, formatDay, formatHours, formatInt, formatPercent, humanize, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Route.GovQueries (drepListHrefFor, emptyDRepFilters, methodologyHrefFor, votesForDRepHref)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_drepDetail :: Proxy "drepDetail"
_drepDetail = Proxy

type Input = String

type State =
  { drepId :: String
  , page :: RemoteData ApiError DRepDetail
  }

data Action
  = Initialize
  | Retry
  | Receive Input

-- | Desfășurarea raționamentelor, ca etichete și numere.
-- |
-- | Cele cinci stări nu se topesc într-un procent: „n-a publicat nimic", „n-am verificat încă", „am
-- | încercat și n-am putut" și „e verificat" sunt fapte diferite despre lume, iar un singur număr
-- | le-ar transforma pe toate în vina autorului.
rationaleBreakdown :: DRepMetrics -> Array (Tuple String Int)
rationaleBreakdown (DRepMetrics m) =
  [ Tuple "Verified" m.rationaleVerified
  , Tuple "Inline in the transaction" m.rationaleInline
  , Tuple "Could not be verified" m.rationaleUnverified
  , Tuple "Not checked yet" m.rationalePending
  , Tuple "None published" m.rationaleAbsent
  , Tuple "Valid CIP-100 document" m.rationaleCip100Valid
  ]

-- | Latența, cu dimensiunea eșantionului lipită de ea: o mediană din două voturi nu e o mediană.
latencyLabel :: Maybe Number -> Int -> String
latencyLabel hours sample = case hours of
  Nothing -> "n/a"
  Just h -> formatHours h <> " (" <> pluralize sample "vote" <> ")"

component
  :: forall q m
   . MonadQueryGov m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \drepId -> { drepId, page: NotAsked }
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
    Receive drepId -> do
      st <- H.get
      when (drepId /= st.drepId) do
        H.modify_ _ { drepId = drepId }
        load

  load = do
    st <- H.get
    H.modify_ _ { page = Loading }
    res <- getDRepDetail st.drepId
    H.modify_ _
      { page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ HH.a [ HP.href (drepListHrefFor emptyDRepFilters), HP.class_ (HH.ClassName "link link-hover text-sm") ]
          [ HH.text "← All DReps" ]
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure st.drepId e
          Success p -> renderDetail p
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading this DRep…" ]
          ]
      ]

  failure drepId e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "This DRep could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ] [ HH.text drepId ]
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

  renderDetail (DRepDetail d) =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ identityCard d.drep
      , votesLink d.drep
      , HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-3") ]
          [ metricsCard d.metrics
          , delegatorsCard d.delegatorStats
          , finalVotesCard d.metrics
          ]
      , powerCard d.powerByEpoch
      , votesByTypeCard d.metrics
      , topDelegatorsCard d.topDelegators
      , updatesCard d.updates
      , anchorCard d.drep d.anchorContent d.updates
      , formulasNote d.metrics
      ]

  -- Istoricul de voturi nu e lipit aici: e propriul ecran, cu propria paginare și propriile
  -- filtre. Linkul duce la el filtrat pe acest DRep.
  votesLink (DRepSummary s) =
    HH.a
      [ HP.href (votesForDRepHref s.id), HP.class_ (HH.ClassName "btn btn-sm") ]
      [ HH.text "See every vote this DRep cast →" ]

  identityCard (DRepSummary s) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
          -- `h1`, nu `div`: numele DRep-ului E titlul paginii. Fără el, lista de titluri începea cu
          -- „Voting record", deci cine navighează cu un cititor de ecran nu afla pe CINE se uită.
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ]
              [ DRepIdentity.render { givenName: s.givenName, drepId: s.id, hasScript: s.hasScript } ]
          , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-2 items-center text-sm") ]
              -- Aceeași culoare ca în listă: cine a filtrat după „Inactive" nu trebuie să piardă
              -- reperul exact când ajunge pe pagina pe care a dat clic.
              [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> statusBadgeClass s.status)) ]
                  [ HH.text (humanize s.status) ]
              , HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
                  [ HH.text
                      ( maybe "no expiry on record"
                          ( \e ->
                              if s.status == "active" then "active until epoch " <> show e
                              else "was active until epoch " <> show e
                          )
                          s.activeUntilEpoch
                      )
                  ]
              , HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
                  [ HH.text ("registered " <> s.registeredAt <> " (" <> formatInt s.ageDays <> " days ago)") ]
              , HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
                  [ HH.text (maybe "no declared language" (\l -> "language: " <> l) s.language) ]
              ]
          , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-6 pt-2") ]
              [ figure "Voting power" (formatAda s.votingPower) ("as of epoch " <> show s.votingPowerEpoch)
              , figure "Delegators" (formatInt s.delegatorCount) ""
              , figure "Participation" (formatPercent s.participationRate)
                  (pluralize s.votesCast "vote" <> " of " <> formatInt s.eligibleActions <> " eligible")
              , figure "Open and unvoted" (formatInt s.openActionsUnvoted) "actions still open"
              ]
          -- `hex` nu e decor: e forma în care apare credențialul în tranzacții și în `required_signers`.
          -- ID-ul întreg se selectează și se copiază. Scurtarea de sub nume e bună pentru citit,
          -- dar dintr-un `title` nu se copiază nimic, iar cine vrea să verifice în alt explorer are
          -- nevoie de forma completă.
          , HH.p [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 break-all") ]
              [ HH.text s.id ]
          , HH.p [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 break-all") ]
              [ HH.text ("credential: " <> s.hex) ]
          ]
      ]

  figure title value hint =
    HH.div_
      [ HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-70") ] [ HH.text title ]
      , HH.div [ HP.class_ (HH.ClassName "text-xl font-semibold") ] [ HH.text value ]
      , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text hint ]
      ]

  metricsCard metrics@(DRepMetrics m) =
    card "Voting record"
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1 text-sm") ]
          -- ID-urile de formulă sunt scrise aici, nu derivate: serverul publică `field` pentru
          -- fiecare formulă, dar asta ar fi un al doilea apel pe ecranul ăsta doar ca să afle ce
          -- scrie deja în `formula_ids` din același răspuns. O nepotrivire se vede în lista de
          -- formule de la baza paginii.
          [ lineWithFormula "Participation" (formatPercent m.participationRate) "participation_rate_v1"
          , lineWithFormula "Rationale rate" (formatPercent m.rationaleRate) "rationale_rate_v1"
          , lineWithFormula "Median time to vote"
              (latencyLabel m.voteLatencyMedianHours m.voteLatencySample)
              "vote_latency_median_hours_v1"
          , line "Their slowest votes" (latencyLabel m.voteLatencyP90Hours m.voteLatencySample)
          , line "Metrics as of epoch" (show m.asOfEpoch)
          ]
      , HH.div [ HP.class_ (HH.ClassName "divider my-1") ] []
      , HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-70") ]
          [ HH.text "Rationales" ]
      , HH.div [ HP.class_ (HH.ClassName "space-y-1 text-sm") ]
          (map (\(Tuple label value) -> line label (formatInt value)) (rationaleBreakdown metrics))
      ]

  delegatorsCard (DelegatorStats s) =
    card "Delegators"
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1 text-sm") ]
          [ line "Now" (formatInt s.delegatorCount)
          , line (pluralize s.windowEpochs "epoch" <> " ago") (formatInt s.delegatorCountPrev)
          , line "Stayed" (formatInt s.delegatorsRetained)
          , line "Joined" (formatInt s.delegatorsJoined)
          , line "Left" (formatInt s.delegatorsLeft)
          , lineWithFormula "Retention" (formatPercent s.delegatorRetentionRate)
              "delegator_retention_rate_v1"
          ]
      ]

  finalVotesCard (DRepMetrics m) =
    let
      FinalVotes v = m.finalVotes
    in
      card "How they voted"
        [ HH.div [ HP.class_ (HH.ClassName "space-y-1 text-sm") ]
            [ line "Yes" (formatInt v.yes)
            , line "No" (formatInt v.no)
            , line "Abstain" (formatInt v.abstain)
            ]
        , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70 pt-2") ]
            [ HH.text
                "Counted from the last vote cast on each action, because a DRep may change its \
                \vote while the action is open."
            ]
        ]

  -- Barele sunt relative la vârf. Puterea unui DRep variază de obicei cu procente, nu cu ordine de
  -- mărime, deci graficul iese aproape plat — ceea ce E adevărul, dar arată ca un bloc desenat
  -- greșit. Intervalul scris dedesubt e diferența dintre cele două citiri.
  powerCard points =
    card "Voting power by epoch"
      [ Series.render (map powerPoint points)
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text
              ( case
                  minimum (map (\(PowerPoint p) -> p.lovelace) points),
                  maximum (map (\(PowerPoint p) -> p.lovelace) points)
                  of
                  Just lo, Just hi | lo /= hi ->
                    "Between " <> formatAda lo <> " and " <> formatAda hi <> " across these epochs."
                  Just lo, Just _ -> "Flat at " <> formatAda lo <> " across these epochs."
                  _, _ -> "No power recorded yet."
              )
          ]
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text
              ( case last points of
                  Nothing -> ""
                  Just (PowerPoint p) ->
                    "Latest: " <> formatAda p.lovelace <> " from "
                      <> pluralize p.delegatorCount "delegator"
                      <> " in epoch "
                      <> show p.epoch
                      <> "."
              )
          ]
      ]

  powerPoint (PowerPoint p) =
    { label: "epoch " <> show p.epoch
    , value: p.lovelace
    , hint: formatAda p.lovelace <> " from " <> pluralize p.delegatorCount "delegator"
    }

  votesByTypeCard (DRepMetrics m) =
    card "By kind of action"
      [ HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ MetricInfo.renderLabelled "How this is counted" "votes_by_type_v1" ]
      , HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
          [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
              [ HH.thead_
                  [ HH.tr_
                      [ HH.th_ [ HH.text "Kind" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Eligible" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Voted" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Yes" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "No" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Abstain" ]
                      , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Participation" ]
                      ]
                  ]
              , HH.tbody_ (map voteTypeRow m.votesByType)
              ]
          ]
      , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text
              "Each row is measured against the actions of that kind alone, so the rates here \
              \answer \"do they show up for this\", not \"what share of everything is this\"."
          ]
      ]

  voteTypeRow (Tuple kind (VoteTypeStats v)) =
    HH.tr_
      [ HH.td_ [ HH.text (humanize kind) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt v.eligibleActions) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt v.votesCast) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt v.yes) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt v.no) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt v.abstain) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatPercent v.participationRate) ]
      ]

  topDelegatorsCard delegators =
    card "Largest delegators"
      [ if null delegators then
          HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text "Nobody has delegated here yet." ]
        else
          HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
            [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                [ HH.thead_
                    [ HH.tr_
                        [ HH.th_ [ HH.text "Stake address" ]
                        , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Amount" ]
                        , HH.th_ [ HH.text "Delegated" ]
                        , HH.th_ [ HH.text "Still delegated" ]
                        ]
                    ]
                , HH.tbody_ (map delegatorRow delegators)
                ]
            ]
      ]

  delegatorRow (Delegator d) =
    let
      ChainPoint at = d.delegatedAt
    in
      HH.tr_
        [ HH.td [ HP.class_ (HH.ClassName "font-mono text-xs break-all"), HP.title d.stakeAddress ]
            [ HH.text (shorten d.stakeAddress) ]
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
            -- Suma vine din `epoch_stake`; când epoca n-are rândul, e „unknown", nu zero.
            [ HH.text (maybe "unknown" formatAda d.lovelace) ]
        , HH.td [ HP.class_ (HH.ClassName "text-xs") ]
            [ HH.text ("epoch " <> show at.epoch <> " · " <> formatDay at.time) ]
        , HH.td_
            [ HH.span
                [ HP.class_
                    ( HH.ClassName
                        ( "badge badge-sm " <>
                            if d.isCurrent then "badge-success"
                            else -- `badge-ghost` are fundalul `base-200`, adică exact culoarea cardului în care stă: starea
                              -- neutră era singura invizibilă. `badge-outline` are contur și text, deci se vede.
                              "badge-outline"
                        )
                    )
                ]
                [ HH.text (if d.isCurrent then "yes" else "no") ]
            ]
        ]

  updatesCard updates =
    card "Registration history"
      [ if null updates then
          HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text "No events recorded." ]
        else HH.ul [ HP.class_ (HH.ClassName "divide-y divide-base-300") ] (map updateRow updates)
      ]

  updateRow (DRepUpdate u) =
    let
      ChainPoint at = u.at
    in
      HH.li [ HP.class_ (HH.ClassName "py-2 space-y-1") ]
        [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
            [ HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ] [ HH.text (humanize u.kind) ]
            , HH.span [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                [ HH.text ("epoch " <> show at.epoch <> " · " <> formatDay at.time) ]
            , case u.deposit of
                Nothing -> HH.text ""
                Just dep ->
                  HH.span [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                    [ HH.text ("deposit " <> formatAda dep) ]
            ]
        , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 break-all") ]
            [ HH.text ("tx " <> at.txHash) ]
        , case u.anchorUrl of
            Nothing -> HH.text ""
            Just url ->
              HH.div [ HP.class_ (HH.ClassName "text-xs") ]
                [ HH.text ("metadata declared here: ")
                , HH.span [ HP.class_ (HH.ClassName "font-mono break-all opacity-70") ] [ HH.text url ]
                ]
        ]

  -- Documentul de metadate. Când serverul nu l-a putut valida, `anchor_content` vine `null` — nu
  -- avem octeții, deci nu putem randa documentul neconform. Ce putem: să nu-l ascundem, și să
  -- spunem în cuvinte ce înseamnă starea.
  anchorCard (DRepSummary s) content updates =
    card "Metadata document"
      [ case content of
          Just c@(AnchorContent _) -> Anchor.render c
          Nothing ->
            Anchor.renderUnavailable
              { anchorStatus: s.anchorStatus
              , anchorUrl: lastAnchorUrl updates
              }
      ]

  lastAnchorUrl updates = case last updates of
    Nothing -> Nothing
    Just (DRepUpdate u) -> u.anchorUrl

  formulasNote (DRepMetrics m) =
    if null m.formulaIds then HH.text ""
    else
      -- Singurul loc de pe site unde un id de formulă apărea fără să ducă la ea.
      HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
        ( [ HH.text "Formulas behind these figures: " ]
            <> intercalateHtml (HH.text ", ") (map formulaLink m.formulaIds)
            <> [ HH.text "." ]
        )

  formulaLink fid =
    HH.a [ HP.href (methodologyHrefFor fid), HP.class_ (HH.ClassName "link link-hover") ]
      [ HH.text fid ]

  card title children =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
          ([ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text title ] ] <> children)
      ]

  line label value =
    HH.div [ HP.class_ (HH.ClassName "flex items-baseline justify-between gap-4") ]
      [ HH.span [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text label ]
      , HH.span [ HP.class_ (HH.ClassName "font-mono") ] [ HH.text value ]
      ]

  lineWithFormula label value formulaId =
    HH.div [ HP.class_ (HH.ClassName "flex items-baseline justify-between gap-4") ]
      [ HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
          [ MetricInfo.renderLabelled label formulaId ]
      , HH.span [ HP.class_ (HH.ClassName "font-mono") ] [ HH.text value ]
      ]

  shorten s =
    if String.length s <= 28 then s
    else String.take 14 s <> "…" <> String.drop (String.length s - 8) s

-- | `HH.HTML` nu e un `Monoid`, deci `intercalate` din `Data.Foldable` nu se aplică pe el.
intercalateHtml :: forall w i. HH.HTML w i -> Array (HH.HTML w i) -> Array (HH.HTML w i)
intercalateHtml sep items = case uncons items of
  Nothing -> []
  Just { head: first, tail: rest } -> [ first ] <> concatMap (\x -> [ sep, x ]) rest

-- | Culoarea stării unui DRep. Aceeași în listă și în detaliu — altfel filtrul vizual se rupe fix
-- | la clic.
statusBadgeClass :: String -> String
statusBadgeClass = case _ of
  "active" -> "badge-success"
  "inactive" -> "badge-warning"
  "retired" -> "badge-outline"
  _ -> "badge-outline"
