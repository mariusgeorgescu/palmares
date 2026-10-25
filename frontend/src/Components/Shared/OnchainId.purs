-- | Un identificator on-chain, afișat ca om și verificabil ca mașină.
-- |
-- | Problema pe care o rezolvă, măsurată pe deploy: identificatorii apar ca text monospațiat
-- | trunchiat cu elipsă — `648c6a732aa55e…d1458b` — iar valoarea întreagă nu e accesibilă nicăieri.
-- | Unele locuri pun un `HP.title`, cu un comentariu care spune „cel întreg e pentru copiat", dar
-- | **un `title` nu se poate copia**: textul unui tooltip nativ nu e selectabil. Iar id-ul unei
-- | atestări sau al unei dispute nu era randat deloc, deși ecranul de scriere cere utilizatorului
-- | să-l „lipească" — deci calea de scriere documentată nu putea fi parcursă din interfață.
-- |
-- | Forma: logo-ul Cardano ca declanșator, iar la hover un panou cu valoarea ÎNTREAGĂ, un link către
-- | explorer și un buton de copiere. E componenta din `bjj-frontend`
-- | (`Components/Shared/OnchainExplorerLink.purs`), cu trei diferențe:
-- |
-- |   1. __`forall w i`, fără monadă și fără `onCopy`.__ Copierea merge prin listenerul delegat din
-- |      `App.CopyOnClick`, deci chipul e HTML pur și se poate folosi din orice funcție de randare.
-- |      Varianta din bjj cere `onCopy :: String -> i`, adică un constructor de Action în fiecare
-- |      componentă gazdă.
-- |   2. __Fără amprentă CIP-14.__ bjj convertește id-ul în `asset1…` cu `blakejs` + `bech32`, două
-- |      dependențe npm. Măsurat pe `preprod.cexplorer.io`: `/asset/<policy>.<name>` se rezolvă
-- |      direct, iar explorerul face conversia singur. Forma noastră de id e deja ce acceptă el.
-- |   3. __Fără `svgMaskStyle`.__ Tailwind 4 are utilitare de mască, deci stilul inline de 400 de
-- |      caractere devine o clasă.
module Components.Shared.OnchainId
  ( IdKind(..)
  , explorerUrl
  , chip
  , withChip
  ) where

import Prelude

import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

-- | Ce fel de lucru e identificatorul. Decide calea din explorer, iar fiecare a fost verificată în
-- | browser pe `preprod.cexplorer.io` — nu ghicită din documentație.
-- |
-- | `Asset` acoperă profiluri, atestări și dispute: toate trei sunt tokenuri CIP-68 sub aceeași
-- | politică, iar id-ul lor e `policy.name`, exact forma pe care explorerul o primește.
data IdKind
  = Asset
  | Tx
  | DRep
  | Policy

derive instance Eq IdKind

-- | Adresa din explorer pentru un identificator.
-- |
-- | Verificat în browser (cardanoscan întoarce 403 chiar și la un Chromium headless, deci nu se
-- | poate măsura; cexplorer răspunde):
-- |
-- |   * `/asset/<policy>.<name>` se rezolvă și afișează `asset1…` — conversia o face explorerul;
-- |   * `/asset/<policy><name>` (fără punct) cade pe pagina de pornire, fără eroare. De aceea
-- |     punctul NU se scoate din id;
-- |   * `/tx/<hash>` și `/drep/<bech32>` se rezolvă;
-- |   * `/policy/<hex>` listează tokenurile politicii.
explorerUrl :: String -> IdKind -> String -> String
explorerUrl base kind value = base <> path <> value
  where
  path = case kind of
    Asset -> "/asset/"
    Tx -> "/tx/"
    DRep -> "/drep/"
    Policy -> "/policy/"

