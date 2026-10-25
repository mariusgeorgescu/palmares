-- | Comitetul constituțional: `GET /committee`.
-- |
-- | Ecranul răspunde întîi la întrebarea pentru care îl deschide cineva — __cîte voturi trebuie ca
-- | un vot al comitetului să conteze__ — și abia apoi listează membrii. Cvorumul e o proprietate a
-- | corpului, nu a vreunui membru, iar o listă fără el nu spune nimic despre putere.
-- |
-- | Nu are paginare și nu are filtre: comitetul are trei membri pe preprod și șapte pe mainnet.
-- | Un plic de paginare peste atîta ar fi mobilier.
module Components.Explorer.Committee
  ( Slot
  , Output
  , _committee
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getCommittee)
import Capabilities.Query.Gov.Types (ChainPoint(..), CommitteeMember(..), CommitteeState(..))
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Format (formatDay, formatInt, humanize, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Route (Route)
import Route.GovQueries (actionDetailHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_committee :: Proxy "committee"
_committee = Proxy

type Input = Unit

type State = { committee :: RemoteData ApiError CommitteeState }

data Action
  = Initialize
  | Retry

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: const { committee: NotAsked }
    , render
    , eval: H.mkEval H.defaultEval { handleAction = handleAction, initialize = Just Initialize }
    }
  where
  handleAction = case _ of
    -- `H.fork`, nu `load` direct: initializatorul unui copil ține deschisă inițializarea
    -- PĂRINTELUI, iar părintele e cel care pune titlul documentului. Măsurat pe deploy:
    -- `/activity` răspunde în 12 secunde pe baza vie, iar tab-ul scria titlul generic tot timpul
    -- ăla. Un ecran lent nu are voie să țină în loc cadrul aplicației.
    Initialize -> void (H.fork load)
    Retry -> load

  load = do
    H.modify_ _ { committee = Loading }
    res <- getCommittee
    H.modify_ _
      { committee = case res of
          Left e -> Failure e
          Right c -> Success c
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Constitutional committee" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "The committee judges whether an action is constitutional. It votes on every kind \
                  \of action except its own replacement and a no-confidence motion."
              ]
          ]
      , case st.committee of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success c -> body c
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading the committee…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The committee could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body (CommitteeState c) =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
          [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
              [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-x-6 gap-y-2") ]
                  [ figure "Quorum" (show c.quorumNumerator <> " of " <> show c.quorumDenominator)
                  , figure "Members seated" (formatInt (length c.members))
                  , figure "As of" ("epoch " <> show c.epoch)
                  ]
              -- Fracția se scrie și în cuvinte: „2/3" e un raport, iar întrebarea omului e cîte
              -- voturi sînt, nu ce procent.
              , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                  [ HH.text
                      ( "A committee vote counts when at least "
                          <> pluralize c.quorumNumerator "member"
                          <> " out of "
                          <> show c.quorumDenominator
                          <> " vote the same way."
                      )
                  ]
              , case c.establishedBy of
                  -- Comitetul din genesis n-a fost instalat de nicio acțiune, și asta e un fapt
                  -- despre rețea, nu un cîmp lipsă.
                  Nothing ->
                    HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                      [ HH.text "This committee came from the genesis configuration, not from a governance action." ]
                  Just actionId ->
                    HH.p [ HP.class_ (HH.ClassName "text-sm") ]
                      [ HH.text "Established by "
                      , HH.a
                          [ HP.href (actionDetailHrefFor actionId)
                          , HP.class_ (HH.ClassName "link link-hover font-mono text-xs break-all")
                          ]
                          [ HH.text actionId ]
                      ]
              ]
          ]
      , if null c.members then noMembers else membersTable c.members
      ]

  noMembers =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "No members are seated." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "A committee with no members cannot ratify anything, which is itself a governance state." ]
          ]
      ]

  membersTable members =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ HH.th_ [ HH.text "Member" ]
                          , HH.th_ [ HH.text "Status" ]
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Term ends" ]
                          , HH.th [ HP.class_ (HH.ClassName "text-right") ] [ HH.text "Votes cast" ]
                          , HH.th_ [ HH.text "Hot key" ]
                          ]
                      ]
                  , HH.tbody_ (map memberRow members)
                  ]
              ]
          ]
      ]

  memberRow (CommitteeMember m) =
    HH.tr_
      [ HH.td [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ]
          [ HH.div_ [ HH.text m.coldBech32 ]
          , HH.div [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text (authorizedNote m) ]
          ]
      , HH.td_
          [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> statusClass m.status)) ]
              [ HH.text (humanize m.status) ]
          ]
      , HH.td [ HP.class_ (HH.ClassName "text-right whitespace-nowrap") ]
          [ HH.text ("epoch " <> show m.expirationEpoch) ]
      , HH.td [ HP.class_ (HH.ClassName "text-right font-mono") ] [ HH.text (formatInt m.votesCast) ]
      -- Fără cheie fierbinte, membrul e numit dar NU poate vota. Asta e distincția pe care o
      -- coloană goală ar pierde-o.
      , HH.td [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ]
          [ HH.text (maybe "not authorized yet" identity m.hotHash) ]
      ]

  authorizedNote m = case m.resignedAt of
    Just (ChainPoint p) -> "resigned in epoch " <> show p.epoch <> " · " <> formatDay p.time
    Nothing -> maybe "" (\(ChainPoint p) -> "authorized in epoch " <> show p.epoch <> " · " <> formatDay p.time) m.authorizedAt

  statusClass = case _ of
    "active" -> "badge-success"
    "resigned" -> "badge-error"
    "expired" -> "badge-outline"
    _ -> "badge-outline"

  figure label value =
    HH.div_
      [ HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-70") ] [ HH.text label ]
      , HH.div [ HP.class_ (HH.ClassName "text-2xl font-bold") ] [ HH.text value ]
      ]
