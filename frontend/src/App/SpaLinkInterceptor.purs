-- | Catches `<a href="/...">` clicks and turns them into history.pushState
-- | so internal links don't trigger full page reloads. Install once from `Main`.
module App.SpaLinkInterceptor where

import Prelude
import Effect (Effect)

foreign import installSpaLinkInterceptorImpl :: Effect Unit

installSpaLinkInterceptor :: Effect Unit
installSpaLinkInterceptor = installSpaLinkInterceptorImpl
