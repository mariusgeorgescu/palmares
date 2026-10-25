-- | Identitatea unui DRep pe ecran: numele **și** ID-ul, mereu amândouă.
-- |
-- | Regula R8/R3 din design: amenințarea aici nu e injecția, e impersonarea. `given_name` vine
-- | dintr-un document de metadate pe care îl scrie oricine, și două profiluri pot revendica
-- | „Intersect" în același timp. Numele singur nu identifică nimic, deci ID-ul nu e un detaliu de
-- | pagină de detaliu — stă lângă nume oriunde apare numele. Măsurat: 154 din 200 de DRep-i n-au
-- | niciun nume, deci cazul „fără nume" e cazul obișnuit, nu excepția.
module Components.Shared.DRepIdentity
  ( Identity
  , identityText
  , render
  , shortId
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Data.String as String
import Data.String.CodeUnits as CU
import AppEnv as AppEnv
import Components.Shared.OnchainId as OnchainId
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

type Identity =
  { givenName :: Maybe String
  , drepId :: String
  , hasScript :: Boolean
  }

-- | `drep1ygzlzlzj8…z9rwhm`. Prefixul rămâne întreg cât să se vadă tipul de credențial (CIP-129),
-- | iar coada cât să distingă două ID-uri puse una lângă alta.
shortId :: String -> String
shortId s =
  if String.length s <= 24 then s
  else CU.take 14 s <> "…" <> CU.takeRight 6 s

-- | Cele două texte care ajung pe ecran, ca funcție pură — ca regula „ID-ul merge lângă nume" să
-- | fie verificabilă de un test, nu doar vizibilă într-un arbore de HTML.
-- |
-- | R2: lungimea se taie aici, nu se speră. `given_name` vine dintr-un document străin, iar
-- | `truncate` din CSS ascunde depășirea fără să o limiteze — un nume de 10.000 de caractere ar
-- | rămâne întreg în DOM.
identityText :: Identity -> { name :: String, id :: String, named :: Boolean }
identityText ident = case ident.givenName of
  Just n | String.trim n /= "" ->
    { name: clamp80 (String.trim n), id: shortId ident.drepId, named: true }
  _ ->
    { name: "Unnamed DRep", id: shortId ident.drepId, named: false }
  where
  clamp80 n = if String.length n <= 80 then n else CU.take 80 n <> "…"

render :: forall w i. Identity -> HH.HTML w i
render ident =
  HH.div [ HP.class_ (HH.ClassName "flex flex-col gap-0.5 min-w-0") ]
    [ HH.div [ HP.class_ (HH.ClassName "flex items-center gap-2") ]
        [ HH.span [ HP.class_ (HH.ClassName nameClass) ] [ HH.text text.name ]
        , if ident.hasScript then
            -- Un DRep script nu e același fel de obiect ca un DRep cu cheie: votul lui e decis de un
            -- validator, nu de o semnătură. Diferența se vede, nu se deduce.
            HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ] [ HH.text "script" ]
          else HH.text ""
        ]
    -- Scurtat pentru citit, întreg pentru copiat — iar „pentru copiat" cere mai mult decît un
    -- `title`: textul unui tooltip nativ nu e selectabil, deci vechea versiune promitea ceva ce nu
    -- livra. Chipul deschide valoarea întreagă, un link către explorer și o copiere adevărată.
    , HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
        [ OnchainId.withChip
            { value: ident.drepId
            , shown: text.id
            , kind: OnchainId.DRep
            , explorerBase: AppEnv.explorerBase
            }
        ]
    ]
  where
  text = identityText ident

  nameClass =
    if text.named then "font-medium truncate"
    else "font-medium italic opacity-70 truncate"
