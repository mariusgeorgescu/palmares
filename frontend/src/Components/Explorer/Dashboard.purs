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
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDashboard)
import Capabilities.Query.Gov.Types (DRepSummary(..), DashboardPage(..), EpochPoint(..), GovActionSummary(..), Lovelace)
import Components.Chart.Series as Series
import Components.Shared.DRepIdentity as DRepIdentity
import Data.Array (null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..))
import Format (formatAda, formatInt, formatPercent, humanize, pluralize)
import Route.GovQueries
  ( actionDetailHrefFor
  , actionListHrefFor
  , drepDetailHrefFor
  , defaultVoteFilters
  , drepListHrefFor
  , emptyDRepFilters
  , emptyGovActionFilters
  , methodologyPath
  , voteListHrefFor
  )
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_dashboard :: Proxy "dashboard"
_dashboard = Proxy

type State = { page :: RemoteData ApiError DashboardPage }

data Action = Initialize

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
    { initialState: const { page: NotAsked }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  handleAction = case _ of
    Initialize -> do
      H.modify_ _ { page = Loading }
      res <- getDashboard
      H.modify_ _
        { page = case res of
            Left e -> Failure e
            Right p -> Success p
        }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-6") ]
      [ intro
      , hub
      , case st.page of
          NotAsked -> skeleton "Loading governance figures…"
          Loading -> skeleton "Loading governance figures…"
          Failure e -> failure e
          Success p -> renderPage p
      ]

  intro =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.h1 [ HP.class_ (HH.ClassName "text-4xl font-bold") ] [ HH.text "Palmares" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "A verifiable track record for Cardano governance. Every figure below is derived \
              \independently from the chain, and every metric resolves to a published formula."
          ]
      ]

  hub =
    HH.div [ HP.class_ (HH.ClassName "grid gap-4 sm:grid-cols-2 lg:grid-cols-4") ]
      (map hubCard hubEntries)

  hubCard entry =
    HH.a
      [ HP.href entry.href
      , HP.class_ (HH.ClassName "card bg-base-200 hover:bg-base-300 transition-colors")
      ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-4") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "card-title text-base") ] [ HH.text entry.label ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text entry.description ]
          ]
      ]

  skeleton label =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
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
          ]
      ]

  renderPage page@(DashboardPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-6") ]
      [ statsRow page
      , treasury p
      , participation page
      , HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-2") ]
          [ breakdown "Governance actions by type" p.actionsByType
          , breakdown "Governance actions by outcome" p.actionsByState
          ]
      , closingSoon p
      , topDreps p
      ]

  statsRow page@(DashboardPage p) =
    HH.div [ HP.class_ (HH.ClassName "grid gap-4 sm:grid-cols-2 lg:grid-cols-4") ]
      [ statCard "Registered DReps" (formatInt p.totalDreps)
          ( HH.span_
              [ HH.a [ HP.href drepListHref, HP.class_ (HH.ClassName "link link-hover") ]
                  [ HH.text (formatInt (activeInactive page) <> " active or inactive") ]
              , HH.text (", " <> formatInt p.unknownDreps <> " unknown, " <> formatInt p.retiredDreps <> " retired")
              ]
          )
      , statCard "Voting power delegated" (formatAda p.drepPowerLovelace)
          (HH.text ("as of epoch " <> show p.powerEpoch))
      , statCard "Parked on always-abstain" (formatAda p.alwaysAbstainLovelace)
          (HH.text ("plus " <> formatAda p.alwaysNoConfidenceLovelace <> " on no-confidence"))
      , statCard "Actions in flight" (formatInt p.actionsInFlight)
          (HH.text ("of " <> formatInt p.totalActions <> " ever proposed"))
      ]

  statCard title value desc =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-4 gap-1") ]
          [ HH.span [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text title ]
          , HH.span [ HP.class_ (HH.ClassName "text-2xl font-semibold") ] [ HH.text value ]
          , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ desc ]
          ]
      ]

  -- Două numere, nu unul. „Cerut" e ce au scris propunerile; „adoptat" e ce a plătit trezoreria. La
  -- măsurătoare, al doilea era zero — un singur număr ar fi spus exact pe dos.
  treasury p =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
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
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ]
              [ HH.text "DRep participation by epoch" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "Share of DReps with voting power that cast at least one vote in the epoch." ]
          , Series.render (participationSeries page)
          , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
              [ HH.text ("Latest epoch in range: " <> show p.epoch <> ".") ]
          ]
      ]

  breakdown title pairs =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text title ]
          , if null pairs then HH.p [ HP.class_ (HH.ClassName "opacity-60 text-sm") ] [ HH.text "Nothing yet." ]
            else
              HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                [ HH.tbody_ (map pairRow pairs) ]
          ]
      ]

  pairRow (Tuple label count) =
    HH.tr_
      [ HH.td_ [ HH.text (humanize label) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt count) ]
      ]

  closingSoon p =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text "Closing soon" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "Open actions whose voting window ends within five epochs." ]
          , if null p.closingSoon then
              HH.p [ HP.class_ (HH.ClassName "opacity-60 text-sm") ] [ HH.text "Nothing closing soon." ]
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
          , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-60 truncate"), HP.title a.id ]
              [ HH.text a.bech32 ]
          ]
      , HH.div [ HP.class_ (HH.ClassName "text-sm text-right space-y-0.5") ]
          [ HH.div_ [ HH.text (humanize a.type_) ]
          , HH.div [ HP.class_ (HH.ClassName "opacity-60") ]
              [ HH.text
                  ( "last votable epoch " <> show a.lastVotableEpoch
                      <> " · "
                      <> pluralize a.votesCast "vote"
                      <> treasuryNote a.treasuryAmount
                  )
              ]
          ]
      ]

  treasuryNote :: Maybe Lovelace -> String
  treasuryNote = case _ of
    Nothing -> ""
    Just amount -> " · " <> formatAda amount <> " requested"

  topDreps p =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text "Largest DReps by voting power" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text ("Voting power as of epoch " <> show p.powerEpoch <> ".") ]
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
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatAda d.votingPower) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt d.delegatorCount) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatPercent d.participationRate) ]
      ]

hubEntries :: Array { href :: String, label :: String, description :: String }
hubEntries =
  [ { href: drepListHref
    , label: "DReps"
    , description: "Who is registered, how much power they hold, and whether they vote."
    }
  , { href: actionListHrefFor emptyGovActionFilters
    , label: "Governance actions"
    , description: "Every proposal, its lifecycle, and who voted which way."
    }
  , { href: voteListHrefFor defaultVoteFilters
    , label: "Votes"
    , description: "Individual votes, with the rationale when one was published."
    }
  , { href: methodologyPath
    , label: "Methodology"
    , description: "The formula behind every metric on this site."
    }
  ]
