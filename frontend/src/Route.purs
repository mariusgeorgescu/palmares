-- | Top-level route ADT for the application.
module Route
  ( Route(..)
  ) where

import Data.Generic.Rep (class Generic)
import Prelude

data Route
  = Home
  | Items
  | NotFound

derive instance eqRoute :: Eq Route
derive instance Generic Route _
