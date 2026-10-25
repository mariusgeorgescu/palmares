-- | Paginarea și sortarea, într-un singur loc, pentru că fiecare din regulile de aici a fost
-- | măsurată pe serviciul care rulează și niciuna nu e publicată în swagger.
-- |
-- | Swagger-ul declară pentru `limit` și `offset` bounds-urile de Int64
-- | (`minimum: -9223372036854775808`), deci un client generat din schemă ar valida orice. Clamp-urile
-- | reale și plafonul de offset sunt aici. Vezi `docs/usecases/api-screen-map.md` §3.1.
module Query.Page
  ( SortOrder(..)
  , PageQuery
  , defaultPageQuery
  , renderSortOrder
  , clampLimit
  , nextOffset
  , prevOffset
  , renderPageQuery
  , offsetCeiling
  , votesOffsetCeiling
  , listLimitMax
  , activityLimitMax
  , searchLimitMax
  ) where

import Prelude

import Data.Array (catMaybes)
import Data.Maybe (Maybe(..))
import Data.String (joinWith)

data SortOrder = Asc | Desc

derive instance Eq SortOrder
derive instance Ord SortOrder

instance Show SortOrder where
  show = renderSortOrder

renderSortOrder :: SortOrder -> String
renderSortOrder = case _ of
  Asc -> "asc"
  Desc -> "desc"

-- | `sortOrder` nu e `Maybe`, și asta e intenționat.
-- |
-- | `order_by` trimis fără `sort_order` înseamnă `asc` pe server (`Query/Common.hs:155`), deci
-- | „sortează după putere de vot" ar arăta cei mai slabi DRep-i primii. Un câmp obligatoriu face
-- | imposibil să-l uiți; `renderPageQuery` îl emite doar când există un `order_by` de însoțit.
type PageQuery =
  { limit :: Int
  , offset :: Int
  , orderBy :: Maybe String
  , sortOrder :: SortOrder
  }

defaultPageQuery :: PageQuery
defaultPageQuery = { limit: 50, offset: 0, orderBy: Nothing, sortOrder: Desc }

-- | Plafonul dur de offset: `offset=10000` răspunde, `offset=10001` dă `400 offset_too_large`.
offsetCeiling :: Int
offsetCeiling = 10000

-- | Plafonul pe care ni-l impunem singuri pe `/votes`, mai jos decât cel al serverului.
-- |
-- | Măsurat: 1,1 s la offset 600, 12,15 s la offset 800 — o funcție în trepte, nu o degradare lină.
-- | ADR 0009 decide că nu se repară, deci pager-ul se oprește înainte de treaptă și oferă filtrare
-- | în loc de adâncime. Un utilizator care vrea voturile acelui DRep le ia filtrate, nu răsfoite.
votesOffsetCeiling :: Int
votesOffsetCeiling = 600

-- | Maximul real pe rutele de listă (`/dreps`, `/gov-actions`, `/votes`, …).
listLimitMax :: Int
listLimitMax = 200

-- | `/activity` e singura rută cu cursor și are propriul maxim.
activityLimitMax :: Int
activityLimitMax = 20

searchLimitMax :: Int
searchLimitMax = 100

-- | Taie o cerere la ce ruta acceptă. Zero și negativele urcă la 1: serverul le clampează oricum,
-- | dar un `limit=0` trimis înseamnă o pagină goală randată ca „nu există date", care e o minciună.
clampLimit :: Int -> Int -> Int
clampLimit maximum requested
  | requested < 1 = 1
  | requested > maximum = maximum
  | otherwise = requested

-- | Offset-ul paginii următoare, sau `Nothing` când nu există una — fie pentru că s-a terminat
-- | setul, fie pentru că următorul pas ar trece plafonul și ar lua 400.
-- |
-- | Primul argument e plafonul, ca `/votes` să-și poată da pe al lui.
-- `let`, nu `where` cu guards: un `where` după guards e ambiguu la indentare, iar `purs-tidy` îl
-- reindentează sub ultimul guard — ceea ce îl scoate din scope-ul celorlalte și nu mai compilează.
nextOffset :: Int -> Int -> Int -> Int -> Maybe Int
nextOffset ceiling limit offset total =
  let
    candidate = offset + limit
  in
    if candidate >= total then Nothing
    else if candidate > ceiling then Nothing
    else Just candidate

prevOffset :: Int -> Int -> Maybe Int
prevOffset limit offset
  | offset <= 0 = Nothing
  | offset - limit < 0 = Just 0
  | otherwise = Just (offset - limit)

-- | Query string-ul, fără `?`. `sort_order` apare dacă și numai dacă apare `order_by`: singur n-are
-- | ce să ordoneze, iar `order_by` singur alege implicit `asc`.
renderPageQuery :: PageQuery -> String
renderPageQuery q =
  joinWith "&" $ catMaybes
    [ Just ("limit=" <> show q.limit)
    , Just ("offset=" <> show q.offset)
    , map (\o -> "order_by=" <> o) q.orderBy
    , map (\_ -> "sort_order=" <> renderSortOrder q.sortOrder) q.orderBy
    ]
