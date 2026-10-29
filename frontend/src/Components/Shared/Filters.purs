-- | Controalele de filtrare și sortare ale listelor.
-- |
-- | Cele trei liste ale registrului n-aveau niciunul: zero `select`, zero `input`, în timp ce
-- | `order_by`, `sort_order`, `kind`, `subject`, `issuer` traversau deja codecul, iar serverul
-- | accepta pe deasupra `q`, `claimed`, `accepted` și `resolved`. Jumătate cablat în patru
-- | direcții, și nimic de apăsat.
-- |
-- | __Starea stă în URL, nu în componentă__, și de aceea controalele nu au stare: o schimbare e o
-- | navigare, iar ecranul reinteroghează din `Receive` fiindcă filtrele i-au venit altfel. Asta
-- | face ca o listă filtrată să fie o adresă pe care o dai cuiva — și e singurul motiv pentru care
-- | controalele astea sînt pure.
module Components.Shared.Filters
  ( bar
  , chosen
  , selectControl
  , boolControl
  , searchControl
  ) where

import Prelude

import Data.Array (cons)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..), fst, snd)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Web.Event.Internal.Types (Event)

-- | Ce a ales omul, ca filtru. Opțiunea „Any" are valoarea vidă, iar un `Just ""` ar ajunge la
-- | server ca un filtru care nu se potrivește cu nimic — deci golul înseamnă „fără filtru", peste
-- | tot, într-un singur loc.
chosen :: String -> Maybe String
chosen "" = Nothing
chosen v = Just v

-- | Rîndul de controale. Se înfășoară pe telefon, unde trei `select`-uri nu încap pe un rînd.
-- |
-- | Grup cu nume, nu un `div` oarecare: un cititor de ecran anunță „Filters" înainte de cele patru
-- | controale, iar fără el „Kind" de aici și „Kind" din cardul unui profil sînt indistingibile —
-- | pentru om și pentru un test.
bar :: forall w i. Array (HH.HTML w i) -> HH.HTML w i
bar = HH.div
  [ HP.class_ (HH.ClassName "flex flex-wrap items-end gap-2")
  , HP.attr (HH.AttrName "role") "group"
  , HP.attr (HH.AttrName "aria-label") "Filters"
  ]

-- | Un `select` cu etichetă. `value` e ce spune URL-ul; prima opțiune e „fără filtru" și are
-- | valoarea vidă, pentru că un filtru care nu se poate scoate e o capcană.
selectControl
  :: forall w i
   . { label :: String
     , value :: Maybe String
     , options :: Array (Tuple String String)
     , onChange :: String -> i
     }
  -> HH.HTML w i
selectControl c =
  HH.label [ HP.class_ (HH.ClassName "form-control") ]
    [ HH.span [ HP.class_ (HH.ClassName "label-text text-xs opacity-70") ] [ HH.text c.label ]
    , HH.select
        [ HP.class_ (HH.ClassName "select select-sm select-bordered")
        , HP.value (fromMaybe "" c.value)
        , HE.onValueChange c.onChange
        ]
        (map option (Tuple "" "Any" `cons` c.options))
    ]
  where
  option o = HH.option [ HP.value (fst o) ] [ HH.text (snd o) ]

-- | Un filtru de tip da/nu, ca `select` și nu ca bifă: o bifă are două stări, iar întrebarea are
-- | trei — da, nu, și „nu mă interesează", care e cea implicită.
boolControl
  :: forall w i
   . { label :: String, value :: Maybe String, yes :: String, no :: String, onChange :: String -> i }
  -> HH.HTML w i
boolControl c =
  selectControl
    { label: c.label
    , value: c.value
    , options: [ Tuple "true" c.yes, Tuple "false" c.no ]
    , onChange: c.onChange
    }

-- | Căutarea pe text. Un formular, deci Enter funcționează; iar cererea pleacă la TRIMITERE, nu la
-- | fiecare tastă — altfel fiecare literă ar fi o navigare în istoricul browserului și o cerere.
-- |
-- | __`onSubmit` primește evenimentul, și trebuie să-l oprească.__ Fără `preventDefault`, browserul
-- | trimite formularul nativ: o încărcare completă a paginii, care pierde SPA-ul și ajunge pe
-- | `/profiles` fără niciun parametru — adică exact opusul căutării. Măsurat în browser: adresa
-- | rămînea fără `?q=`.
searchControl
  :: forall w i
   . { label :: String, draft :: String, onInput :: String -> i, onSubmit :: Event -> i }
  -> HH.HTML w i
searchControl c =
  HH.form
    [ HP.class_ (HH.ClassName "form-control")
    , HE.onSubmit c.onSubmit
    ]
    [ HH.span [ HP.class_ (HH.ClassName "label-text text-xs opacity-70") ] [ HH.text c.label ]
    , HH.div [ HP.class_ (HH.ClassName "join") ]
        [ HH.input
            [ HP.class_ (HH.ClassName "input input-sm input-bordered join-item")
            , HP.type_ HP.InputText
            , HP.value c.draft
            , HP.placeholder "name or description"
            , HE.onValueInput c.onInput
            ]
        , HH.button
            [ HP.class_ (HH.ClassName "btn btn-sm join-item")
            , HP.type_ HP.ButtonSubmit
            ]
            [ HH.text "Search" ]
        ]
    ]
