-- | Ecranul de scriere: cele nouă fluxuri, fiecare prin aceeași secvență.
-- |
-- | Secvența e construiește → semnează → trimite → așteaptă, iar fiecare pas se NUMEȘTE pe ecran,
-- | pentru că fiecare înseamnă altceva pentru om: pînă la „trimite" nu s-a întîmplat nimic pe
-- | lanț, iar după el nu se mai poate lua înapoi. Un singur indicator de încărcare peste tot ar
-- | șterge exact distincția care contează.
-- |
-- | __Poarta de wallet e înaintea formularului, nu înaintea butonului.__ Dacă rețeaua nu poate fi
-- | determinată, nu se completează un formular întreg ca să afli la final că n-ai voie: se spune
-- | de la început, cu motivul, și formularul nici nu se desenează.
module Components.Write.Runner
  ( Slot
  , Output
  , _writeRunner
  , component
  ) where

import Prelude

import AppEnv (Env)
import Capabilities.Interaction.MonadInteract (class MonadInteract, buildFlow, interactionStatus, submitSigned, txStatus)
import Capabilities.Query.Gov.Http (renderApiError)
import Capabilities.Wallet.Governance (class MonadGovWallet, GateVerdict(..), blockMessage, connectGovernance, hasExtension)
import Capabilities.Interaction.Types (InteractionStatus(..), OracleGate(..), OracleParams(..), UserAddresses, oracleGate)
import Components.Shared.DRepIdentity (shortId)
import Components.Write.Flows (FieldKind(..), buildRequest, flowSpecs, missingFields, specFor)
import Components.Write.TxSummaryDecode (summarise)
import Format (formatAda, pluralize)
import Control.Monad.Reader (class MonadAsk)
import Cardano.Wallet.Cip30 (Api, getAvailableWallets, getChangeAddress, getUsedAddresses, signTx)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Data.Tuple (Tuple(..))
import Effect.Aff (Aff, attempt)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Exception (message)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Route (Route)
import Route.GovQueries (WriteFilters, writeHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_writeRunner :: Proxy "writeRunner"
_writeRunner = Proxy

type Input = WriteFilters

-- | Pașii, fiecare cu numele lui. `Built` e separat de `Submitted` tocmai pentru că între ele e
-- | singura diferență care nu se poate anula.
data Step
  = Idle
  | Connecting
  | Building
  | Built String
  -- Cei trei pași de după construire, fiecare cu numele lui pe ecran. „Signing" e singurul în care
  -- așteptarea e a OMULUI, nu a rețelei, iar „Submitted" e primul în care ceva s-a întâmplat pe
  -- lanț și nu se mai poate lua înapoi.
  | Signing String
  | Submitting
  | Submitted String
  | Confirmed String
  | Failed String

type State =
  { filters :: WriteFilters
  , values :: Map String String
  , gate :: Maybe GateVerdict
  -- Starea protocolului, citită o dată la intrarea pe ecran.
  , oracle :: Maybe InteractionStatus
  -- Dacă răspunsul a SOSIT. Fără flag-ul ăsta, `Nothing` înseamnă deopotrivă „încă se încarcă" și
  -- „n-am putut afla", iar ecranul arăta avertismentul alarmant („nu putem ști dacă protocolul e
  -- oprit") la fiecare încărcare, timp de o clipă, înainte să se liniștească. Un avertisment care
  -- apare și dispare singur învață omul să nu citească avertismentele.
  , oracleAsked :: Boolean
  , wallets :: Array String
  , step :: Step
  }

data Action
  = Initialize
  | Receive Input
  | Connect String
  | SetField String String
  | Submit
  | SignAndSubmit String

component
  :: forall q m
   . MonadInteract m
  => MonadAff m
  => MonadEffect m
  => MonadGovWallet m
  => MonadAsk Env m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, values: seedFrom filters, gate: Nothing, oracle: Nothing, oracleAsked: false, wallets: [], step: Idle }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  -- Ce vine din URL intră în formular. Un link din lista de atestări care spune „contestă asta"
  -- trebuie să aducă atestarea cu el, altfel omul copiază un identificator de 60 de caractere.
  seedFrom filters = case filters.subject of
    Nothing -> Map.empty
    Just s ->
      Map.fromFoldable (map (\k -> Tuple k s) (subjectKeysFor (fromMaybe "" filters.flow)))

  handleAction = case _ of
    -- Starea oracolului se cere ÎNAINTE de orice: dacă protocolul e oprit, nu are rost nici
    -- măcar să conectezi wallet-ul.
    Initialize -> do
      -- Wallet-urile din browser se citesc, nu se presupun: un buton „Connect Lace" pe o mașină
      -- fără Lace e un buton care nu face nimic, iar unul care spune „Connect wallet" fără să
      -- zică pe care nu dă omului nicio informație despre ce i se va deschide.
      names <- liftEffect getAvailableWallets
      H.modify_ _ { wallets = names }
      res <- interactionStatus
      H.modify_ _
        { oracleAsked = true
        , oracle = case res of
            Left _ -> Nothing
            Right st -> Just st
        }
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters, values = seedFrom filters, step = Idle }
    Connect walletName -> do
      H.modify_ _ { step = Connecting }
      verdict <- connectGovernance walletName
      H.modify_ _ { gate = Just verdict, step = Idle }
    SetField k v -> H.modify_ \st -> st { values = Map.insert k v st.values }
    Submit -> do
      st <- H.get
      case st.gate of
        Just (Allowed _) -> runBuild st
        _ -> pure unit

    -- Semnătura e a wallet-ului, trimiterea e a serverului, iar între ele nu e nimic al nostru.
    -- Un refuz la semnare NU e o eroare a aplicației: omul a apăsat „Decline", iar ecranul trebuie
    -- să spună asta și să lase butonul apăsabil.
    SignAndSubmit tx -> do
      st <- H.get
      case st.gate of
        Just (Allowed w) -> do
          H.modify_ _ { step = Signing tx }
          signed <- H.liftAff (attempt (signTx w.api tx true))
          case signed of
            Left err ->
              H.modify_ _
                { step = Failed
                    ( "The wallet did not sign"
                        <> (if message err == "" then "" else " (" <> message err <> ")")
                        <> ". Nothing has been submitted; you can try again."
                    )
                }
            Right witness -> do
              H.modify_ _ { step = Submitting }
              res <- submitSigned { txUnsigned: tx, txWit: witness }
              case res of
                Left e -> H.modify_ _ { step = Failed (renderApiError e) }
                Right txId -> do
                  H.modify_ _ { step = Submitted txId }
                  -- O singură verificare, nu o buclă: confirmarea vine în minute, iar un ecran
                  -- care ar bate la ușă în fundal ar cheltui bateria cuiva ca să afle un lucru
                  -- pe care tx-ul îl spune oricum. `Submitted` e deja starea ireversibilă.
                  confirmed <- txStatus txId
                  case confirmed of
                    Right true -> H.modify_ _ { step = Confirmed txId }
                    _ -> pure unit
        _ -> pure unit

  -- Se construiește cu adresele wallet-ului. Nu se semnează aici: semnătura e a wallet-ului, iar
  -- trimiterea e pasul pe care produsul îl ține deliberat separat.
  runBuild st = case st.filters.flow, st.gate of
    Just flowId, Just (Allowed w) -> do
      H.modify_ _ { step = Building }
      -- ADRESELE VIN DIN WALLET, iar versiunea dinainte trimitea o listă goală și o adresă de rest
      -- goală: serverul alege intrările și dă restul pe baza lor, deci cu ele goale nu putea
      -- construi nimic. Nu s-a văzut pe fixturi, unde `buildFlow` e un mock care întoarce un CBOR
      -- oricum.
      addrs <- H.liftAff (walletAddresses w.api)
      case addrs of
        Nothing ->
          H.modify_ _
            { step = Failed
                "The wallet did not return an address to build from. Reconnect and try again."
            }
        Just addresses -> case buildRequest flowId st.values addresses of
          Nothing -> H.modify_ _ { step = Failed "Some required fields are still empty." }
          Just req -> do
            res <- buildFlow req
            H.modify_ _
              { step = case res of
                  Left e -> Failed (renderApiError e)
                  Right tx -> Built tx
              }
    _, _ -> pure unit

  -- `OracleUnknown` cît timp n-a răspuns încă: ecranul nu promite nimic pe baza unui răspuns care
  -- n-a venit. Când vine, devine ce spune serverul.
  protocolGate st = case st.oracle of
    Nothing -> OracleUnknown
    Just s -> oracleGate s

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4") ]
      [ header
      , HH.div [ HP.class_ (HH.ClassName "grid gap-4 lg:grid-cols-4") ]
          [ HH.div [ HP.class_ (HH.ClassName "lg:col-span-1") ] [ flowList st ]
          , HH.div [ HP.class_ (HH.ClassName "lg:col-span-3 min-w-0 space-y-4") ]
              [ walletCard st
              , case st.filters.flow >>= specFor of
                  Nothing -> pickOne
                  Just spec -> flowCard st spec
              ]
          ]
      ]

  header =
    HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
      [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Act on chain" ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
          [ HH.text
              "The nine things this registry lets you write. Every one of them is a transaction you \
              \sign yourself — nothing here is submitted on your behalf."
          ]
      ]

  flowList st =
    HH.ul [ HP.class_ (HH.ClassName "menu bg-base-200 rounded-box w-full") ]
      (map (flowLink st) flowSpecs)

  flowLink st spec =
    HH.li_
      [ HH.a
          [ HP.href (writeHrefFor { flow: Just spec.id, subject: st.filters.subject })
          , HP.class_
              ( HH.ClassName
                  (if st.filters.flow == Just spec.id then "menu-active font-semibold text-primary" else "")
              )
          ]
          [ HH.text spec.title ]
      ]

  pickOne =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "Pick what you want to do." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text "Each one says what it writes and what it costs before it asks for anything." ]
          ]
      ]

  -- Matricea de compatibilitate (M2-4): ce zice wallet-ul că poate, ce s-a negociat, ce există cu
  -- adevărat — și verdictul, ÎNAINTE de orice semnătură.
  walletCard st = case st.gate of
    Nothing ->
      HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
        [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
            [ HH.p_ [ HH.text "Connect a wallet to see what it can and cannot do here." ]
            , if null st.wallets then
                HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
                  [ HH.text "No Cardano wallet is installed in this browser." ]
              else
                HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-2") ]
                  (map (walletButton st) st.wallets)
            ]
        ]
    Just (Allowed w) ->
      HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
        [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
            [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-center gap-2") ]
                [ HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-success") ] [ HH.text "ready" ]
                , HH.span [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text w.capabilities.walletName ]
                ]
            , matrix w.capabilities
            ]
        ]
    Just (Blocked reason caps) ->
      HH.div [ HP.class_ (HH.ClassName "card bg-base-200 border border-warning") ]
        [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
            [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-center gap-2") ]
                [ HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-warning") ] [ HH.text "cannot write" ]
                , HH.span [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text caps.walletName ]
                ]
            , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (blockMessage reason) ]
            , matrix caps
            -- Un refuz fără cale de întoarcere e un fund de sac: cineva care a apăsat „Decline"
            -- din greșeală, sau care tocmai a schimbat rețeaua în wallet, trebuie să poată
            -- încerca din nou fără să reîncarce pagina. Prins de `cip30-test-wallet` cu
            -- `enableRejected`: ecranul rămînea cu matricea și fără niciun buton.
            , HH.div [ HP.class_ (HH.ClassName "card-actions") ]
                [ HH.button
                    [ HP.class_ (HH.ClassName "btn btn-sm")
                    , HP.type_ HP.ButtonButton
                    , HE.onClick (const (Connect caps.walletName))
                    ]
                    [ HH.text (if st.step == Connecting then "Connecting…" else "Connect " <> caps.walletName) ]
                ]
            ]
        ]

  walletButton st name =
    HH.button
      [ HP.class_ (HH.ClassName "btn btn-sm btn-primary")
      , HP.type_ HP.ButtonButton
      , HE.onClick (const (Connect name))
      ]
      [ HH.text (if st.step == Connecting then "Connecting…" else "Connect " <> name) ]

  -- Cele trei forme de detecție, una lîngă alta. Se arată toate pentru că se CONTRAZIC în
  -- practică, iar un wallet refuzat deși „scrie pe cutie" că suportă extensia e exact cazul în
  -- care omul are nevoie să vadă unde s-a rupt lanțul.
  matrix caps =
    HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
      [ HH.table [ HP.class_ (HH.ClassName "table table-xs") ]
          [ HH.thead_
              [ HH.tr_
                  [ HH.th_ [ HH.text "Extension" ]
                  , HH.th_ [ HH.text "Advertised" ]
                  , HH.th_ [ HH.text "Negotiated" ]
                  , HH.th_ [ HH.text "Actually present" ]
                  ]
              ]
          , HH.tbody_
              [ extRow "CIP-95 (governance keys)" 95 caps caps.cip95Present
              , extRow "CIP-142 (network magic)" 142 caps caps.cip142Present
              ]
          ]
      ]

  extRow label cip caps present =
    HH.tr_
      [ HH.td_ [ HH.text label ]
      , yesNo (hasExtension cip caps.advertised)
      , yesNo (hasExtension cip caps.negotiated)
      , yesNo present
      ]

  yesNo b =
    HH.td_
      [ HH.span
          [ HP.class_ (HH.ClassName ("badge badge-xs " <> if b then "badge-success" else "badge-outline")) ]
          [ HH.text (if b then "yes" else "no") ]
      ]

  flowCard st spec =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-3") ]
          [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text spec.title ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-80") ] [ HH.text spec.summary ]
          , if not st.oracleAsked then
              -- Încă se întreabă. Nu se promite nimic și nu se sperie nimeni.
              HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text "Checking the protocol…" ]
            else case protocolGate st, st.gate of
              OracleOpen, Just (Allowed _) -> form st spec
              OracleOpen, _ -> gateNote
              g, _ -> oracleNote g
          ]
      ]

  -- Oracolul e o poartă diferită de wallet, și se spune ca atare: „protocolul e oprit" nu e
  -- aceeași problemă cu „wallet-ul tău nu poate", iar un singur mesaj pentru amândouă ar trimite
  -- omul să-și schimbe wallet-ul degeaba.
  oracleNote = case _ of
    OracleOpen -> HH.text ""
    OraclePaused ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-warning text-sm") ]
        [ HH.span_
            [ HH.text
                "The oracle has paused this protocol. Nothing can be written until whoever holds \
                \that authority resumes it. Reading is unaffected."
            ]
        ]
    OracleUnknown ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-warning text-sm") ]
        [ HH.span_
            [ HH.text
                "We cannot tell whether this protocol is paused, so nothing will be built. A \
                \transaction built against a paused protocol is rejected by the validator after \
                \you have already signed it."
            ]
        ]
    ScriptsMissing ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-error text-sm") ]
        [ HH.span_
            [ HH.text
                "The protocol's scripts are not on this chain, so there is nothing to write \
                \against. This is a deployment problem, not something you can fix here."
            ]
        ]

  -- Formularul nu se desenează fără poartă deschisă. Un formular completat degeaba e o pierdere
  -- de timp pe care o puteai spune de la început.
  gateNote =
    HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
      [ HH.text "Connect a wallet that can write here, and this form appears." ]

  form st spec =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.div [ HP.class_ (HH.ClassName "grid gap-3 md:grid-cols-2") ] (map (field st) spec.fields)
      , HH.div [ HP.class_ (HH.ClassName "alert alert-warning text-sm") ]
          [ HH.span_ [ HH.text (consequenceOf st spec) ] ]
      , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-center gap-3") ]
          [ HH.button
              [ HP.class_ (HH.ClassName "btn btn-primary btn-sm")
              , HP.type_ HP.ButtonButton
              , HP.disabled (not (null (missingFields spec st.values)) || st.step == Building)
              , HE.onClick (const Submit)
              ]
              [ HH.text (if st.step == Building then "Building…" else "Build the transaction") ]
          , missingNote spec st
          ]
      , stepNote st
      ]

  -- Depozitul se scrie cu NUMĂRUL cerut acum de oracol, nu cu „un depozit": e ce riscă omul, și e
  -- singurul parametru al protocolului care îl costă direct.
  consequenceOf st spec =
    if spec.id /= "open-dispute" then spec.consequence
    else case st.oracle of
      Just (InteractionStatus s) -> case s.oracle of
        Just (OracleParams o) ->
          "Locks " <> formatAda o.disputeDepositLovelace
            <> " from your wallet until the dispute resolves. You lose it if the dispute is dismissed."
        Nothing -> spec.consequence
      Nothing -> spec.consequence

  missingNote spec st =
    let
      missing = missingFields spec st.values
    in
      if null missing then HH.text ""
      else
        HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
          [ HH.text (show (length missing) <> " required field(s) still empty") ]

  field st spec =
    HH.label [ HP.class_ (HH.ClassName "form-control w-full") ]
      [ HH.div [ HP.class_ (HH.ClassName "label") ]
          [ HH.span [ HP.class_ (HH.ClassName "label-text text-sm") ]
              [ HH.text (spec.label <> (if spec.required then "" else " (optional)")) ]
          ]
      , control st spec
      , HH.div [ HP.class_ (HH.ClassName "label") ]
          [ HH.span [ HP.class_ (HH.ClassName "label-text-alt text-xs opacity-70") ] [ HH.text spec.hint ] ]
      ]

  control st spec = case spec.kind of
    Text ->
      HH.input
        [ HP.type_ HP.InputText
        , HP.class_ (HH.ClassName "input input-bordered input-sm w-full")
        , HP.value (valueOf st spec)
        , HE.onValueInput (SetField spec.key)
        ]
    LongText ->
      HH.textarea
        [ HP.class_ (HH.ClassName "textarea textarea-bordered textarea-sm w-full")
        , HP.value (valueOf st spec)
        , HE.onValueInput (SetField spec.key)
        ]
    Select opts ->
      HH.select
        [ HP.class_ (HH.ClassName "select select-bordered select-sm w-full")
        , HE.onValueChange (SetField spec.key)
        ]
        ( [ HH.option [ HP.value "" ] [ HH.text "—" ] ]
            <> map (\o -> HH.option [ HP.value o, HP.selected (valueOf st spec == o) ] [ HH.text o ]) opts
        )

  valueOf st spec = fromMaybe "" (Map.lookup spec.key st.values)

  -- Mint-ul e faptul central al fiecărui flux de aici: profilul, atestarea și disputa sunt toate
  -- token-uri. „Creates 1 token" cu numele lui spune mai mult decât orice altceva din sumar.
  mintLine m =
    HH.li_
      [ HH.text
          ( (if m.quantity == "1" then "Creates one token, " else "Creates " <> m.quantity <> " of token ")
              <> assetLabel m.assetName
              <> " under policy "
              <> shortId m.policy
              <> "."
          )
      ]

  outputLine o =
    HH.li_
      [ HH.text
          ( "Sends " <> formatAda o.lovelace <> " to " <> shortId o.address
              <> (if o.otherAssets > 0 then ", with " <> pluralize o.otherAssets "token" else "")
              <> "."
          )
      ]

  certLine n =
    if n == 0 then []
    else [ HH.li_ [ HH.text (pluralize n "certificate" <> " included.") ] ]

  signerLine n =
    if n == 0 then []
    else
      [ HH.li_
          [ HH.text
              (pluralize n "signature" <> " required beyond the inputs — this is what proves the credential is yours.")
          ]
      ]

  -- Numele activului vine în hex. Scurtat, nu decodat: un `assetName` nu e garantat text, iar o
  -- decodare care reușește uneori ar face ca uneori să arate ca text și uneori ca hex.
  assetLabel n = if String.length n > 16 then String.take 16 n <> "…" else n

  -- Ce s-a întîmplat, în cuvinte care spun și ce NU s-a întîmplat.
  stepNote st = case st.step of
    Idle -> HH.text ""
    Connecting -> HH.text ""
    Building -> HH.text ""
    Failed e ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-error text-sm") ]
        [ HH.span_ [ HH.text e ] ]
    -- R8: ce se arată aici e ce FACE tranzacția, citit din ea. Ecoul câmpurilor din formular nu
    -- ajunge — ar dovedi ce s-a cerut, nu ce s-a construit — iar CBOR-ul brut nu e un sumar, e
    -- exact blind-signing-ul pe care check 14 îl interzice.
    Built tx -> case summarise tx of
      Nothing ->
        -- O tranzacție pe care n-o putem citi NU se oferă la semnat. Asta e singurul răspuns
        -- consecvent cu regula: dacă nu putem spune ce face, nu putem cere o semnătură pentru ea.
        HH.div [ HP.class_ (HH.ClassName "alert alert-error text-sm") ]
          [ HH.span_
              [ HH.text
                  "The server returned a transaction this app could not decode, so it will not be \
                  \offered for signing. Nothing has happened on chain."
              ]
          ]
      Just sum -> summaryCard st tx sum
    Signing _ ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-info text-sm") ]
        [ HH.span_ [ HH.text "Waiting for your wallet. Nothing has been submitted yet." ] ]
    Submitting ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-info text-sm") ]
        [ HH.span_ [ HH.text "Signed. Submitting…" ] ]
    Submitted txId -> submittedCard txId false
    Confirmed txId -> submittedCard txId true

  -- Trimis, și apoi confirmat. Cele două sunt stări DIFERITE: „trimis" înseamnă că nodul a primit
  -- tranzacția, „confirmat" că e într-un bloc. Un singur mesaj pentru amândouă ar face pe cineva să
  -- creadă că s-a terminat când încă se poate pierde în mempool.
  submittedCard txId confirmed =
    HH.div [ HP.class_ (HH.ClassName ("alert text-sm flex-col items-start gap-2 " <> if confirmed then "alert-success" else "alert-info")) ]
      [ HH.span_
          [ HH.text
              ( if confirmed then "Confirmed on chain. The register will show it once the indexer catches up."
                else "Submitted. The node has it; it is not in a block yet."
              )
          ]
      , HH.code [ HP.class_ (HH.ClassName "font-mono text-xs break-all opacity-80") ] [ HH.text txId ]
      ]

  summaryCard st tx sum =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-3") ]
          [ HH.h3 [ HP.class_ (HH.ClassName "card-title text-base") ]
              [ HH.text "What this transaction does" ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
              [ HH.text
                  "Read out of the transaction itself, not out of the form you filled in. \
                  \Nothing has been signed or submitted yet."
              ]
          , HH.ul [ HP.class_ (HH.ClassName "text-sm space-y-1 list-disc ml-5") ]
              ( [ HH.li_ [ HH.text ("Pays a network fee of " <> formatAda sum.fee <> ".") ] ]
                  <> map mintLine sum.mints
                  <> map outputLine sum.outputs
                  <> certLine sum.certificates
                  <> signerLine sum.requiredSigners
              )
          , HH.details_
              [ HH.summary [ HP.class_ (HH.ClassName "text-xs opacity-70 cursor-pointer") ]
                  [ HH.text "Show the raw transaction" ]
              , HH.pre [ HP.class_ (HH.ClassName "bg-base-300 rounded p-2 overflow-x-auto text-xs mt-2") ]
                  [ HH.code_ [ HH.text tx ] ]
              ]
          -- Butonul stă SUB sumar, nu lângă „Build": semnătura se cere după ce ai citit ce
          -- semnezi, iar ordinea pe ecran e ordinea în care se face.
          , HH.div [ HP.class_ (HH.ClassName "card-actions") ]
              [ HH.button
                  [ HP.class_ (HH.ClassName "btn btn-primary btn-sm")
                  , HP.type_ HP.ButtonButton
                  , HE.onClick (const (SignAndSubmit tx))
                  ]
                  [ HH.text "Sign and submit" ]
              ]
          ]
      ]

