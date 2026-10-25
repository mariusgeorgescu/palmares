-- | Randarea unui document de metadate — adică a unui document pe care l-a scris altcineva.
-- |
-- | Trei reguli, toate pentru că textul de aici e neîncrezut:
-- |
-- |   * __niciun HTML brut.__ Tot ce vine din document ajunge pe ecran prin `HH.text`, deci ca text.
-- |     Halogen nu are aici o cale spre `innerHTML`, și nu i se dă una;
-- |   * __lungimea se taie la randare__, nu se speră. `objectives` n-are limită în CIP-119, iar un
-- |     câmp de 400 kB ar bloca pagina fără să fie nevoie de niciun exploit;
-- |   * __linkurile se filtrează pe schemă.__ Halogen scrie `href` prin proprietatea DOM, iar un
-- |     `javascript:` pus în `href` se execută la clic. `safeHref` acceptă doar `http` și `https`;
-- |     restul rămân text. Legăturile ies cu `rel="nofollow noopener noreferrer"`, pentru că nu dăm
-- |     niciun fel de garanție despre ce e la celălalt capăt, și cu URL-ul la vedere, ca omul să
-- |     vadă unde pleacă înainte să dea clic.
-- |
-- | Ce __nu__ se poate face aici, și e un fapt măsurat despre API: când documentul nu se potrivește
-- | cu hash-ul din lanț sau nu respectă schema, serverul întoarce `anchor_content: null` — nu avem
-- | octeții, deci nu putem „randa documentul neconform așa cum e". Ce putem, și facem, e să nu
-- | ascundem că există: se arată URL-ul, starea, și ce înseamnă starea aceea în cuvinte.
module Components.Shared.Anchor
  ( safeHref
  , clampText
  , render
  , renderAction
  , renderUnavailable
  , statusExplanation
  ) where

import Prelude

import Capabilities.Query.Gov.Types (ActionAnchor(..), AnchorContent(..), AnchorRef(..))
import Data.Array (null)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Data.String.CodeUnits as CU
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

-- | URL-ul, dacă e o schemă pe care un browser o poate deschide fără să execute cod. Orice
-- | altceva — `javascript:`, `data:`, `file:`, o cale relativă, un șir gol — nu devine link.
safeHref :: String -> Maybe String
safeHref raw =
  let
    trimmed = String.trim raw
    lower = String.toLower trimmed
  in
    if CU.take 7 lower == "http://" || CU.take 8 lower == "https://" then Just trimmed
    else Nothing

-- | Taie un text la o lungime maximă, adăugând un semn că a fost tăiat.
clampText :: Int -> String -> String
clampText limit s =
  if String.length s <= limit then s
  else CU.take limit s <> "…"

-- | Explicația stării unei ancore, în cuvinte. Scrisă pentru cineva care vede „hash_mismatch" și
-- | nu știe dacă e vina DRep-ului, a noastră, sau a nimănui.
statusExplanation :: Maybe String -> String
statusExplanation = case _ of
  Nothing ->
    "This DRep registered without a metadata document."
  Just "unreachable" ->
    "We could not fetch the document at this URL. It may be offline now, or it may never have been \
    \reachable."
  Just "hash_mismatch" ->
    "The document at this URL does not match the hash recorded on chain. Either it changed after \
    \registration, or the URL serves something else. Its contents are not shown, because they are \
    \not what this DRep registered."
  Just "invalid_schema" ->
    "The document at this URL is not a CIP-119 metadata document, so its fields cannot be read."
  Just "valid" ->
    "The document at this URL matches the hash recorded on chain."
  Just other ->
    "The metadata document is in state \"" <> clampText 40 other <>
      "\", which this page does not \
      \have an explanation for."

-- | Ce se arată când nu avem conținut: starea, ce înseamnă, și URL-ul pe care îl poate deschide
-- | oricine ca să se uite singur.
renderUnavailable
  :: forall w i
   . { anchorStatus :: Maybe String, anchorUrl :: Maybe String }
  -> HH.HTML w i
renderUnavailable r =
  HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
    [ HH.div [ HP.class_ (HH.ClassName "flex items-center gap-2") ]
        [ HH.span [ HP.class_ (HH.ClassName "badge badge-outline badge-sm") ]
            [ HH.text (fromMaybe "no metadata" r.anchorStatus) ]
        ]
    , HH.p [ HP.class_ (HH.ClassName "text-sm opacity-80") ] [ HH.text (statusExplanation r.anchorStatus) ]
    , case r.anchorUrl of
        Nothing -> HH.text ""
        Just url -> externalLink url url
    ]

