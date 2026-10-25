-- | O desfășurare pe intervale, ca bare orizontale. Fiecare bară e un link: un interval de putere
-- | de vot e un filtru, iar un filtru care se vede trebuie să se și poată aplica.
-- |
-- | Lățimea barei e relativă la cel mai mare interval, nu la total. Procentul din total ar fi
-- | corect aici — `power_buckets` e singura desfășurare care însumează la `total`, pentru că
-- | fiecare DRep cade în exact un interval — dar relativ la maxim se citește mai bine când un
-- | interval conține jumătate din populație.
module Components.Chart.Histogram
  ( Bar
  , render
  ) where

import Prelude

import Data.Array (null)
import Data.Foldable (maximum)
import Data.Int (toNumber)
import Data.Maybe (fromMaybe)
import Data.Number.Format (fixed, toStringWith)
import Format (formatInt)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

type Bar =
  { label :: String
  , count :: Int
  , href :: String
  , active :: Boolean
  }

render :: forall w i. Array Bar -> HH.HTML w i
render bars =
  let
    peak = toNumber (fromMaybe 1 (maximum (map _.count bars)))

    widthPct b =
      if peak <= 0.0 then 0.0
      else toNumber b.count / peak * 100.0

    row b =
      HH.a
        [ HP.href b.href
        , HP.class_
            ( HH.ClassName
                ( "flex items-center gap-2 text-xs rounded px-1 py-2 lg:py-0.5 hover:bg-base-300 "
                    <> (if b.active then "bg-base-300 font-medium" else "")
                )
            )
        ]
        [ HH.span [ HP.class_ (HH.ClassName "w-36 shrink-0 text-right opacity-70") ] [ HH.text b.label ]
        , HH.span [ HP.class_ (HH.ClassName "flex-1 h-3 bg-base-100 rounded overflow-hidden") ]
            [ HH.span
                [ HP.class_ (HH.ClassName "block h-3 bg-secondary")
                , HP.style ("width: " <> toStringWith (fixed 1) (widthPct b) <> "%")
                ]
                []
            ]
        , HH.span [ HP.class_ (HH.ClassName "w-12 shrink-0 text-right font-mono") ] [ HH.text (formatInt b.count) ]
        ]
  in
    if null bars then
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-60") ] [ HH.text "No distribution available." ]
    else HH.div [ HP.class_ (HH.ClassName "space-y-1") ] (map row bars)
