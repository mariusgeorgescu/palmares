-- | Afordanța „ⓘ" de lângă o metrică: un link spre formula care a produs-o.
-- |
-- | E un `<a>` cu `href`, nu un tooltip și nu un modal: o explicație pe care n-o poți da mai
-- | departe ca link nu e verificabilă de nimeni, iar pe un ecran de reputație verificabilitatea e
-- | tot ce vindem.
module Components.Shared.MetricInfo
  ( render
  , renderLabelled
  ) where

import Prelude

import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Route.GovQueries (methodologyHrefFor)

render :: forall w i. String -> HH.HTML w i
render formulaId =
  HH.a
    [ HP.href (methodologyHrefFor formulaId)
    , HP.class_ (HH.ClassName "opacity-70 hover:opacity-100 text-xs align-super px-2 py-2")
    , HP.title ("How " <> formulaId <> " is computed")
    -- Glifa singură nu e un nume: un cititor de ecran anunța „circled latin small letter i, link".
    -- Numele accesibil spune unde duce, iar glifa rămâne doar decor.
    , HP.attr (HH.AttrName "aria-label") ("How " <> formulaId <> " is computed")
    ]
    [ HH.span [ HP.attr (HH.AttrName "aria-hidden") "true" ] [ HH.text "ⓘ" ] ]

-- | Eticheta unei metrici cu „ⓘ" lipit de ea.
renderLabelled :: forall w i. String -> String -> HH.HTML w i
renderLabelled label formulaId =
  HH.span_
    [ HH.text label
    , render formulaId
    ]