-- | Documentul unei acțiuni (CIP-108) — alt set de câmpuri decât al unui DRep (CIP-119).
-- |
-- | Limita de tăiere e mai mare aici (10.000, nu 2.000): `rationale` e argumentul pentru care se
-- | votează, iar pe o propunere reală avea peste 2.500 de caractere. Tăierea rămâne, pentru că
-- | motivul ei n-a fost niciodată lungimea rezonabilă, ci cea nerezonabilă.
renderAction :: forall w i. ActionAnchor -> HH.HTML w i
renderAction (ActionAnchor a) =
  HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
    [ longField "Abstract" a.abstract
    , longField "Motivation" a.motivation
    , longField "Rationale" a.rationale
    , if null a.references then HH.text ""
      else
        HH.div_
          [ fieldLabel "References"
          -- Nu se deduplică: documentul măsurat avea același link de două ori, iar un
          -- deduplicator ar ascunde ce au scris ei.
          , HH.ul [ HP.class_ (HH.ClassName "list-disc list-inside space-y-1") ]
              (map referenceItem a.references)
          ]
    ]

fieldLabel :: forall w i. String -> HH.HTML w i
fieldLabel t = HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-70") ] [ HH.text t ]

longField :: forall w i. String -> Maybe String -> HH.HTML w i
longField title = case _ of
  Nothing -> HH.text ""
  Just value ->
    if String.trim value == "" then HH.text ""
    else
      HH.div_
        [ fieldLabel title
        -- `max-w-3xl`: pe un card lat, un paragraf ajunge la 170-180 de caractere pe rând, iar la
        -- al treilea rând ochiul nu mai nimerește începutul rândului următor. Doar paragrafele se
        -- îngustează; tabelele și listele rămân pe lățimea cardului.
        , HH.p [ HP.class_ (HH.ClassName "text-sm whitespace-pre-line max-w-3xl") ]
            [ HH.text (clampText 10000 value) ]
        ]

referenceItem :: forall w i. AnchorRef -> HH.HTML w i
referenceItem (AnchorRef ref) =
  let
    text = clampText 120 (fromMaybe "(untitled reference)" ref.label)
  in
    HH.li_
      [ case ref.uri of
          Nothing -> HH.span_ [ HH.text text ]
          Just uri ->
            HH.span [ HP.class_ (HH.ClassName "space-x-2") ]
              [ externalLink uri text
              , HH.span [ HP.class_ (HH.ClassName "font-mono text-xs opacity-70 break-all") ]
                  [ HH.text (clampText 160 uri) ]
              ]
      ]

render :: forall w i. AnchorContent -> HH.HTML w i
render (AnchorContent a) =
  HH.div [ HP.class_ (HH.ClassName "space-y-3") ]
    [ field "Objectives" a.objectives
    , field "Motivations" a.motivations
    , field "Qualifications" a.qualifications
    , case a.paymentAddress of
        Nothing -> HH.text ""
        Just addr ->
          HH.div_
            [ label "Payment address"
            -- Se arată, nu se folosește: nimic din ecranul acesta nu propune o plată.
            , HH.p [ HP.class_ (HH.ClassName "font-mono text-xs break-all opacity-80") ]
                [ HH.text (clampText 160 addr) ]
            ]
    , case a.imageUrl of
        Nothing -> HH.text ""
        Just url ->
          HH.div_
            [ label "Image"
            -- URL-ul de imagine nu se încarcă: ar fi o cerere făcută de browserul vizitatorului
            -- către un server pe care documentul l-a ales, adică un ping cu IP-ul cititorului.
            , externalLink url (clampText 120 url)
            ]
    , if null a.references then HH.text ""
      else
        HH.div_
          [ label "References"
          , HH.ul [ HP.class_ (HH.ClassName "list-disc list-inside space-y-1") ]
              (map reference a.references)
          ]
    ]
  where
  label = fieldLabel

  field title = case _ of
    Nothing -> HH.text ""
    Just value ->
      if String.trim value == "" then HH.text ""
      else
        HH.div_
          [ label title
          , HH.p [ HP.class_ (HH.ClassName "text-sm whitespace-pre-line max-w-3xl") ]
              [ HH.text (clampText 2000 value) ]
          ]

  reference = referenceItem

-- | Un link spre un document străin. Dacă schema nu e http(s), rămâne text: nimic nu e atât de
-- | important de afișat încât să merite un `href` care execută cod.
externalLink :: forall w i. String -> String -> HH.HTML w i
externalLink uri text = case safeHref uri of
  Nothing ->
    HH.span [ HP.class_ (HH.ClassName "font-mono text-xs break-all opacity-70") ]
      [ HH.text (clampText 160 uri <> " (not a web link)") ]
  Just href ->
    HH.a
      [ HP.href href
      , HP.target "_blank"
      , HP.rel "nofollow noopener noreferrer"
      , HP.class_ (HH.ClassName "link link-hover text-sm break-all")
      ]
      [ HH.text text ]
