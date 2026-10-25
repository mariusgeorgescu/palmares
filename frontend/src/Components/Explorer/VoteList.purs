-- | Explorerul de voturi: `GET /votes`, cu filtre și paginare în URL.
-- |
-- | Două lucruri îl fac diferit de celelalte liste, și amândouă sunt măsurate:
-- |
-- |   * __nu interoghează niciodată nefiltrat.__ `/votes` fără filtre raportează `total:
-- |     3.244.726` pe o rețea cu ~900 de voturi reale; orice filtru îl repară. Default-ul e
-- |     `is_final=true`, care e și înțelesul corect: votul care a contat e ultimul;
-- |   * __pagerul se oprește la offset 600__, nu la plafonul serverului de 10.000. Măsurat: 1,1 s
-- |     la offset 600, 12,15 s la 800 — o funcție în trepte, nu o degradare lină. ADR 0009 decide
-- |     că nu se repară, deci ecranul oferă filtrare în loc de adâncime, și spune de ce.
module Components.Explorer.VoteList
  ( Slot
  , Output
  , _voteList
  , component
  , verdicts
  , voterRoles
  , verdictClass
  , effectiveFilters
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getVotes)
import Capabilities.Query.Gov.Types (ChainPoint(..), VoteAnchor(..), VotePage(..), VoteRow(..))
import Components.Explorer.ActionList (actionTypes)
import Components.Shared.Anchor as Anchor
import Components.Shared.DRepIdentity as DRepIdentity
import Data.Array (elem, length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe)
import Data.Number.Format (fixed, toStringWith)
import Format (formatInt, humanize, pluralize, roleLabel)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter, navigate)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, prevOffset, votesOffsetCeiling)
import Route (Route(..))
import Route.GovQueries
  ( VoteFilters
  , actionDetailHrefFor
  , defaultVoteFilters
  , drepDetailHrefFor
  , toggleIn
  , voteListHrefFor
  )
import Type.Proxy (Proxy(..))
import Web.UIEvent.KeyboardEvent as KE

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_voteList :: Proxy "voteList"
_voteList = Proxy

type Input = VoteFilters

type State =
  { filters :: VoteFilters
  , page :: RemoteData ApiError VotePage
  , searchDraft :: String
  }

data Action
  = Initialize
  | Receive Input
  | SearchDraft String
  | SearchKey KE.KeyboardEvent
  | SubmitSearch

verdicts :: Array String
verdicts = [ "yes", "no", "abstain" ]

voterRoles :: Array String
voterRoles = [ "drep", "spo", "constitutional_committee" ]

verdictClass :: String -> String
verdictClass = case _ of
  "yes" -> "badge-success"
  "no" -> "badge-error"
  "abstain" -> "badge-ghost"
  _ -> "badge-outline"

-- | Filtrele cu care se interoghează chiar: dacă URL-ul n-a cerut niciunul, se pune default-ul.
-- | Un `/votes` nefiltrat n-ar întoarce un număr adevărat, deci nu se cere niciodată.
effectiveFilters :: VoteFilters -> VoteFilters
effectiveFilters f =
  if anyFilter f then f
  else f { is_final = defaultVoteFilters.is_final }

