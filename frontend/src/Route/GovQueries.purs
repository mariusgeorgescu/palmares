-- | Filtrele de listă, ca stare în URL și ca șir de interogare pentru API — din același record.
-- |
-- | Etichetele record-ului sunt scrise exact ca parametrii API-ului (`anchor_status`, nu
-- | `anchorStatus`), și toate valorile sunt `String`. Nu din lene de tipuri, ci pentru că asta face
-- | din URL-ul browserului și din interogarea trimisă serverului __aceeași__ listă de perechi: o
-- | singură funcție le produce pe amândouă, deci nu pot să se despartă. Unde ecranul are nevoie de
-- | un număr (pagerul), îl parsează el, prin clampările din `Query.Page`.
-- |
-- | Parametrii care se repetă se repetă: API-ul citește `status=active&status=inactive` ca listă.
-- | Forma cu virgulă e un status necunoscut — măsurat, serverul o refuză.
module Route.GovQueries
  ( DRepFilters
  , emptyDRepFilters
  , drepFiltersCodec
  , drepFilterPairs
  , renderQuery
  , renderDRepFilters
  , drepListPath
  , drepListHrefFor
  , drepDetailHrefFor
  , GovActionFilters
  , emptyGovActionFilters
  , govActionFiltersCodec
  , govActionFilterPairs
  , renderGovActionFilters
  , actionListPath
  , actionListHrefFor
  , actionDetailHrefFor
  , VoteFilters
  , emptyVoteFilters
  , defaultVoteFilters
  , voteFiltersCodec
  , voteFilterPairs
  , renderVoteFilters
  , voteListPath
  , voteListHrefFor
  , votesForDRepHref
  , votesForActionHref
  , encodePathSegment
  , toggleIn
  ) where

import Prelude

