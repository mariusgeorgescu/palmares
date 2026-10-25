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
    , HP.class_ (HH.ClassName "opacity-50 hover:opacity-100 text-xs align-super")
    , HP.title ("How " <> formulaId <> " is computed")
    ]
    [ HH.text "ⓘ" ]

-- | Eticheta unei metrici cu „ⓘ" lipit de ea.
renderLabelled :: forall w i. String -> String -> HH.HTML w i
renderLabelled label formulaId =
  HH.span_
    [ HH.text label
    , render formulaId
    ]
