-- | Atestările: `GET /attestations`.
-- |
-- | O atestare e o afirmație a cuiva (`issuer`) despre altcineva (`subject`). Ecranul ține trei
-- | stări SEPARATE, pentru că înseamnă lucruri diferite și confundarea lor ar fi exact greșeala
-- | pe care un registru de reputație n-are voie s-o facă:
-- |
-- |   * __acceptată sau nu__ — e alegerea SUBIECTULUI. O atestare neacceptată e afirmată, nu
-- |     recunoscută, și asta nu spune nimic despre adevărul ei;
-- |   * __contestată__ — cineva a deschis o dispută și a blocat un depozit. Blocat, nu pus la
-- |     bătaie: depozitul se întoarce pe oricare verdict, deci o contestație costă taxe de rețea și
-- |     nimic altceva;
-- |   * __confirmată în dispută__ (`upheld`) — disputa s-a judecat și a căzut împotriva atestării.
-- |
-- | O atestare poate fi acceptată și contestată în același timp. De-aia sînt două coloane și nu o
-- | singură „stare".
module Components.Explorer.AttestationList
  ( Slot
  , Output
  , _attestationList
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getAttestations, getProfiles)
import Capabilities.Query.Gov.Types (AttestationPage(..), AttestationRow(..), ProfilePage(..), ProfileRow(..))
import Components.Shared.DRepIdentity (shortId)
import Components.Shared.Refresh (subscribeRefresh)
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Tuple (Tuple(..))
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), isJust, isNothing)
import Format (formatDay, formatInt, humanize, matchLine)
import Halogen as H
import AppEnv as AppEnv
import Components.Shared.OnchainId as OnchainId
import Components.Shared.Pager as Pager
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Router.Class (class MonadRouter)
import Halogen.Store.Monad (class MonadStore)
import Network.RemoteData (RemoteData(..))
import Query.Page (clampLimit, listLimitMax, nextOffset, offsetCeiling, prevOffset)
import Route (Route)
import Route.GovQueries
  ( RegistryFilters
  , attestationDetailHrefFor
  , attestationListHrefFor
  , emptyRegistryFilters
  , writeHrefFor
  )
import Store as Store
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_attestationList :: Proxy "attestationList"
_attestationList = Proxy

type Input = RegistryFilters

type State =
  { filters :: RegistryFilters
  , refreshing :: Boolean
  , page :: RemoteData ApiError AttestationPage
  -- Numele profilurilor, după id. Tabelul ăsta e „cine a vouchuit pentru cine", iar cu două
  -- hash-uri de şaizeci de caractere pe rînd nu răspunde la întrebarea aia: arată că s-a întîmplat
  -- ceva, nu între cine.
  , names :: Map String String
  }

data Action
  = Initialize
  | Retry
  | Receive Input

