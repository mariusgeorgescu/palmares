-- | Fișa de încorporat: `/embed?drep=…`, desenată pentru un `iframe` de pe alt site.
-- |
-- | Ca `iframe` și NU ca `<script>`, și asta nu e o preferință: serverul nostru rulează cu o
-- | allowlist de origini fail-closed, deci un script încărcat de pe alt site n-ar putea citi
-- | niciun răspuns al API-ului. Un `iframe` cere pagina de la NOI, iar cererile ei sunt
-- | same-origin ca oricare alta. (Funcționează pentru că BFF-ul nu trimite `X-Frame-Options`; dacă
-- | cineva îl adaugă vreodată, widgetul moare în tăcere pe toate site-urile care-l au pus.)
-- |
-- | Ecranul n-are bară de navigare, n-are bandă de prospețime și n-are subsol: ce se încorporează
-- | pe site-ul altcuiva trebuie să fie fapta, nu produsul nostru în miniatură. Singurul link duce
-- | la pagina întreagă, și se deschide în fereastra de sus.
module Components.Embed
  ( Slot
  , Output
  , _embed
  , component
  , embedSnippet
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getDRepDetail)
import Capabilities.Query.Gov.Types (DRepDetail(..), DRepMetrics(..), DRepSummary(..))
import Components.Shared.DRepIdentity (shortId)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Format (formatAda, formatPercent, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Route.GovQueries (EmbedFilters, drepDetailHrefFor)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_embed :: Proxy "embed"
_embed = Proxy

type Input = EmbedFilters

type State =
  { filters :: EmbedFilters
  , detail :: RemoteData ApiError DRepDetail
  }

data Action
  = Initialize
  | Receive Input

-- | Fragmentul pe care îl copiază cineva ca să pună fișa pe site-ul lui.
-- |
-- | `title` e obligatoriu pentru cititoarele de ecran — un `iframe` fără nume se anunță ca „frame",
-- | ceea ce nu spune nimic — iar `loading="lazy"` înseamnă că o pagină cu zece fișe nu face zece
-- | cereri înainte să se vadă ceva.
embedSnippet :: String -> String -> String
embedSnippet origin drepId =
  "<iframe src=\"" <> origin <> "/embed?drep=" <> drepId <> "\" "
    <> "title=\"Palmares governance record\" "
    <> "width=\"380\" height=\"220\" loading=\"lazy\" "
    <> "style=\"border:0\"></iframe>"

component
  :: forall q m
   . MonadQueryGov m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, detail: NotAsked }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  handleAction = case _ of
    Initialize -> load
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters }
        load

  load = do
    st <- H.get
    case st.filters.drep of
      Nothing -> H.modify_ _ { detail = NotAsked }
      Just drepId -> do
        H.modify_ _ { detail = Loading }
        res <- getDRepDetail drepId
        H.modify_ _
          { detail = case res of
              Left e -> Failure e
              Right d -> Success d
          }

  render st =
    HH.div [ HP.class_ (HH.ClassName "p-3 bg-base-100 text-base-content") ]
      [ case st.filters.drep of
          Nothing -> message "No representative was named in the embed URL."
          Just _ -> case st.detail of
            NotAsked -> message "…"
            Loading -> message "Loading…"
            Failure e -> message (renderApiError e)
            Success d -> card d
      ]

  message t =
    HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ] [ HH.text t ]

  card (DRepDetail d) =
    let
      DRepSummary s = d.drep
      DRepMetrics m = d.metrics
    in
      HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
        [ HH.div_
            [ HH.div [ HP.class_ (HH.ClassName "font-semibold leading-tight") ]
                [ HH.text (fromMaybe "Unnamed DRep" s.givenName) ]
            -- Identificatorul stă lângă nume și aici: fișa e o afirmație despre cineva anume, iar
            -- pe site-ul altcuiva nu există nimic altceva care să spună despre cine e vorba.
            , HH.div [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70"), HP.title s.id ]
                [ HH.text (shortId s.id) ]
            ]
        , HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-x-5 gap-y-1 text-sm") ]
            [ figure "Voting power" (formatAda s.votingPower)
            , figure "Participation" (formatPercent m.participationRate)
            , figure "Rationales" (formatPercent m.rationaleRate)
            ]
        , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text (pluralize m.votesCast "vote" <> " of " <> show m.eligibleActions <> " eligible · as of epoch " <> show m.asOfEpoch) ]
        -- `target="_top"`: fără el, clicul deschide Palmares ÎN cadrul de 380px de pe site-ul
        -- gazdă, care e cea mai proastă pagină de pornire posibilă.
        , HH.a
            [ HP.href (drepDetailHrefFor s.id)
            , HP.target "_top"
            , HP.class_ (HH.ClassName "link link-hover text-xs")
            ]
            [ HH.text "See the full record on Palmares →" ]
        ]

  figure label value =
    HH.div_
      [ HH.div [ HP.class_ (HH.ClassName "text-[10px] uppercase tracking-wide opacity-70") ] [ HH.text label ]
      , HH.div [ HP.class_ (HH.ClassName "font-semibold") ] [ HH.text value ]
      ]
