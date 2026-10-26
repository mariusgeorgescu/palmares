-- | Paginatorul listelor, într-un singur loc.
-- |
-- | __Defectul pe care îl repară, raportat de owner: „paginarea nu merge".__ Nu era stricată — nu
-- | AVEA ce face. Măsurat pe deploy: 14 profiluri, 22 de atestări, 6 dispute, toate sub limita de 50,
-- | deci „Previous" și „Next" erau dezactivate amândouă, pe toate ecranele, tot timpul. Două butoane
-- | moarte permanent, cu un număr între ele, arată exact ca un control rupt — iar un utilizator care
-- | apasă și nu se întâmplă nimic are dreptate să creadă că e rupt.
-- |
-- | Deci: cînd nu există nici pagină anterioară, nici următoare, nu se randează butoane deloc. Rămâne
-- | doar totalul, care e singura informație adevărată în situația aia. Butoanele reapar singure în
-- | clipa în care registrul trece de o pagină.
-- |
-- | De ce un modul partajat și nu o reparație în fiecare ecran: erau NOUĂ copii ale aceleiași
-- | funcții, iar ownerul a cerut explicit consistență între liste. Nouă copii înseamnă nouă șanse ca
-- | următoarea schimbare să prindă doar opt.
module Components.Shared.Pager
  ( render
  ) where

import Prelude

import Data.Maybe (Maybe(..), isNothing)
import Format (pluralize)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

-- | `prev`/`next` sunt deplasările către paginile vecine, `Nothing` cînd nu există.
-- |
-- | `offset`, `shown` și `ceiling` există doar ca să poată SPUNE de ce „Next" e dezactivat. Șase
-- | dintre cele nouă ecrane aveau deja mesajul ăsta și trei nu — iar cele trei erau tocmai cele din
-- | registru, unde ownerul a observat că paginarea „nu merge". Varianta bogată a cîștigat: un buton
-- | dezactivat fără explicație e indistinguibil de unul rupt.
render
  :: forall w i
   . { total :: Int
     , offset :: Int
     , shown :: Int
     , ceiling :: Int
     , prev :: Maybe Int
     , next :: Maybe Int
     , hrefFor :: Int -> String
     -- Forma de SINGULAR. `pluralize` o acordă: „1 challenge in total", nu „1 challenges in total" —
     -- greșeală pe care șase din cele nouă ecrane o evitau deja și trei nu.
     , noun :: String
     }
  -> HH.HTML w i
render { total, offset, shown, ceiling, prev, next, hrefFor, noun } =
  if isNothing prev && isNothing next then
    -- O singură pagină: nu există unde naviga, deci nu se randează comenzi. Totalul rămâne, fiindcă
    -- e informație. Butoanele reapar singure cînd registrul trece de o pagină.
    HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
      [ HH.text (pluralize total noun <> " in total") ]
  else
    HH.div [ HP.class_ (HH.ClassName "flex items-center justify-between gap-2") ]
      [ link prev "Previous"
      , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text middle ]
      , link next "Next"
      ]
  where
  -- Cît timp mai e unde merge, numărul total e tot ce trebuie spus. La capăt, se spune de ce nu mai
  -- e: „am terminat" și „mai sînt, dar nu pe calea asta" sînt două lucruri diferite, iar al doilea
  -- are o soluție pe care utilizatorul o poate aplica.
  middle = case next of
    Just _ -> pluralize total noun <> " in total"
    Nothing ->
      if offset + shown >= total then "End of results."
      else "Deeper pages are refused past offset " <> show ceiling
        <> "; narrow the filters instead."

  -- Capătul listei păstrează butonul, dezactivat: acolo el SPUNE ceva — „ai ajuns la margine" — iar
  -- dispariția lui ar muta „Next" sub degetul care tocmai a apăsat „Previous".
  link target label = case target of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "btn btn-sm btn-disabled") ] [ HH.text label ]
    Just off -> HH.a [ HP.href (hrefFor off), HP.class_ (HH.ClassName "btn btn-sm") ] [ HH.text label ]
