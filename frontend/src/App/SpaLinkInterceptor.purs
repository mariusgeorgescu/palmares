-- | Catches `<a href="/...">` clicks and turns them into history.pushState
-- | so internal links don't trigger full page reloads. Install once from `Main`.
module App.SpaLinkInterceptor where

import Prelude
import Effect (Effect)

foreign import installSpaLinkInterceptorImpl :: Effect Unit

installSpaLinkInterceptor :: Effect Unit
installSpaLinkInterceptor = installSpaLinkInterceptorImpl

foreign import normaliseTrailingSlashImpl :: Effect Unit

-- | Taie un slash final din adresă înainte ca routerul s-o vadă. Se cheamă o dată, din `Main`,
-- | ÎNAINTEA pornirii aplicației: routerul parsează cu codecul direct, deci o normalizare pusă în
-- | `parseRoute` nu l-ar atinge niciodată.
normaliseTrailingSlash :: Effect Unit
normaliseTrailingSlash = normaliseTrailingSlashImpl