component
  :: forall q m
   . MonadQueryGov m
  => MonadStore Store.Action Store.Store m
  => MonadRouter Route m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \filters -> { filters, page: NotAsked, refreshing: false, names: Map.empty }
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
    Initialize -> do
      -- O scriere confirmată schimbă ce arată ecranul ăsta, iar proiecția vine ~45s după
      -- tranzacție — deci nu se poate încărca o dată și gata.
      subscribeRefresh Retry
      void (H.fork load)
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
    res <- getAttestations st.filters
    H.modify_ _
      { refreshing = false
      , page = case res of
          Left e -> Failure e
          Right p -> Success p
      }
    -- Numele se cer o singură dată, și eșecul lor NU strică ecranul: fără ele se arată
    -- identificatorii, ca înainte. Registrul are douăsprezece profiluri pe preprod, deci o cerere
    -- de 200 le acoperă; dacă ajunge să nu le mai acopere, ce se vede e un id, nu un nume greșit.
    when (Map.isEmpty st.names) do
      profiles <- getProfiles (emptyRegistryFilters { limit = Just "200" })
      case profiles of
        Left _ -> pure unit
        Right (ProfilePage pp) ->
          H.modify_ _ { names = Map.fromFoldable (map (\(ProfileRow r) -> Tuple r.id r.name) pp.items) }

  render st =
    HH.div [ HP.class_ (HH.ClassName "explorer-page container mx-auto px-6 py-6 space-y-4") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ]
              [ HH.text (if isCredentialView st.filters then "Verified credentials" else "Vouches") ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80 max-w-3xl") ]
              [ HH.text
                  ( if isCredentialView st.filters then
                      "Every governance credential a profile has claimed, with the proof the validator \
                      \required. For a key credential that is a signature on the claiming \
                      \transaction; for a script credential it is only that the transaction spent an \
                      \output at the script's address, which one member of a 1-of-N multisig — or \
                      \anyone after a timelock — can do. Where two parties claim the same \
                      \credential, both are shown and neither is ranked — the registry does not decide \
                      \who is right."
                    else
                      "What one profile states about another, countersigned by its subject. A vouch is \
                      \a signed opinion, not a finding of fact: nobody countersigns criticism of \
                      \themselves, so read this as what people are willing to put their name to. One \
                      \marked \"not yet\" has been stated but not countersigned, which is not the same \
                      \as denied."
                  )
              ]
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
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading vouches…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The vouches could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          , HH.button
              [ HP.class_ (HH.ClassName "btn btn-sm"), HP.type_ HP.ButtonButton, HE.onClick (const Retry) ]
              [ HH.text "Try again" ]
          ]
      ]

  body st page@(AttestationPage p) =
    HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
      [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-70") ]
          [ HH.text (matchLine p.total p.offset (length p.items) "vouch")
          , if st.refreshing then
              HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-xs ml-2") ] []
            else HH.text ""
          ]
      , if null p.items then emptyState st else table st p.items
      , if null p.items then HH.text "" else pager st page
      ]

  -- Trei goluri, pentru că înseamnă trei lucruri diferite — și scrierea unuia în locul altuia era
  -- defectul: „No vouches have been issued yet" e o afirmație despre REGISTRU, iar arătată pe o
  -- vedere îngustată era falsă.
  --
  -- Vederea de credențiale își primește propoziția ei: ecranul pune o singură întrebare („cine
  -- controlează credențiala asta?"), deci golul lui e un fapt despre revendicări, nu despre
  -- vouch-uri în general. Dar DOAR cînd `kind` e singurul filtru: cu `subject` sau `issuer` pe
  -- lîngă el, propoziția ar vorbi iar despre tot registrul uitîndu-se la o felie din el.
  emptyState st =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body items-start gap-2") ]
          ( if isCredentialView st.filters && isNothing st.filters.subject && isNothing st.filters.issuer then
              [ HH.p_ [ HH.text "No profile has claimed a governance credential yet." ]
              , wayOut "See all vouches"
              ]
            else if hasAnyFilter st.filters then
              [ HH.p_ [ HH.text "No vouches match these filters." ]
              , wayOut "Clear the filters"
              ]
            else [ HH.p_ [ HH.text "No vouches have been issued yet." ] ]
          )
      ]

  -- Drumul înapoi e același pentru amîndouă golurile filtrate — lista nefiltrată a ACESTUI ecran —
  -- deci adresa stă într-un singur loc, chiar dacă eticheta diferă.
  wayOut label =
    HH.a
      [ HP.href (attestationListHrefFor emptyRegistryFilters)
      , HP.class_ (HH.ClassName "btn btn-sm btn-primary")
      ]
      [ HH.text label ]

  -- „Filtrat" înseamnă `kind`, `subject` sau `issuer` — singurele care schimbă CE se potrivește.
  -- `order_by`/`sort_order` doar reordonează, iar `limit`/`offset` sînt o fereastră peste
  -- potriviri: o pagină goală de la capătul listei nu e un filtru care n-a prins nimic.
  hasAnyFilter f = isJust f.kind || isJust f.subject || isJust f.issuer

  table st items =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200 explorer-card") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body p-0") ]
          [ HH.div [ HP.class_ (HH.ClassName "overflow-x-auto") ]
              [ HH.table [ HP.class_ (HH.ClassName "table table-sm") ]
                  [ HH.thead_
                      [ HH.tr_
                          [ HH.th_ [ HH.text "Vouch" ]
                          , HH.th_ [ HH.text "Subject" ]
                          , HH.th_ [ HH.text "Issuer" ]
                          , HH.th_ [ HH.text "Date" ]
                          -- Capul de coloană și celula din `row` se schimbă pe ACEEAȘI condiție.
                          -- Dacă una se mută fără cealaltă, tabelul iese decalat cu o coloană.
                          , HH.th_
                              [ HH.text (if isCredentialView st.filters then "Credential proved" else "Accepted") ]
                          , HH.th_ [ HH.text "Challenges" ]
                          , HH.th_ [ HH.text "Act" ]
                          ]
                      ]
                  , HH.tbody_ (map (row st) items)
                  ]
              ]
          ]
      ]

  -- Numele deasupra, identificatorul dedesubt — nu unul SAU altul. Numele e ce caută omul, iar
  -- identificatorul e ce verifică pe lanț, şi regula casei (R3) cere să fie amîndouă.
  party st i = case Map.lookup i st.names of
    Nothing -> idChip i
    Just n ->
      HH.div_
        [ HH.div [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text n ]
        , HH.div [ HP.class_ (HH.ClassName "opacity-70") ] [ idChip i ]
        ]

  idChip i =
    OnchainId.withChip
      { value: i, shown: shortId i, kind: OnchainId.Asset, explorerBase: AppEnv.explorerBase }

  row st (AttestationRow a) =
    HH.tr_
      [ HH.td_
          -- Numele duce la pagina vouch-ului. Fara ea, ca sa vezi CE s-a contestat trebuia sa
          -- treci pe ecranul de provocari si sa filtrezi dupa un id de saizeci de caractere.
          [ HH.div_
              [ HH.a
                  [ HP.href (attestationDetailHrefFor a.id)
                  , HP.class_ (HH.ClassName "link link-hover")
                  ]
                  [ HH.text a.name ]
              ]
          , HH.div [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text (humanize a.kind) ]
          -- IDENTIFICATORUL ATESTĂRII, care nu era randat nicăieri. Exista doar în `href`-urile de
          -- mai jos, iar `/write` îi cere omului să-l „lipească" — deci calea de scriere
          -- documentată nu se putea parcurge din interfață. Linkurile îl purtau cu ele, ceea ce
          -- acoperea cazul obișnuit și ascundea lipsa: oricine voia id-ul pentru altceva (un
          -- raport, un test, o verificare pe lanț) nu-l avea de unde lua.
          , HH.div [ HP.class_ (HH.ClassName "mt-0.5 opacity-70") ]
              [ OnchainId.withChip
                  { value: a.id
                  , shown: shortId a.id
                  , kind: OnchainId.Asset
                  , explorerBase: AppEnv.explorerBase
                  }
              ]
          ]
      , HH.td_ [ party st a.subject ]
      , HH.td_ [ party st a.issuer ]
      , HH.td [ HP.class_ (HH.ClassName "text-sm whitespace-nowrap"), HP.title a.date ] [ HH.text (formatDay a.date) ]
      -- Pe vederea de revendicări de credențială coloana asta NU poate fi „Accepted": revendicarea
      -- e AUTOEMISĂ — regula `Mc1` cere `subject == issuer`, iar `Mr` scutește felurile de
      -- credențială de interdicția autoatestării — deci nu există a doua parte care să
      -- contrasemneze și `accepted` e structural fals pe toate rândurile. O pastilă „not yet" pe
      -- fiecare rând n-ar adăuga nicio informație și ar contrazice chiar titlul ecranului. Ce
      -- lipsea în locul ei e credențiala însăși, adică singurul lucru pentru care se deschide
      -- ecranul.
      , HH.td_ [ if isCredentialView st.filters then credentialCell a else acceptedBadge a ]
      , HH.td_ [ disputeCell a ]
      -- Linkurile duc identificatorul CU ELE. Fără asta, „contestă atestarea asta" înseamnă că
      -- omul copiază de mână un identificator de şaizeci de caractere dintr-un tabel.
      , HH.td [ HP.class_ (HH.ClassName "whitespace-nowrap") ]
          -- „Accept" dispare si pe vederea de credentiale, nu doar cand e deja acceptata: o
          -- revendicare e auto-emisa (`Mc1` cere `subject == issuer`), deci nu exista a doua parte
          -- care s-o contrasemneze. Un link care nu poate reusi niciodata e mai rau decit absenta
          -- lui, fiindca trimite omul intr-un formular care va fi refuzat de lant.
          [ if a.accepted || isCredentialView st.filters then HH.text ""
            else
              HH.a
                [ HP.href (writeHrefFor { flow: Just "accept-attestation", subject: Just a.id })
                , HP.class_ (HH.ClassName "link link-hover text-xs mr-2")
                ]
                [ HH.text "Accept" ]
          , HH.a
              [ HP.href (writeHrefFor { flow: Just "open-dispute", subject: Just a.id })
              , HP.class_ (HH.ClassName "link link-hover text-xs")
              ]
              [ HH.text "Challenge" ]
          ]
      ]

  -- „Afirmată, nerecunoscută" și nu „respinsă": subiectul care n-a acceptat încă nu a negat.
  -- `whitespace-nowrap`: „not yet accepted" se rupea pe două rînduri ÎN pastilă, iar conturul
  -- tăia textul pe la mijloc. O pastilă e o etichetă, nu un paragraf.
  acceptedBadge a =
    HH.span
      [ HP.class_
          ( HH.ClassName
              ("badge badge-sm whitespace-nowrap " <> if a.accepted then "badge-success" else "badge-outline")
          )
      , HP.title
          ( if a.accepted then "The subject countersigned this claim."
            else "Stated, but the subject has not countersigned it. That is not the same as denied."
          )
      ]
      [ HH.text (if a.accepted then "accepted" else "not yet") ]

  -- Credențiala e bech32 CIP-129, deci rolul se citește din prefix (`drep1…`, `cc_cold1…`,
  -- `cc_hot1…`) și se vede în partea scurtată. Valoarea întreagă, linkul și copierea stau în chip,
  -- la fel ca pe pagina de detaliu — ca cineva care nu ne crede pe cuvânt să poată verifica.
  credentialCell a = case a.credential of
    Nothing -> HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text "not named" ]
    Just c ->
      OnchainId.withChip
        { value: c, shown: shortId c, kind: OnchainId.DRep, explorerBase: AppEnv.explorerBase }

  -- Zero dispute e cazul obișnuit și se scrie discret; o dispută deschisă e o întrebare în curs,
  -- iar una confirmată e un verdict împotriva atestării. Trei lucruri, trei culori.
  disputeCell a =
    if a.disputeCount == 0 then
      HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ] [ HH.text "none" ]
    else
      HH.div [ HP.class_ (HH.ClassName "flex flex-wrap gap-1") ]
        [ if a.openDisputeCount > 0 then
            HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-warning") ]
              [ HH.text (formatInt a.openDisputeCount <> " open") ]
          else HH.text ""
        , if a.upheldDisputeCount > 0 then
            HH.span [ HP.class_ (HH.ClassName "badge badge-sm badge-error") ]
              [ HH.text (formatInt a.upheldDisputeCount <> " upheld") ]
          else HH.text ""
        , HH.span [ HP.class_ (HH.ClassName "text-xs opacity-70") ]
            [ HH.text (formatInt a.disputeCount <> " in total") ]
        ]

  pager st (AttestationPage p) =
    let
      limit = clampLimit listLimitMax p.limit
      prev = prevOffset limit p.offset
      next = nextOffset offsetCeiling limit p.offset p.total
      hrefFor off = attestationListHrefFor (st.filters { offset = Just (show off), limit = Just (show limit) })
    in
      Pager.render
        { total: p.total
        , offset: p.offset
        , shown: length p.items
        , ceiling: offsetCeiling
        , prev
        , next
        , hrefFor
        , noun: "vouch"
        }

-- | Vederea filtrata pe revendicari de credentiala. Nu e un ecran separat: aceleasi coloane, acelasi
-- | tabel, alt titlu si alt paragraf -- fiindca intrebarea „cine controleaza credentiala asta?" se
-- | pune pe RINDURILE astea, nu pe altele. Un ecran nou ar fi fost cod duplicat.
isCredentialView :: RegistryFilters -> Boolean
isCredentialView f = f.kind == Just "credential_claim"
