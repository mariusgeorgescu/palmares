-- | O serie în timp, desenată din bare. Nu e o componentă Halogen: n-are stare proprie, deci e o
-- | funcție de randare pe care o apelează ecranul.
-- |
-- | Planul cerea SVG scris de mână. Barele cu `div` sunt mai puțin cod decât același grafic în SVG
-- | (fără `viewBox`, fără scalare de coordonate, fără dependență nouă), se scalează singure pe
-- | lățime, iar valoarea exactă a fiecărui punct ajunge la utilizator prin `title` — tooltipul
-- | nativ al browserului. Dacă vreodată e nevoie de o linie de trend adevărată, interfața de aici
-- | nu se schimbă.
module Components.Chart.Series
  ( Point
  , render
  ) where

import Prelude

import Data.Array (head, last, null)
import Data.Foldable (maximum)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Number.Format (fixed, toStringWith)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

type Point =
  { label :: String
  , value :: Number
  , hint :: String
  }

-- | Înălțimea fiecărei bare e relativă la cea mai mare valoare din serie, nu la 100%: o serie de
-- | participare care stă toată între 0 și 20% ar fi altfel o linie plată lipită de axă.
-- |
-- | Corpul e un `let`, nu un `where` după gărzi: purs-tidy reindentează un `where` pus după gărzi
-- | sub ultima gardă și îl scoate din domeniul celorlalte.
render :: forall w i. Array Point -> HH.HTML w i
render points =
  let
    peak = fromMaybe 1.0 (maximum (map _.value points))

    -- O valoare de zero rămâne o bară de 2% din înălțime: altfel „n-a votat nimeni în epoca 311" ar
    -- arăta identic cu „epoca 311 nu e în serie".
    heightPct p =
      if peak <= 0.0 then 2.0
      else max 2.0 (p.value / peak * 100.0)

    bar p =
      HH.div
        [ HP.class_ (HH.ClassName "flex-1 bg-primary rounded-t")
        , HP.style ("height: " <> toStringWith (fixed 1) (heightPct p) <> "%")
        , HP.title (p.label <> ": " <> p.hint)
        ]
        []

    edgeLabel pick = case pick points of
      Nothing -> ""
      Just p -> p.label
  in
    if null points then
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-60") ] [ HH.text "No data for this range." ]
    else
      HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
        [ HH.div [ HP.class_ (HH.ClassName "flex items-end gap-1 h-32") ] (map bar points)
        , HH.div [ HP.class_ (HH.ClassName "flex justify-between text-xs opacity-60") ]
            [ HH.span_ [ HH.text (edgeLabel head) ]
            , HH.span_ [ HH.text (edgeLabel last) ]
            ]
        ]