anyFilter :: VoteFilters -> Boolean
anyFilter f =
  not (null f.voter_role) || not (null f.verdict) || not (null f.gov_action_type)
    || isJust f.voter_id
    || isJust f.gov_action_id
    || isJust f.q
    || isJust f.is_final

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters ->
        { filters: effectiveFilters filters
        , page: NotAsked
        , searchDraft: fromMaybe "" filters.q
        }
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
    Receive incoming -> do
      st <- H.get
      let filters = effectiveFilters incoming
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters, searchDraft = fromMaybe "" filters.q }
        load
    SearchDraft s -> H.modify_ _ { searchDraft = s }
    SearchKey ev -> when (KE.key ev == "Enter") (handleAction SubmitSearch)
    SubmitSearch -> do
      st <- H.get
      let q = if st.searchDraft == "" then Nothing else Just st.searchDraft
      navigate (VoteList (st.filters { q = q, offset = Nothing }))

  load = do
    st <- H.get
    H.modify_ _ { page = Loading }
    res <- getVotes st.filters
    H.modify_ _
      { page = case res of
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
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Votes" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "Every vote cast, who cast it, how long after the proposal opened, and whether they \
              \published a reason."
          ]
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-2 items-center") ]
          [ HH.input
              [ HP.type_ HP.InputSearch
              , HP.class_ (HH.ClassName "input input-bordered input-sm w-72")
              , HP.placeholder "Search voter or proposal"
              , HP.value st.searchDraft
              , HE.onValueInput SearchDraft
              , HE.onKeyDown SearchKey
              ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm btn-primary"), HE.onClick (const SubmitSearch) ]
              [ HH.text "Search" ]
          , HH.a
              [ HP.href (voteListHrefFor defaultVoteFilters)
              , HP.class_ (HH.ClassName "btn btn-sm btn-ghost")
              ]
              [ HH.text "Reset filters" ]
          ]
      , case st.filters.voter_id, st.filters.gov_action_id of
          Just v, _ ->
            HH.p [ HP.class_ (HH.ClassName "text-sm") ]
              [ HH.text "Filtered to the votes of "
              , HH.a
                  [ HP.href (drepDetailHrefFor v), HP.class_ (HH.ClassName "link link-hover font-mono text-xs") ]
                  [ HH.text (DRepIdentity.shortId v) ]
              ]
          _, Just a ->
            HH.p [ HP.class_ (HH.ClassName "text-sm") ]
              [ HH.text "Filtered to the votes on "
              , HH.a
                  [ HP.href (actionDetailHrefFor a), HP.class_ (HH.ClassName "link link-hover font-mono text-xs") ]
                  [ HH.text a ]
              ]
          _, _ -> HH.text ""
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading votes…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The votes could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          ]
      ]

  body st page@(VotePage p) =
    HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "lg:col-span-1 space-y-4") ] [ sidebar st ]
      , HH.div [ HP.class_ (HH.ClassName "lg:col-span-3 space-y-3") ]
          [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text
                  ( formatInt p.total <> " votes match, showing "
                      <> show (p.offset + 1)
                      <> "–"
                      <> show (p.offset + length p.items)
                  )
              ]
          , table st page
          , pager st page
          ]
      ]

  sidebar st =
    HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
      [ filterBlock st "Verdict" "verdict" verdicts
      , filterBlock st "Voter" "voter_role" voterRoles
      , filterBlock st "Kind of action" "gov_action_type" actionTypes
      , finalBlock st
      ]

  filterBlock st title key values =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-3 gap-1") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "font-medium text-sm") ] [ HH.text title ]
          , HH.div [ HP.class_ (HH.ClassName "space-y-0.5") ] (map (filterRow st key) values)
          ]
      ]

  filterRow st key value =
    let
      selected = selectedFor key st.filters
      active = value `elem` selected
      next = withSelected key (toggleIn value selected) st.filters
    in
      HH.a
        [ HP.href (voteListHrefFor (next { offset = Nothing }))
        , HP.class_
            ( HH.ClassName
                ( "block text-xs rounded px-1 py-0.5 hover:bg-base-300 "
                    <> (if active then "bg-base-300 font-medium" else "")
                )
            )
        ]
        [ HH.text (if key == "voter_role" then roleLabel value else humanize value) ]

  -- Comutatorul care spune ce se numără: ultimul vot al fiecărui votant, sau fiecare vot exprimat,
  -- inclusiv cele înlocuite.
  finalBlock st =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-3 gap-1") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "font-medium text-sm") ] [ HH.text "What counts" ]
          , HH.a
              [ HP.href (voteListHrefFor (st.filters { is_final = Just "true", offset = Nothing }))
              , HP.class_
                  ( HH.ClassName
                      ( "block text-xs rounded px-1 py-0.5 hover:bg-base-300 "
                          <> (if st.filters.is_final == Just "true" then "bg-base-300 font-medium" else "")
                      )
                  )
              ]
              [ HH.text "Final vote only" ]
          , HH.a
              [ HP.href (voteListHrefFor (st.filters { is_final = Just "false", offset = Nothing }))
              , HP.class_
                  ( HH.ClassName
                      ( "block text-xs rounded px-1 py-0.5 hover:bg-base-300 "
                          <> (if st.filters.is_final == Just "false" then "bg-base-300 font-medium" else "")
                      )
                  )
              ]
              [ HH.text "Superseded votes only" ]
          , HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60 pt-1") ]
              [ HH.text "A voter may change its vote while an action is open; only the last one counts." ]
          ]
      ]

  table st (VotePage p) =
    HH.div [ HP.class_ (HH.ClassName "overflow-x-auto card bg-base-200") ]
      [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
          [ HH.thead_
              [ HH.tr_
                  [ HH.th_ [ HH.text "Voter" ]
                  , HH.th_ [ HH.text "Vote" ]
                  , HH.th_ [ HH.text "Proposal" ]
                  , sortHeader st "cast_at" "Cast" false
                  , sortHeader st "latency" "After" true
                  , HH.th_ [ HH.text "Reason" ]
                  ]
              ]
          , HH.tbody_ (map row p.items)
          ]
      ]

  sortHeader st column label alignRight =
    let
      sorted = st.filters.order_by == Just column
      arrow =
        if not sorted then ""
        else if st.filters.sort_order == Just "asc" then " ▲"
        else " ▼"

      next =
        if sorted then
          st.filters
            { sort_order = Just (if st.filters.sort_order == Just "asc" then "desc" else "asc")
            , offset = Nothing
            }
        else st.filters { order_by = Just column, sort_order = Just "desc", offset = Nothing }
    in
      HH.th [ HP.class_ (HH.ClassName (if alignRight then "text-right" else "")) ]
        [ HH.a
            [ HP.href (voteListHrefFor next)
            , HP.class_ (HH.ClassName ("link link-hover " <> (if sorted then "font-semibold" else "")))
            ]
            [ HH.text (label <> arrow) ]
        ]

  row (VoteRow v) =
    let
      ChainPoint at = v.castAt
    in
      HH.tr_
        [ HH.td [ HP.class_ (HH.ClassName "max-w-xs") ]
            [ HH.a [ HP.href (drepDetailHrefFor v.voterId), HP.class_ (HH.ClassName "hover:underline") ]
                [ DRepIdentity.render
                    { givenName: v.voterName, drepId: v.voterId, hasScript: false }
                ]
            , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ HH.text (roleLabel v.voterRole) ]
            ]
        , HH.td_
            [ HH.span [ HP.class_ (HH.ClassName ("badge badge-sm " <> verdictClass v.verdict)) ]
                [ HH.text (humanize v.verdict) ]
            -- Un vot înlocuit nu se ascunde și nu se numără ca încă unul: se spune ce e.
            , if v.isFinal then HH.text ""
              else
                HH.div [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                  [ HH.text ("superseded, " <> pluralize v.revoteCount "vote" <> " in all") ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "max-w-xs") ]
            [ HH.a
                [ HP.href (actionDetailHrefFor v.govActionId)
                , HP.class_ (HH.ClassName "hover:underline block min-w-0")
                ]
                [ HH.div [ HP.class_ (HH.ClassName "truncate text-sm") ]
                    [ HH.text (fromMaybe "Untitled proposal" v.govActionTitle) ]
                , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ HH.text (humanize v.govActionType) ]
                ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-sm whitespace-nowrap") ]
            [ HH.div_ [ HH.text ("epoch " <> show at.epoch) ]
            , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ HH.text at.time ]
            ]
        , HH.td [ HP.class_ (HH.ClassName "text-right font-mono whitespace-nowrap") ]
            [ HH.text (maybe "n/a" (\h -> toStringWith (fixed 1) h <> " h") v.latencyHours) ]
        , HH.td [ HP.class_ (HH.ClassName "text-xs") ] [ reason v.anchor ]
        ]

  -- Raționamentul: linkul se filtrează pe schemă, ca orice document străin, iar „valid" nu se
  -- confundă cu „conform CIP-100" — serverul le raportează separat, deci se arată separat.
  reason = case _ of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "opacity-50") ] [ HH.text "none published" ]
    Just (VoteAnchor a) ->
      HH.div [ HP.class_ (HH.ClassName "space-y-0.5") ]
        [ HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ]
            [ HH.text (maybe "unknown" humanize a.status) ]
        , case a.cip100Valid of
            Just true -> HH.div [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "CIP-100 valid" ]
            Just false -> HH.div [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "not CIP-100" ]
            Nothing -> HH.text ""
        , case a.url of
            Nothing -> HH.text ""
            Just url -> case Anchor.safeHref url of
              -- Un `ipfs://` nu devine link: ar însemna să alegem noi un gateway terț în numele
              -- cititorului. Se arată adresa, ca omul să decidă ce face cu ea.
              Nothing ->
                HH.span
                  [ HP.class_ (HH.ClassName "font-mono opacity-50 break-all"), HP.title url ]
                  [ HH.text (Anchor.clampText 40 url) ]
              Just href ->
                HH.a
                  [ HP.href href
                  , HP.target "_blank"
                  , HP.rel "nofollow noopener noreferrer"
                  , HP.class_ (HH.ClassName "link link-hover")
                  ]
                  [ HH.text "read it" ]
        ]

  -- Pagerul se oprește la 600, nu la 10.000: dincolo de treapta măsurată, o pagină ia 12 secunde.
  pager st (VotePage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset votesOffsetCeiling limit p.offset p.total
      hrefFor off = voteListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
        [ HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
            [ pagerLink prev hrefFor "Previous"
            , pagerLink next hrefFor "Next"
            ]
        , case next of
            Just _ -> HH.text ""
            Nothing ->
              if p.offset + length p.items >= p.total then
                HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ] [ HH.text "End of results." ]
              else
                HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                  [ HH.text
                      ( "This explorer stops at offset " <> show votesOffsetCeiling
                          <>
                            ". Past that point a page takes about twelve seconds to come back, so \
                            \narrowing the filters gets you there faster than paging does."
                      )
                  ]
        ]

  pagerLink target hrefFor label = case target of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off -> HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]

  selectedFor key f = case key of
    "verdict" -> f.verdict
    "voter_role" -> f.voter_role
    _ -> f.gov_action_type

  withSelected key values f = case key of
    "verdict" -> f { verdict = values }
    "voter_role" -> f { voter_role = values }
    _ -> f { gov_action_type = values }
