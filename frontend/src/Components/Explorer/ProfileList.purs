-- | Registrul de profiluri: `GET /profiles`.
-- |
-- | Un profil e un TOKEN, nu un rînd într-o bază: `id` e o clasă de activ (`policy.assetName`), și
-- | cine deține tokenul deține profilul. De-aia ecranul arată identificatorul întreg și nu-l
-- | ascunde într-un link — e lucrul pe care îl verifici pe lanț.
-- |
-- | `credential` leagă profilul de o identitate de guvernanță și lipsește la jumătate din
-- | profilurile măsurate. Asta nu e un profil incomplet: e un profil care nu pretinde nimic
-- | despre cine e pe lanț, ceea ce e o stare validă și e scrisă ca atare.
module Components.Explorer.ProfileList
  ( Slot
  , Output
  , _profileList
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getProfiles)
import Capabilities.Query.Gov.Types (ProfilePage(..), ProfileRow(..))
import Components.Shared.DRepIdentity (shortId)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), isJust, maybe)
import Data.String (Pattern(..), stripPrefix)
import Format (enumLabel, formatInt, humanize, matchLine, pluralize)
import Halogen as H
import AppEnv as AppEnv
import Components.Shared.OnchainId as OnchainId
import Components.Shared.Pager as Pager
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries
  ( RegistryFilters
  , drepDetailHrefFor
  , profileDetailHrefFor
  , profileListHrefFor
  , writeHrefFor
  )
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_profileList :: Proxy "profileList"
_profileList = Proxy

type Input = RegistryFilters

type State =
  { filters :: RegistryFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError ProfilePage
  }

data Action
  = Initialize
  | Retry
  | Receive Input

-- | Dacă credențiala e a unui DRep, citit din prefixul CIP-129.
-- |
-- | Rolul e în prefix: `drep1…` pentru un DRep, `cc_cold1…`/`cc_hot1…` pentru o cheie de comitet,
-- | revendicabilă de la ADR 0006. `drepDetailHrefFor` e o simplă concatenare, deci fără verificarea
-- | asta o cheie de comitet ajungea la `/dreps/cc_cold1…` — pagina de DRep a ceva care nu e DRep.
-- | Patru linii duplicate și în `ProfileDetail`: un modul nou pentru un `stripPrefix` ar fi o
-- | abstracție înaintea celui de-al treilea apelant.
isDRepCredential :: String -> Boolean
isDRepCredential c = isJust (stripPrefix (Pattern "drep1") c)

