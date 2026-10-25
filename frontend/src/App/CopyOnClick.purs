-- | Copierea în clipboard, ca un singur listener delegat pe `document`. Se instalează o dată din
-- | `Main`.
-- |
-- | Orice element cu `data-copy="<valoare>"` devine copiabil: la click, valoarea ajunge în
-- | clipboard și elementul primește clasa `copied` pentru ~1,2 s, pe care CSS-ul o folosește ca să
-- | schimbe „Copy" în „Copied!".
-- |
-- | __De ce nu un handler Halogen.__ Butonul apare în vreo zece locuri. Un `HE.onClick` ar cere un
-- | constructor de `Action` în fiecare componentă gazdă și o clasă de capabilitate pentru
-- | clipboard — exact forma în care a fost împins `bjj-frontend`, și motivul pentru care chipul lui
-- | nu e `forall w i`. Cu listenerul delegat, chipul nostru rămâne HTML pur: fără monadă, fără
-- | stare, folosibil din orice funcție de randare.
-- |
-- | Confirmarea vine din JavaScript, nu din `:focus` ca în bjj: acolo un Tab pe buton arăta
-- | „Copied!" înainte să se copieze ceva.
module App.CopyOnClick (installCopyOnClick) where

import Prelude

import Effect (Effect)

foreign import installCopyOnClickImpl :: Effect Unit

installCopyOnClick :: Effect Unit
installCopyOnClick = installCopyOnClickImpl
