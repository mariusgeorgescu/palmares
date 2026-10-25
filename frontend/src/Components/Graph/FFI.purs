-- | Legătura cu Cytoscape. Patru funcții, toate imperative, toate în `FFI.js`.
-- |
-- | Tipurile de aici sunt contractul: un nod are un id, o etichetă și un steag care spune dacă e
-- | rădăcina, iar o muchie are capetele și o etichetă. Nimic despre culori sau despre layout —
-- | alea sunt decizii de desen și stau în JavaScript, unde se pot citi din tema curentă.
module Components.Graph.FFI
  ( GraphInstance
  , GraphNode
  , GraphEdge
  , initGraph
  , setElements
  , fitGraph
  , destroyGraph
  ) where

import Prelude

import Effect (Effect)
import Web.HTML.HTMLElement (HTMLElement)

foreign import data GraphInstance :: Type

type GraphNode =
  { id :: String
  , label :: String
  , isRoot :: Boolean
  }

type GraphEdge =
  { id :: String
  , source :: String
  , target :: String
  , label :: String
  }

foreign import initGraph :: HTMLElement -> Effect GraphInstance

foreign import setElements :: GraphInstance -> Array GraphNode -> Array GraphEdge -> Effect Unit

foreign import fitGraph :: GraphInstance -> Effect Unit

foreign import destroyGraph :: GraphInstance -> Effect Unit