component
  :: forall q m
   . MonadQueryGov m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, page: NotAsked, refreshing: false }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  handleAction = case _ of
    -- `H.fork`, nu `load` direct: initializatorul unui copil ține deschisă inițializarea
    -- PĂRINTELUI, iar părintele e cel care pune titlul documentului. Măsurat pe deploy:
    -- `/activity` răspunde în 12 secunde pe baza vie, iar tab-ul scria titlul generic tot timpul
    -- ăla. Un ecran lent nu are voie să țină în loc cadrul aplicației.
    Initialize -> void (H.fork load)
    Retry -> load
    Receive filters -> do
      st <- H.get
      when (filters /= st.filters) do
        H.modify_ _ { filters = filters }
        load

  load = do
    st <- H.get
    H.modify_ \s0 -> case s0.page of
      Success _ -> s0 { refreshing = true }
      _ -> s0 { page = Loading }
    res <- getProfiles st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Profiles" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  "Identities in the register. A profile is a token: whoever holds it holds the \
                  \profile. A profile may also prove control of a governance credential — that is the \
                  \part that can be checked."
              ]
          , HH.a
              [ HP.href (writeHrefFor { flow: Just "claim-profile", subject: Nothing })
              , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
              ]
              [ HH.text "Claim a profile" ]
          ]
      , case st.page of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success p -> body st p
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading profiles…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The profiles could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(ProfilePage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "profile")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState else cards p.items
      , if null p.items then HH.text "" else pager st page
      ]

  emptyState =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.p_ [ HH.text "No profiles have been registered yet." ] ]
      ]

  -- Carduri, nu tabel: descrierea e text liber de lungime necontrolată, iar într-o coloană ar
  -- împinge totul la dreapta sau s-ar tăia exact unde începe informația.
  cards items =
    HH.div [ HP.class_ (HH.ClassName "grid gap-3 md:grid-cols-2") ] (map card items)

  card (ProfileRow r) =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
          [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline gap-2") ]
              -- Numele duce la pagina profilului. Pina acum cardul nu ducea nicaieri: ca sa afli
              -- ce s-a afirmat despre cineva trebuia sa copiezi un id de saizeci de caractere din
              -- chip si sa filtrezi de mina.
              [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-base") ]
                  [ HH.a
                      [ HP.href (profileDetailHrefFor r.id)
                      , HP.class_ (HH.ClassName "link link-hover")
                      ]
                      [ HH.text r.name ]
                  ]
              , HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-outline") ] [ HH.text (enumLabel r.kind) ]
              ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-80") ] [ HH.text r.description ]
          -- Scurtat pe card, întreg în chip. Înainte, cardul randa id-ul INTEGRAL cu un `title`
          -- redundant, iar la douăzeci și șapte de linii mai jos credențiala era scurtată FĂRĂ
          -- `title`, deci inaccesibilă — două decizii contradictorii pe același card. Acum e o
          -- singură regulă, aceeași peste tot.
          --
          -- Prima variantă a păstrat id-ul integral lîngă chip și a RUPT R2: testul „/profiles does
          -- not scroll sideways" la 390px a căzut imediat. Șaizeci și patru de caractere monospațiate
          -- plus un buton nu încap pe un telefon, iar `truncate` într-un `inline-flex` nu le
          -- strînge. De aceea panoul de hover există: ca lista să nu plătească pentru valoarea
          -- întreagă.
          , HH.div [ HP.class_ (HH.ClassName "opacity-70") ]
              [ OnchainId.withChip
                  { value: r.id
                  , shown: shortId r.id
                  , kind: OnchainId.Asset
                  , explorerBase: AppEnv.explorerBase
                  }
              ]
          , credentialLine r
          , HH.div [ HP.class_ (HH.ClassName "card-actions") ]
              [ HH.a
                  [ HP.href (writeHrefFor { flow: Just "update-profile", subject: Just r.id })
                  , HP.class_ (HH.ClassName "link link-hover text-xs")
                  ]
                  [ HH.text "Edit" ]
              , HH.a
                  [ HP.href (writeHrefFor { flow: Just "claim-credential", subject: Just r.id })
                  , HP.class_ (HH.ClassName "link link-hover text-xs")
                  ]
                  [ HH.text "Claim a credential" ]
              ]
          ]
      ]

  -- Un profil fără credențial nu e incomplet, și propoziția o spune. Cînd există, duce la pagina
  -- DRep-ului — dar DOAR dacă e un DRep: vezi `isDRepCredential`. Și cînd serverul nu spune ce fel
  -- de credențial e, cardul nu mai ghicește „cheie": o afirmație despre dovadă e exact ce n-ai
  -- voie să deduci dintr-un cîmp lipsă.
  credentialLine r = case r.credential of
    Nothing ->
      HH.p [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
        [ HH.text "Claims no on-chain governance credential." ]
    Just c ->
      HH.p [ HP.class_ (HH.ClassName "text-xs") ]
        ( [ HH.text "Claims " ]
            <> credentialIdent c
            <>
              [ HH.text
                  ( case r.credentialIsScript of
                      Just true -> " (a script credential)"
                      Just false -> " (a key credential)"
                      Nothing -> ""
                  )
              , HH.text (maybe "" (\n -> " · " <> pluralize n "claimant") r.claimantCount)
              ]
        )

  -- Credențiala era scurtată fără nicio cale către valoarea întreagă. Chipul stă lîngă link, nu în
  -- locul lui: linkul duce în registru, chipul duce pe lanț. Pentru o cheie de comitet nu există
  -- niciunul din cele două: registrul n-are pagină de membru de comitet, iar `IdKind` n-are valoare
  -- de comitet — `DRep` ar duce explorerul la `/drep/cc_cold1…`, tot o pagină greșită.
  credentialIdent c =
    if isDRepCredential c then
      [ HH.a [ HP.href (drepDetailHrefFor c), HP.class_ (HH.ClassName "link link-hover font-mono") ]
          [ HH.text (shortId c) ]
      , OnchainId.chip { value: c, kind: OnchainId.DRep, explorerBase: AppEnv.explorerBase }
      ]
    else [ HH.span [ HP.class_ (HH.ClassName "font-mono") ] [ HH.text (shortId c) ] ]

  pager st (ProfilePage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = profileListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      Pager.render
        { total: p.total
        , offset: p.offset
        , shown: length p.items
        , ceiling: offsetCeiling
        , prev
        , next
        , hrefFor
        , noun: "profile"
        }

