module Main where

import Prelude

import App.CopyOnClick (installCopyOnClick)
import App.SpaLinkInterceptor (installSpaLinkInterceptor)
import AppEnv (defaultEnv)
import AppM (runAppM)
import Components.Home as Home
import Effect (Effect)
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Store (initialStore)

-- | Production entry point: runs Halogen UI with AppM (real HTTP via affjax) and Home as root.
main :: Effect Unit
main = do
  installSpaLinkInterceptor
  installCopyOnClick
  HA.runHalogenAff do
    rootComponent <- runAppM defaultEnv initialStore Home.component
    body <- HA.awaitBody
    runUI rootComponent unit body
