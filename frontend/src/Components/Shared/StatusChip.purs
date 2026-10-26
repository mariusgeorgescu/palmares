-- | Chip-ul global de prospețime: pe fiecare ecran, un singur apel, fără al doilea.
-- |
-- | Trei lucruri pe care le face **intenționat** altfel decât ar fi comod:
-- |
-- |   * nu arată niciodată verde când nu știe. `Unknown` e o a patra stare, nu o degradare la
-- |     „probabil e bine" — un produs al cărui diferențiator e aritmetica verificabilă nu are voie
-- |     să mintă despre cât de veche e aritmetica;
-- |   * ia pragurile din răspuns (`amber_lag_seconds`, `ready_max_lag_seconds`), nu din cod, ca să
-- |     nu se dezacordeze de la probe-ul care decide dacă `/ready` e verde;
-- |   * etichetează cifrele de putere cu `drep_distr_epoch`, nu cu epoca curentă, pentru că ledgerul
-- |     scrie distribuția de stake cu o epocă în urmă față de tip.
module Components.Shared.StatusChip
  ( Slot
  , Output
  , _statusChip
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError(..), renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getStatus)
import Capabilities.Query.Gov.Types (AttestSync(..), ChipState(..), GovStatus(..), GovSync(..), chipStateFor)
import Format (formatLag)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_statusChip :: Proxy "statusChip"
_statusChip = Proxy

type State = { status :: RemoteData ApiError GovStatus }

data Action = Initialize

component
  :: forall q i m
   . MonadQueryGov m
  => H.Component q i Output m
component =
  H.mkComponent
    { initialState: const { status: NotAsked }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }
  where
  handleAction = case _ of
    -- Banda de stare e PRIMUL lucru de pe fiecare ecran și stă în afara slotului de rută, deci
    -- cererea ei ar ține în loc inițializarea întregii aplicații — inclusiv titlul documentului.
    Initialize -> void (H.fork load)

  load = do
    H.modify_ _ { status = Loading }
    res <- getStatus
    H.modify_ _
      { status = case res of
          Left e -> Failure e
          Right s -> Success s
      }

  render st = case st.status of
    NotAsked -> badge Unknown "status unknown"
    Loading -> badge Unknown "checking data freshness…"
    -- Pastila rămâne scurtă și de lungime fixă; mesajul serverului (de lungime necontrolată) merge
    -- lângă ea, unde poate să se rupă pe rânduri fără să deformeze banda. Ambar, nu gri: „nu știu
    -- cât de vechi sunt datele" e un avertisment, nu o informație neutră.
    Failure e ->
      HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-center gap-2 text-xs") ]
        [ badge Amber "freshness unknown"
        , HH.span [ HP.class_ (HH.ClassName "opacity-70"), HP.title (renderApiError e) ]
            [ HH.text (failureLabel e) ]
        ]
    Success s -> renderStatus s

  -- Banda spune ce e NOU, nu tot ce știe. Când metricile și distribuția de stake sunt din epoca
  -- curentă — cazul obișnuit — a le scrie oricum înseamnă același număr de trei ori pe fiecare
  -- ecran, iar repetiția face banda să cântărească mai mult decât titlul paginii de sub ea. Când
  -- diferă, însă, diferența e exact faptul important, și atunci se scrie.
  renderStatus s@(GovStatus st) =
    let
      GovSync gov = st.governance
    in
      HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-center gap-x-3 gap-y-1 text-xs") ]
        [ HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ] [ HH.text st.network ]
        , badge (chipStateFor s) (formatLag gov.lagSeconds)
        , HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
            [ HH.text ("epoch " <> show gov.epoch) ]
        -- Amindouă epocile lipsesc pe o bază de date care n-a produs încă metrici sau distribuție
        -- de putere. Atunci nu se scrie nimic: „as of epoch ?" nu e o informație, iar banda spune
        -- oricum, prin pastila ei, cît de veche e imaginea.
        , offEpochNote "metrics as of epoch " gov.epoch st.metricsAsOfEpoch
        , offEpochNote "voting power as of epoch " gov.epoch st.drepDistrEpoch
        , renderAttestation st.attestation
        ]

  -- Absent nu e „zero" și nu e o eroare: un deploy doar-guvernanță nu are proiector de atestări, și
  -- asta e o configurație validă pe care ecranul trebuie să o numească.
  renderAttestation = case _ of
    Nothing ->
      HH.span [ HP.class_ (HH.ClassName "opacity-70") ]
        [ HH.text "vouches: not deployed" ]
    Just (AttestSync a) ->
      HH.span [ HP.class_ (HH.ClassName "opacity-70 inline-flex items-center gap-1.5") ]
        -- Punctul pulsând, din `bjj-frontend`, dar DOAR cînd proiectorul chiar ține pasul. Un
        -- indicator „live" care pulsează peste un proiector rămas în urmă ar fi exact minciuna pe
        -- care banda asta există s-o prevină — de aceea e legat de stare și de decalaj, nu pus
        -- necondiționat.
        [ if a.state == "following" && a.lagSeconds <= 60 then
            HH.span [ HP.class_ (HH.ClassName "feed-live-dot") ] []
          else HH.text ""
        , HH.text ("vouches: " <> a.state <> " (" <> show a.lagSeconds <> "s behind)")
        ]

  -- Banda spune ce e NOU: o epocă egală cu cea a lanțului e același număr scris a doua oară, iar
  -- una care lipsește n-are ce să spună.
  offEpochNote label chainEpoch = case _ of
    Just e | e /= chainEpoch ->
      HH.span [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text (label <> show e) ]
    _ -> HH.text ""

  -- „Nu a răspuns" e fals când serverul a răspuns exact: `indexer_behind` e un 503 pe care
  -- query-api îl dă deliberat cât timp db-sync încă reface istoria și nu există încă parametri de
  -- guvernanță împotriva cărora o numărătoare s-ar putea verifica. Pe un deploy nou asta e starea
  -- pe care o vede fiecare vizitator timp de câteva ore, deci merită propoziția ei.
  failureLabel = case _ of
    Api { code: "indexer_behind" } -> "the index is still catching up"
    _ -> "the status service did not answer"

  badge state label =
    HH.span
      [ HP.class_ (HH.ClassName ("badge badge-sm " <> badgeClass state)) ]
      [ HH.text label ]

  badgeClass = case _ of
    Green -> "badge-success"
    Amber -> "badge-warning"
    Red -> "badge-error"
    -- NU `badge-ghost`: are fundalul lui `base-200`, adică exact culoarea cardului în care stă,
    -- deci starea pe care n-o cunoaștem ar fi singura care nu se vede.
    Unknown -> "badge-outline"
