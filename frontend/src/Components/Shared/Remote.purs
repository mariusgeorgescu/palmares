-- | Cele două stări care nu sunt date: „se încarcă" și „n-a venit".
-- |
-- | Erau scrise de mână în fiecare ecran: șaptesprezece carduri de încărcare identice în afară de
-- | propoziție, și optsprezece alerte de eroare identice în afară de titlu — iar comentariul care
-- | explică DE CE există butonul de reîncercare era copiat în cinci dintre ele. Asta nu e doar
-- | volum: sunt optsprezece locuri în care se repară un cuvânt, și cinci în care se repară o
-- | decizie. Precedentul proiectului e `Shared/Pager.purs`, extras când erau nouă copii.
-- |
-- | Ce NU se mută aici e propoziția. Fiecare ecran spune ce n-a putut încărca EL — „The profiles
-- | could not be loaded", „This proposal could not be loaded" — iar un „Something went wrong"
-- | partajat ar fi exact pierderea pentru care n-ar merita extragerea.
module Components.Shared.Remote
  ( loadingCard
  , errorCard
  , errorCardAbout
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Data.Maybe (Maybe(..))
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

-- | Cardul de încărcare, cu propoziția ecranului. Un card, nu un spinner singur: ocupă locul pe
-- | care îl va ocupa conținutul, deci pagina nu sare când sosește.
loadingCard :: forall w i. String -> HH.HTML w i
loadingCard says =
  HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
    [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
        [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
        , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text says ]
        ]
    ]

-- | Alerta de eroare: ce n-a putut fi încărcat, ce a spus serverul, și o ieșire.
-- |
-- | __Butonul nu e decor.__ Un ecran de eroare fără nimic de apăsat e un fund de sac: singura
-- | ieșire rămâne reîncărcarea din browser, care pe rutele lente costă încă o dată cele ~30 de
-- | secunde de așteptare. `retry` e acțiunea componentei, de obicei aceeași pe care o folosește și
-- | reîmprospătarea după o scriere confirmată.
errorCard :: forall w i. String -> ApiError -> i -> HH.HTML w i
errorCard says err retry = alert says Nothing err retry

-- | Ca `errorCard`, plus identificatorul care n-a putut fi citit.
-- |
-- | Există separat pentru paginile de detaliu, și nu ca un `Maybe` la call site: acolo „n-a putut fi
-- | încărcat" fără să spună CARE e o propoziție pe care nimeni n-o poate acționa — nici cel care se
-- | uită la ecran, nici cel căruia i se raportează.
errorCardAbout :: forall w i. String -> String -> ApiError -> i -> HH.HTML w i
errorCardAbout says about err retry = alert says (Just about) err retry

alert :: forall w i. String -> Maybe String -> ApiError -> i -> HH.HTML w i
alert says about err retry =
  HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
    [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
        ( [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text says ] ]
            <> case about of
              Nothing -> []
              Just id_ -> [ HH.p [ HP.class_ (HH.ClassName "font-mono text-xs break-all") ] [ HH.text id_ ] ]
            <>
              [ HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError err) ]
              , HH.button
                  [ HP.class_ (HH.ClassName "btn btn-sm")
                  , HP.type_ HP.ButtonButton
                  , HE.onClick (const retry)
                  ]
                  [ HH.text "Try again" ]
              ]
        )
    ]