-- | Logo-ul Cardano, ca mască peste `currentColor`, deci moștenește culoarea linkului.
logo :: forall w i. HH.HTML w i
logo =
  HH.span
    [ HP.class_
        ( HH.ClassName
            "w-4 h-4 inline-block shrink-0 bg-current \
            \[mask-image:url(/images/cardano-logo.svg)] [mask-size:contain] \
            \[mask-position:center] [mask-repeat:no-repeat]"
        )
    , HP.attr (HH.AttrName "aria-hidden") "true"
    ]
    []

-- | Chipul singur: logo-ul, iar la hover valoarea întreagă, linkul și copierea.
-- |
-- | `dropdown-end` ca panoul să nu iasă din tabel pe dreapta, iar `z-50` fiindcă rândurile de tabel
-- | creează contexte de stivuire proprii.
chip :: forall w i. { value :: String, kind :: IdKind, explorerBase :: String } -> HH.HTML w i
chip { value, kind, explorerBase } =
  HH.span [ HP.class_ (HH.ClassName "dropdown dropdown-hover dropdown-end shrink-0") ]
    [ HH.span
        [ HP.class_ (HH.ClassName "btn btn-ghost btn-xs p-0.5 opacity-60 hover:opacity-100")
        , HP.tabIndex 0
        , HP.attr (HH.AttrName "role") "button"
        , HP.title "On-chain proof"
        ]
        [ logo ]
    , HH.div
        [ HP.class_
            ( HH.ClassName
                "dropdown-content z-50 bg-base-200 rounded-box shadow-lg p-2 w-72 max-w-[90vw]"
            )
        ]
        [ -- Valoarea ÎNTREAGĂ, selectabilă, cu `break-all` ca să nu împingă panoul în lățime. Asta
          -- e jumătatea care lipsea: până acum valoarea completă nu exista pe ecran.
          HH.a
            [ HP.class_
                ( HH.ClassName
                    "font-mono text-xs break-all link link-hover text-base-content/90 block mb-2"
                )
            , HP.href (explorerUrl explorerBase kind value)
            , HP.target "_blank"
            , HP.rel "noopener noreferrer"
            ]
            [ HH.text value ]
        , HH.button
            [ HP.class_
                (HH.ClassName "btn btn-ghost btn-xs gap-2 w-full justify-start copy-btn")
            , HP.type_ HP.ButtonButton
            -- Listenerul delegat din `App.CopyOnClick` citește atributul ăsta. Fără handler, fără
            -- Action, fără stare.
            , HP.attr (HH.AttrName "data-copy") value
            , HP.attr (HH.AttrName "aria-label") "Copy the full identifier"
            ]
            [ HH.span
                [ HP.class_
                    ( HH.ClassName
                        "w-4 h-4 inline-block shrink-0 bg-current \
                        \[mask-image:url(/images/copy-icon.svg)] [mask-size:contain] \
                        \[mask-position:center] [mask-repeat:no-repeat]"
                    )
                , HP.attr (HH.AttrName "aria-hidden") "true"
                ]
                []
            , HH.span [ HP.class_ (HH.ClassName "copy-label") ] [ HH.text "Copy" ]
            , HH.span [ HP.class_ (HH.ClassName "copy-confirm") ] [ HH.text "Copied!" ]
            ]
        ]
    ]

-- | Textul scurtat plus chipul, forma folosită în liste.
-- |
-- | `min-w-0` pe container: fără el, `truncate` de pe text nu are efect într-un flex, iar rândul
-- | împinge tabelul în lățime — defectul pe care regula R2 îl interzice.
withChip
  :: forall w i
   . { value :: String, shown :: String, kind :: IdKind, explorerBase :: String }
  -> HH.HTML w i
withChip { value, shown, kind, explorerBase } =
  HH.span [ HP.class_ (HH.ClassName "inline-flex items-center gap-1 min-w-0 max-w-full") ]
    [ HH.span [ HP.class_ (HH.ClassName "font-mono text-xs truncate") ] [ HH.text shown ]
    , chip { value, kind, explorerBase }
    ]
