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
