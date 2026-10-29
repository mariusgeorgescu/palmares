-- | Notificările care supraviețuiesc navigării.
-- |
-- | Ecranul de scriere spune pe el însuși unde e tranzacția. Problema e ce se întîmplă după: o
-- | confirmare vine în minute, iar omul pleacă de pe ecran între timp — se uită la profilul pe care
-- | tocmai l-a atestat. Starea din componenta aceea moare la demontare, deci fără notificări
-- | nimeni nu mai află niciodată că tranzacția a intrat. Astea se randează în înveliș, nu în ecran,
-- | exact pentru asta.
-- |
-- | Lista și numărătoarea stau la rădăcină; aici sînt doar tipul, scăderea și randarea.
-- | `renderToasts` vine din `halogen-daisyui`, deci nu se desenează nimic de mînă.
module Components.Shared.Toast
  ( Level(..)
  , Toast
  , toast
  , levelClass
  , tick
  , render
  ) where

import Prelude

import Data.Array (filter)
import Data.Tuple (Tuple(..))
import Halogen.DaisyUI.Components (renderToasts)
import Halogen.HTML as HH

-- | Severitatea, nu culoarea. `levelClass` e singurul loc unde devine o clasă daisyUI — un
-- | `String` purtat prin aplicație ar fi lăsat o greșeală de tipar să ajungă pe ecran ca o alertă
-- | fără culoare.
data Level
  = Info
  | Success
  | Warning
  | Error

derive instance Eq Level

levelClass :: Level -> String
levelClass = case _ of
  Info -> "info"
  Success -> "success"
  Warning -> "warning"
  Error -> "error"

type Toast =
  { level :: Level
  , message :: String
  -- Cîte secunde mai are de trăit. Scade la fiecare tic al rădăcinii.
  , secondsLeft :: Int
  }

-- | Șase secunde. Mesajele de aici sînt propoziții, nu cuvinte, iar cinci secunde nu ajung pentru
-- | una care conține un identificator de tranzacție.
toast :: Level -> String -> Toast
toast level message = { level, message, secondsLeft: 6 }

-- | O secundă mai puțin pentru fiecare, și afară cele care au expirat.
tick :: Array Toast -> Array Toast
tick = filter (\t -> t.secondsLeft > 0) <<< map (\t -> t { secondsLeft = t.secondsLeft - 1 })

render :: forall w i. Array Toast -> HH.HTML w i
render = renderToasts <<< map (\t -> Tuple (levelClass t.level) t.message)
