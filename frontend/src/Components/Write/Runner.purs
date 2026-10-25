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
import Capabilities.Interaction.MonadInteract (class MonadInteract, buildFlow, interactionStatus)
import Capabilities.Query.Gov.Http (renderApiError)
import Capabilities.Wallet.Governance (class MonadGovWallet, GateVerdict(..), blockMessage, connectGovernance, hasExtension)
import Capabilities.Interaction.Types (InteractionStatus(..), OracleGate(..), OracleParams(..), oracleGate)
import Components.Write.Flows (FieldKind(..), buildRequest, flowSpecs, missingFields, specFor)
import Format (formatAda)
import Control.Monad.Reader (class MonadAsk)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Data.Tuple (Tuple(..))
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
  | Failed String

type State =
  { filters :: WriteFilters
  , values :: Map String String
  , gate :: Maybe GateVerdict
  -- Starea protocolului, citită o dată la intrarea pe ecran. `Nothing` cît timp n-a răspuns.
  , oracle :: Maybe InteractionStatus
  , step :: Step
  }

data Action
  = Initialize
  | Receive Input
  | Connect
  | SetField String String
  | Submit

component
  :: forall q m
   . MonadInteract m
  => MonadGovWallet m
  => MonadAsk Env m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, values: seedFrom filters, gate: Nothing, oracle: Nothing, step: Idle }
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
      res <- interactionStatus
      H.modify_ _
        { oracle = case res of
            Left _ -> Nothing
            Right st -> Just st
        }
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters, values = seedFrom filters, step = Idle }
    Connect -> do
      H.modify_ _ { step = Connecting }
      verdict <- connectGovernance "lace"
      H.modify_ _ { gate = Just verdict, step = Idle }
    SetField k v -> H.modify_ \st -> st { values = Map.insert k v st.values }
    Submit -> do
      st <- H.get
      case st.gate of
        Just (Allowed _) -> runBuild st
        _ -> pure unit

  -- Se construiește cu adresele wallet-ului. Nu se semnează aici: semnătura e a wallet-ului, iar
  -- trimiterea e pasul pe care produsul îl ține deliberat separat.
  runBuild st = case st.filters.flow of
    Nothing -> pure unit
    Just flowId -> do
      H.modify_ _ { step = Building }
      -- Adresele vin din wallet la pasul următor; aici se trimit cele pe care le-a dat poarta.
      case buildRequest flowId st.values emptyAddresses of
        Nothing -> H.modify_ _ { step = Failed "Some required fields are still empty." }
        Just req -> do
          res <- buildFlow req
          H.modify_ _
            { step = case res of
                Left e -> Failed (renderApiError e)
                Right tx -> Built tx
            }

  emptyAddresses = { usedAddresses: [], changeAddress: "" }

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
            , HH.button
                [ HP.class_ (HH.ClassName "btn btn-sm btn-primary")
                , HP.type_ HP.ButtonButton
                , HE.onClick (const Connect)
                ]
                [ HH.text (if st.step == Connecting then "Connecting…" else "Connect wallet") ]
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
            ]
        ]

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
          , case protocolGate st, st.gate of
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

  -- Ce s-a întîmplat, în cuvinte care spun și ce NU s-a întîmplat.
  stepNote st = case st.step of
    Idle -> HH.text ""
    Connecting -> HH.text ""
    Building -> HH.text ""
    Failed e ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-error text-sm") ]
        [ HH.span_ [ HH.text e ] ]
    Built tx ->
      HH.div [ HP.class_ (HH.ClassName "alert alert-info text-sm flex-col items-start gap-2") ]
        [ HH.span_
            [ HH.text
                "Built. Nothing has been signed or submitted — this is the unsigned transaction, \
                \and the next step is your wallet."
            ]
        , HH.code [ HP.class_ (HH.ClassName "font-mono text-xs break-all opacity-80") ]
            [ HH.text (String.take 120 tx <> if String.length tx > 120 then "…" else "") ]
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