import Data.Array (delete, elem, filter, reverse, snoc)
import Data.Foldable (foldMap)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String (joinWith)
import Data.Tuple (Tuple(..), snd)
import JSURI (encodeURIComponent)
import Routing.Duplex (RouteDuplex(..), RouteDuplex', optional, param, prop, record)
import Routing.Duplex.Parser (RouteParser(..), RouteResult(..))
import Routing.Duplex.Printer as Printer
import Type.Proxy (Proxy(..))

type DRepFilters =
  { status :: Array String
  , anchor_status :: Array String
  , language :: Array String
  , has_script :: Maybe String
  , q :: Maybe String
  , min_voting_power :: Maybe String
  , max_voting_power :: Maybe String
  , order_by :: Maybe String
  , sort_order :: Maybe String
  , limit :: Maybe String
  , offset :: Maybe String
  }

emptyDRepFilters :: DRepFilters
emptyDRepFilters =
  { status: []
  , anchor_status: []
  , language: []
  , has_script: Nothing
  , q: Nothing
  , min_voting_power: Nothing
  , max_voting_power: Nothing
  , order_by: Nothing
  , sort_order: Nothing
  , limit: Nothing
  , offset: Nothing
  }

-- | Codecul pentru rută. Doar cei unsprezece parametri pe care un control din UI îi poate schimba;
-- | ceilalți nouă pe care îi acceptă `/pages/drep-explorer` n-au afordanță, deci n-au cod.
-- | Toate aparițiile unui parametru, nu doar prima.
-- |
-- | Scris de mână pentru că `Routing.Duplex.many (param k)` **nu termină**: `Parser.param` reușește
-- | fără să consume din stare (`lookup key state.params`, state neschimbat), iar `many1` se
-- | reapelează cu exact aceeași stare, la infinit. Măsurat: suita de teste a atârnat până la
-- | timeout pe o singură parsare de URL. Și chiar dacă ar termina, `param` citește doar prima
-- | apariție, deci lista ar avea mereu un singur element — adică filtrul ar pierde în silenție
-- | jumătate din ce a cerut omul.
repeatedParam :: String -> RouteDuplex' (Array String)
repeatedParam key = RouteDuplex printer parser
  where
  -- `Printer.param` pune perechea în __față__ (`Array.cons`), deci o listă scrisă în ordine ar
  -- ieși în URL invers. Inversăm la scriere ca `parse (print x) == x`: ordinea nu contează pentru
  -- server, dar un URL care se rescrie singur la fiecare clic contează pentru om.
  printer = foldMap (Printer.param key) <<< reverse

  parser = Chomp \state ->
    Success state (map snd (filter (\(Tuple k _) -> k == key) state.params))

-- | Codecul pentru rută, compus cu `prop` în loc de `params`, pentru că `params` construiește
-- | singur `param <label>` și nu lasă cheia la vedere — deci nu se poate pune `repeatedParam` în el.
drepFiltersCodec :: RouteDuplex' DRepFilters
drepFiltersCodec =
  record
    # prop (Proxy :: Proxy "status") (repeatedParam "status")
    # prop (Proxy :: Proxy "anchor_status") (repeatedParam "anchor_status")
    # prop (Proxy :: Proxy "language") (repeatedParam "language")
    # prop (Proxy :: Proxy "has_script") (optional (param "has_script"))
    # prop (Proxy :: Proxy "q") (optional (param "q"))
    # prop (Proxy :: Proxy "min_voting_power") (optional (param "min_voting_power"))
    # prop (Proxy :: Proxy "max_voting_power") (optional (param "max_voting_power"))
    # prop (Proxy :: Proxy "order_by") (optional (param "order_by"))
    # prop (Proxy :: Proxy "sort_order") (optional (param "sort_order"))
    # prop (Proxy :: Proxy "limit") (optional (param "limit"))
    # prop (Proxy :: Proxy "offset") (optional (param "offset"))

-- | Perechile trimise serverului, în ordinea în care le citește un om din URL.
drepFilterPairs :: DRepFilters -> Array (Tuple String String)
drepFilterPairs f =
  map (Tuple "status") f.status
    <> map (Tuple "anchor_status") f.anchor_status
    <> map (Tuple "language") f.language
    <> opt "has_script" f.has_script
    <> opt "q" f.q
    <> opt "min_voting_power" f.min_voting_power
    <> opt "max_voting_power" f.max_voting_power
    <> order
    <> opt "limit" f.limit
    <> opt "offset" f.offset
  where
  opt k = maybe [] \v -> [ Tuple k v ]

  -- `sort_order` nu pleacă niciodată singur, și când există `order_by` pleacă mereu: fără el
  -- serverul presupune `asc`, iar o presupunere nescrisă în URL e o sortare care se schimbă sub
  -- mâna cuiva care a dat linkul mai departe.
  order = case f.order_by of
    Nothing -> []
    Just ob -> [ Tuple "order_by" ob, Tuple "sort_order" (fromMaybe "asc" f.sort_order) ]

-- | Perechi → `?a=1&b=2`. Valorile se codează procentual: `q` e text introdus de om și poate
-- | conține `&`, `#` sau spații.
renderQuery :: Array (Tuple String String) -> String
renderQuery pairs = case pairs of
  [] -> ""
  _ -> "?" <> joinWith "&" (map pair pairs)
  where
  pair (Tuple k v) = k <> "=" <> fromMaybe v (encodeURIComponent v)

renderDRepFilters :: DRepFilters -> String
renderDRepFilters = renderQuery <<< drepFilterPairs

drepListPath :: String
drepListPath = "/dreps"

drepListHrefFor :: DRepFilters -> String
drepListHrefFor f = drepListPath <> renderDRepFilters f

-- | Un segment de cale, codat procentual. Nu e paranoia: ID-urile ajung aici din URL, iar un
-- | identificator de acțiune de guvernanță conține `#` prin construcție (`<txhash>#<index>`), care
-- | netratat ar tăia cererea la fragment și ar cere altceva decât s-a cerut.
encodePathSegment :: String -> String
encodePathSegment s = fromMaybe s (encodeURIComponent s)

drepDetailHrefFor :: String -> String
drepDetailHrefFor drepId = drepListPath <> "/" <> encodePathSegment drepId

-- | Un facet se comută: dacă valoarea e deja în listă, iese; altfel intră la coadă. Ordinea de
-- | adăugare se păstrează ca URL-ul să nu se rescrie singur la fiecare clic.
toggleIn :: String -> Array String -> Array String
toggleIn v xs = if v `elem` xs then delete v xs else snoc xs v

-- | Filtrele listei de acțiuni. `type_` e numele câmpului, `type` e numele parametrului: `type` e
-- | cuvânt rezervat în PureScript, iar cheia din URL o poartă codecul, nu eticheta record-ului.
type GovActionFilters =
  { type_ :: Array String
  , state :: Array String
  , anchor_status :: Array String
  , q :: Maybe String
  , order_by :: Maybe String
  , sort_order :: Maybe String
  , limit :: Maybe String
  , offset :: Maybe String
  }

emptyGovActionFilters :: GovActionFilters
emptyGovActionFilters =
  { type_: []
  , state: []
  , anchor_status: []
  , q: Nothing
  , order_by: Nothing
  , sort_order: Nothing
  , limit: Nothing
  , offset: Nothing
  }

govActionFiltersCodec :: RouteDuplex' GovActionFilters
govActionFiltersCodec =
  record
    # prop (Proxy :: Proxy "type_") (repeatedParam "type")
    # prop (Proxy :: Proxy "state") (repeatedParam "state")
    # prop (Proxy :: Proxy "anchor_status") (repeatedParam "anchor_status")
    # prop (Proxy :: Proxy "q") (optional (param "q"))
    # prop (Proxy :: Proxy "order_by") (optional (param "order_by"))
    # prop (Proxy :: Proxy "sort_order") (optional (param "sort_order"))
    # prop (Proxy :: Proxy "limit") (optional (param "limit"))
    # prop (Proxy :: Proxy "offset") (optional (param "offset"))

govActionFilterPairs :: GovActionFilters -> Array (Tuple String String)
govActionFilterPairs f =
  map (Tuple "type") f.type_
    <> map (Tuple "state") f.state
    <> map (Tuple "anchor_status") f.anchor_status
    <> opt "q" f.q
    <> order
    <> opt "limit" f.limit
    <> opt "offset" f.offset
  where
  opt k = maybe [] \v -> [ Tuple k v ]

  order = case f.order_by of
    Nothing -> []
    Just ob -> [ Tuple "order_by" ob, Tuple "sort_order" (fromMaybe "asc" f.sort_order) ]

renderGovActionFilters :: GovActionFilters -> String
renderGovActionFilters = renderQuery <<< govActionFilterPairs

actionListPath :: String
actionListPath = "/gov-actions"

actionListHrefFor :: GovActionFilters -> String
actionListHrefFor f = actionListPath <> renderGovActionFilters f

-- | Un identificator de acțiune e `<txhash>#<index>`. `#` netratat ar tăia cererea la fragment,
-- | deci ar cere pagina listei în loc de acțiune.
actionDetailHrefFor :: String -> String
actionDetailHrefFor actionId = actionListPath <> "/" <> encodePathSegment actionId

-- | Filtrele explorerului de voturi.
type VoteFilters =
  { voter_role :: Array String
  , verdict :: Array String
  , gov_action_type :: Array String
  , voter_id :: Maybe String
  , gov_action_id :: Maybe String
  , q :: Maybe String
  , is_final :: Maybe String
  , order_by :: Maybe String
  , sort_order :: Maybe String
  , limit :: Maybe String
  , offset :: Maybe String
  }

emptyVoteFilters :: VoteFilters
emptyVoteFilters =
  { voter_role: []
  , verdict: []
  , gov_action_type: []
  , voter_id: Nothing
  , gov_action_id: Nothing
  , q: Nothing
  , is_final: Nothing
  , order_by: Nothing
  , sort_order: Nothing
  , limit: Nothing
  , offset: Nothing
  }

-- | Explorerul de voturi nu interoghează niciodată nefiltrat, și asta nu e o preferință de produs.
-- |
-- | Măsurat pe serverul care rulează: `/votes` fără niciun filtru raportează `total: 3.244.726`, pe
-- | o rețea cu 131 de acțiuni și ~900 de voturi reale. Orice filtru îl repară — pe acțiune 43, pe
-- | votant 1, `is_final=true` 934 — deci numărătoarea nefiltrată e un defect de server, nu un fapt
-- | despre lanț. Un ecran care ar tipări 3,2 milioane ar minți cu un factor de 3.500, iar pagerul
-- | ar oferi zece mii de pagini goale.
-- |
-- | `is_final=true` e și default-ul corect ca înțeles: un DRep poate să-și schimbe votul cât
-- | acțiunea e deschisă, iar votul care a contat e ultimul. Filtrul se vede pe ecran ca oricare
-- | altul și se poate scoate — dar „curăță filtrele" duce aici, nu la zero filtre.
defaultVoteFilters :: VoteFilters
defaultVoteFilters = emptyVoteFilters { is_final = Just "true" }

voteFiltersCodec :: RouteDuplex' VoteFilters
voteFiltersCodec =
  record
    # prop (Proxy :: Proxy "voter_role") (repeatedParam "voter_role")
    # prop (Proxy :: Proxy "verdict") (repeatedParam "verdict")
    # prop (Proxy :: Proxy "gov_action_type") (repeatedParam "gov_action_type")
    # prop (Proxy :: Proxy "voter_id") (optional (param "voter_id"))
    # prop (Proxy :: Proxy "gov_action_id") (optional (param "gov_action_id"))
    # prop (Proxy :: Proxy "q") (optional (param "q"))
    # prop (Proxy :: Proxy "is_final") (optional (param "is_final"))
    # prop (Proxy :: Proxy "order_by") (optional (param "order_by"))
    # prop (Proxy :: Proxy "sort_order") (optional (param "sort_order"))
    # prop (Proxy :: Proxy "limit") (optional (param "limit"))
    # prop (Proxy :: Proxy "offset") (optional (param "offset"))

voteFilterPairs :: VoteFilters -> Array (Tuple String String)
voteFilterPairs f =
  map (Tuple "voter_role") f.voter_role
    <> map (Tuple "verdict") f.verdict
    <> map (Tuple "gov_action_type") f.gov_action_type
    <> opt "voter_id" f.voter_id
    <> opt "gov_action_id" f.gov_action_id
    <> opt "q" f.q
    <> opt "is_final" f.is_final
    <> order
    <> opt "limit" f.limit
    <> opt "offset" f.offset
  where
  opt k = maybe [] \v -> [ Tuple k v ]

  order = case f.order_by of
    Nothing -> []
    Just ob -> [ Tuple "order_by" ob, Tuple "sort_order" (fromMaybe "asc" f.sort_order) ]

renderVoteFilters :: VoteFilters -> String
renderVoteFilters = renderQuery <<< voteFilterPairs

voteListPath :: String
voteListPath = "/votes"

voteListHrefFor :: VoteFilters -> String
voteListHrefFor f = voteListPath <> renderVoteFilters f

-- | Linkul din pagina unui DRep spre voturile lui. Fără `is_final`: pe pagina unui DRep, un vot
-- | schimbat e parte din povestea lui.
votesForDRepHref :: String -> String
votesForDRepHref drepId = voteListHrefFor (emptyVoteFilters { voter_id = Just drepId })

votesForActionHref :: String -> String
votesForActionHref actionId = voteListHrefFor (emptyVoteFilters { gov_action_id = Just actionId })
