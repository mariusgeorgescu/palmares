-- | Top-level route ADT for the application.
module Route
  ( Route(..)
  ) where

import Data.Generic.Rep (class Generic)
import Prelude
import Route.GovQueries (DRepFilters, renderDRepFilters)

-- Rutele se adaugă pe măsură ce ecranele se livrează (plan, taskurile 5–11), nu în avans: o rută
-- fără pagină e un link care duce la NotFound.
data Route
  = Home
  -- Filtrele călătoresc în rută, nu în starea componentei: URL-ul e stare partajabilă, iar
  -- butoanele înainte/înapoi ale browserului sunt controale ale ecranului, nu accidente.
  | DRepList DRepFilters
  | NotFound

derive instance eqRoute :: Eq Route
derive instance Generic Route _

-- `Show` e pentru mesaje de eroare și teste: un „expected DRepList ?status=active but got
-- NotFound" spune de ce a eșuat parsarea, iar un `false /= true` nu spune nimic.
--
-- Scris de mână, nu `genericShow`: reprezentarea generică a unui record de unsprezece câmpuri l-a
-- ținut pe `purs` peste șapte minute pe un singur modul, fără să termine. Oricum tipărește mai
-- citibil — URL-ul, nu arborele.
instance Show Route where
  show = case _ of
    Home -> "Home"
    DRepList f -> "DRepList " <> renderDRepFilters f
    NotFound -> "NotFound"