derive instance Eq Step

-- | Cheia în care intră identificatorul venit din URL, per flux. Un link „contestă atestarea
-- | asta" trebuie să pună identificatorul în cîmpul potrivit, nu în primul.
subjectKeysFor :: String -> Array String
subjectKeysFor = case _ of
  "accept-attestation" -> [ "attestation_id" ]
  "open-dispute" -> [ "attestation_id" ]
  "resolve-dispute" -> [ "dispute_id" ]
  "expire-dispute" -> [ "dispute_id" ]
  "update-profile" -> [ "profile_id" ]
  "claim-credential" -> [ "profile_id" ]
  "withdraw-credential" -> [ "profile_id" ]
  "issue-attestation" -> [ "subject_profile_id" ]
  _ -> []

-- | Adresele pe care serverul le folosește ca să aleagă intrările și să dea restul.
-- |
-- | `Nothing` cînd wallet-ul nu dă o adresă de rest — fără ea nu se poate construi, iar un
-- | `changeAddress` gol trimis la server ar produce o eroare de validare care arată ca o greșeală
-- | a utilizatorului.
-- |
-- | Adresele FOLOSITE pot fi legitim zero, pe un portofel nou: serverul are nevoie de cel puțin
-- | una ca să caute intrări, iar adresa de rest e și ea una a portofelului, deci intră în listă
-- | cînd altceva nu există.
walletAddresses :: Api -> Aff (Maybe UserAddresses)
walletAddresses api = do
  change <- attempt (getChangeAddress api)
  used <- attempt (getUsedAddresses api Nothing)
  case change of
    Left _ -> pure Nothing
    Right changeAddress ->
      pure
        ( Just
            { changeAddress
            , usedAddresses: case used of
                Right us | not (null us) -> us
                _ -> [ changeAddress ]
            }
        )
