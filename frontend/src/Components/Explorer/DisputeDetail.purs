-- | Pagina unei singure provocari: `GET /disputes/{id}`.
-- |
-- | Ruta intoarce chiar forma `DisputeRow`, deci ecranul nu cere niciun tip nou. §5.5 din harta
-- | API->ecran o cerea exact asa: „a linkable, refreshable dispute detail page — the target of a
-- | notification or a shared URL".
-- |
-- | Ce face in plus fata de rindul din lista: tinta si deschizatorul devin LINKURI, iar verdictul
-- | e explicat. Al treilea lucru conteaza cel mai mult: „expired" NU e o constatare impotriva
-- | nimanui — inseamna ca nimeni nu a decis la timp — iar o insigna singura nu poate spune asta.
module Components.Explorer.DisputeDetail
  ( Slot
  , Output
  , _disputeDetail
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov
  ( class MonadQueryGov
  , getAttestation
  , getDispute
  , getProfile
  )
import Capabilities.Query.Gov.Types
  ( AttestationDetail(..)
  , AttestationRow(..)
  , DisputeRow(..)
  , ProfileRow(..)
  )
import Components.Explorer.DisputeList (verdictClass)
import Components.Shared.DRepIdentity (shortId)
import Data.Const (Const)
import Data.Either (Either(..), either)
import Data.Maybe (Maybe(..), fromMaybe)
import Format (formatAda, formatDay)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Route (Route)
import Route.GovQueries (attestationDetailHrefFor, profileDetailHrefFor, writeHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_disputeDetail :: Proxy "disputeDetail"
_disputeDetail = Proxy

type Input = String

type State =
  { disputeId :: String
  , dispute :: RemoteData ApiError DisputeRow
  , targetName :: Maybe String
  , openerName :: Maybe String
  }

data Action
  = Initialize
  | Retry
  | Receive Input

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \disputeId ->
        { disputeId, dispute: NotAsked, targetName: Nothing, openerName: Nothing }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  handleAction = case _ of
    Initialize -> void (H.fork load)
    Retry -> load
    Receive did -> do
      st <- H.get
      when (did /= st.disputeId) do
        H.modify_ _ { disputeId = did }
        load

  load = do
    st <- H.get
    H.modify_ _ { dispute = Loading, targetName = Nothing, openerName = Nothing }
    res <- getDispute st.disputeId
    H.modify_ _ { dispute = either Failure Success res }
    -- Ecranul scrie DOUĂ nume, deci cere două obiecte, nu două registre. Varianta de dinainte
    -- descărca două sute de atestări ȘI două sute de profiluri pentru atît, iar peste două sute un
    -- nume redevenea TĂCUT un id.
    --
    -- Regula veche se păstrează: eșecul unui nume nu strică ecranul — fără el se arată
    -- identificatorul scurtat, care e oricum lucrul verificabil pe lanț. Cererile vin DUPĂ ce
    -- provocarea e în stare, deci conținutul principal e randat înainte de ele.
    case res of
      Left _ -> pure unit
      Right (DisputeRow d) -> do
        target <- getAttestation d.target
        H.modify_ _ { targetName = vouchName target }
        opener <- getProfile d.openedBy
        H.modify_ _ { openerName = profileName opener }

  -- `getAttestation` întoarce atestarea ÎMPREUNĂ cu disputele ei; de aici se ia numai numele, ca
  -- să nu apară o capabilitate nouă pentru un singur șir.
  vouchName = case _ of
    Left _ -> Nothing
    Right (AttestationDetail ad) -> case ad.attestation of
      AttestationRow a -> Just a.name

  profileName = case _ of
    Left _ -> Nothing
    Right (ProfileRow r) -> Just r.name

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
      [ case st.dispute of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success d -> body st d
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading the challenge…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The challenge could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st (DisputeRow d) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text d.name ]
          , HH.span [ HP.class_ (HH.ClassName ("badge " <> verdictClass d.verdict)) ]
              [ HH.text (fromMaybe "still open" d.verdict) ]
          ]
      , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ] [ HH.text d.description ]
      , verdictMeaning d
      , HH.dl [ HP.class_ (HH.ClassName "grid gap-x-6 gap-y-1 sm:grid-cols-2 text-sm pt-1") ]
          [ HH.div_
              [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Against the vouch" ]
              , HH.dd_
                  [ HH.a
                      [ HP.href (attestationDetailHrefFor d.target)
                      , HP.class_ (HH.ClassName "link link-hover")
                      ]
                      [ HH.text (fromMaybe (shortId d.target) st.targetName) ]
                  ]
              ]
          , HH.div_
              [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Opened by" ]
              , HH.dd_
                  [ HH.a
                      [ HP.href (profileDetailHrefFor d.openedBy)
                      , HP.class_ (HH.ClassName "link link-hover")
                      ]
                      [ HH.text (fromMaybe (shortId d.openedBy) st.openerName) ]
                  ]
              ]
          , HH.div_
              -- „At stake" promitea o pierdere posibilă; nu există una. Eticheta e aceeași cu
              -- coloana din listă, iar ce se întîmplă cu el o spune `verdictMeaning`.
              [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Deposit" ]
              , HH.dd [ HP.class_ (HH.ClassName "font-mono") ] [ HH.text (formatAda d.deposit) ]
              ]
          , HH.div_
              [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Opened" ]
              , HH.dd_ [ HH.text (formatDay d.openedAt) ]
              ]
          , HH.div_
              [ HH.dt [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "Stale after" ]
              , HH.dd_ [ HH.text (formatDay d.staleAfter) ]
              ]
          ]
      , case d.verdict of
          Nothing ->
            HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-3 pt-1") ]
              [ HH.a
                  [ HP.href (writeHrefFor { flow: Just "resolve-dispute", subject: Just d.id })
                  , HP.class_ (HH.ClassName "btn btn-sm")
                  ]
                  [ HH.text "Resolve" ]
              , HH.a
                  [ HP.href (writeHrefFor { flow: Just "expire-dispute", subject: Just d.id })
                  , HP.class_ (HH.ClassName "link link-hover text-sm self-center")
                  ]
                  [ HH.text "Expire" ]
              ]
          Just _ -> HH.text ""
      ]

  -- O insignă nu poate spune ce înseamnă un verdict, iar al treilea e cel care se interpretează
  -- cel mai des greșit: o expirare NU e o constatare împotriva nimănui. Nimeni nu a decis nimic —
  -- scris aici fiindcă registrul nu dă scoruri și nu lasă pe altcineva să deducă.
  --
  -- Depozitul se întoarce pe TOATE cele trei verdicte: cererea validatorului stă în definiția
  -- comună a închiderii, nu pe o ramură, deci niciun verdict nu îl confiscă. Textul de aici nu are
  -- voie să sugereze altceva, fiindcă ar descuraja contestarea cu o pierdere care nu există.
  verdictMeaning d = case d.verdict of
    Nothing ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        [ HH.text
            ( "Nobody has decided this yet. After " <> formatDay d.staleAfter
                <>
                  ", anyone may close it as expired — the deadline was fixed when the challenge was \
                  \opened and is recorded in its own datum."
            )
        ]
    Just "upheld" ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        [ HH.text "Upheld: the vouch did not survive the objection, and the deposit goes back to whoever opened it." ]
    Just "rejected" ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        [ HH.text
            "Rejected: the claim stands, and the deposit went back to whoever opened the challenge \
            \— as it does on every outcome. Contesting costs network fees and nothing else."
        ]
    Just "expired" ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
        [ HH.text
            "Expired: nobody decided it in time, so anyone was allowed to close it and the deposit \
            \was returned. This is not a finding against anyone — it says only that the clock ran out."
        ]
    Just other ->
      HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text ("Verdict: " <> other <> ".") ]
