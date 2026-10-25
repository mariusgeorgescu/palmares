module MainDemo where

import Prelude

import App.CopyOnClick (installCopyOnClick)
import App.SpaLinkInterceptor (installSpaLinkInterceptor)
import AppEnv (defaultEnv)
import Components.Home as Home
import DemoM (runDemoM)
import Effect (Effect)
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Store (initialStore)

-- | Demo entry point: runs Halogen UI with DemoM (mock data) and Home as root.
-- | Used by `npm run dev` and the default `npm run build` so the app boots
-- | without a real backend.
main :: Effect Unit
main = do
  installSpaLinkInterceptor
  installCopyOnClick
  HA.runHalogenAff do
    rootComponent <- runDemoM defaultEnv initialStore Home.component
    body <- HA.awaitBody
    runUI rootComponent unit body
