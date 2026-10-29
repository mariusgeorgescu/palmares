-- | Reinterogarea după o scriere confirmată, într-un singur loc.
-- |
-- | Cu 45 de secunde între trimitere și proiecție, un ecran care încarcă o dată la montare arată
-- | registrul DINAINTE de scrierea pe care omul tocmai a făcut-o — iar el stă și se uită la locul
-- | unde ar trebui să apară. Defectul e în jurnalul M2-1: „ecranele registrului nu reinterogheaza".
-- |
-- | Ce lipsea până acum nu era abonamentul, era momentul: nimeni nu știa CÂND se confirmă o
-- | tranzacție, fiindcă ecranul de scriere făcea o singură verificare, imediat după trimitere, când
-- | e garantat prea devreme. Învelișul urmărește acum confirmarea, deci există ce să se anunțe.
-- |
-- | O linie per ecran, și anume aceeași linie: opt componente aveau deja `Initialize -> fork load`
-- | și `Retry -> load` identice, iar un abonament copiat de opt ori ar fi fost opt locuri în care
-- | se repară o decizie.
module Components.Shared.Refresh
  ( subscribeRefresh
  ) where

import Prelude

import Halogen as H
import Halogen.Store.Monad (class MonadStore, emitSelected, getStore)
import Halogen.Store.Select (selectEq)
import Halogen.Subscription as HS
import Store as Store

-- | Abonează componenta la cheia de reîmprospătare și declanșează acțiunea dată la fiecare
-- | schimbare a ei. Se cheamă din `Initialize`, cu acțiunea care reîncarcă ecranul — de obicei
-- | aceeași pe care o folosește butonul de reîncercare.
-- |
-- | `selectEq` pe `refreshKey`, nu pe tot `Store`-ul: altfel conectarea unui wallet ar reinteroga
-- | fiecare ecran montat, iar o reinterogare pe care n-a cerut-o nimeni e exact genul de lucru
-- | care face o pagină să clipească fără motiv.
-- |
-- | __Filtrul nu e prudență, e necesar, și e MĂSURAT.__ `selectEmitter` din halogen-store pornește
-- | cu `previousDerived = Nothing`, deci PRIMUL eveniment de `Store` trece oricare ar fi valoarea
-- | selectată — dedupul lui începe abia de la al doilea. Prins în browser: cu abonamentul neflitrat,
-- | o conectare de wallet pe `/profiles` producea o a treia cerere către `/api/query/profiles`,
-- | deși nicio scriere nu se confirmase. `refreshKey` doar crește, deci „mai mare decît cît era cînd
-- | ecranul s-a montat" e exact „s-a confirmat o scriere de atunci încoace".
subscribeRefresh
  :: forall st act slots out m
   . MonadStore Store.Action Store.Store m
  => act
  -> H.HalogenM st act slots out m Unit
subscribeRefresh action = do
  seen <- _.refreshKey <$> getStore
  emitter <- emitSelected (selectEq _.refreshKey)
  void (H.subscribe (const action <$> HS.filter (_ > seen) emitter))
