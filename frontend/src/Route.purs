-- | Top-level route ADT for the application.
module Route
  ( Route(..)
  ) where

import Data.Generic.Rep (class Generic)
import Prelude

-- Rutele se adaugă pe măsură ce ecranele se livrează (plan, taskurile 5–11), nu în avans: o rută
-- fără pagină e un link care duce la NotFound.
data Route
  = Home
  | NotFound

derive instance eqRoute :: Eq Route
derive instance Generic Route _
