-- | Metodologia: fiecare metrică de pe site, cu formula publicată și cu SQL-ul care o calculează.
-- |
-- | Pagina asta e diferențiatorul produsului scris pe ecran. Nu e documentație: e răspunsul la
-- | „de unde știi?", iar răspunsul e interogarea întreagă, nu o descriere a ei.
-- |
-- | `null_when` are loc propriu, pentru că e regula care face diferența între „n/a" și „0%" — iar
-- | diferența aceea e, pe un ecran de reputație, diferența dintre o constatare și o acuzație.
module Components.Explorer.Methodology
  ( Slot
  , Output
  , _methodology
  , component
  ) where

import Prelude

import Capabilities.Query.Gov.Http (ApiError, renderApiError)
import Capabilities.Query.Gov.MonadQueryGov (class MonadQueryGov, getFormulas)
import Capabilities.Query.Gov.Types (Formula(..))
import Data.Array (length, null)
import Data.Const (Const)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), maybe)
import Format (formatInt, pluralize)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Network.RemoteData (RemoteData(..))
import Route.GovQueries (MethodologyFilters)
import Type.Proxy (Proxy(..))

type Slot = H.Slot (Const Void) Output Unit

type Output = Void

_methodology :: Proxy "methodology"
_methodology = Proxy

type Input = MethodologyFilters

type State =
  { focus :: Maybe String
  , formulas :: RemoteData ApiError (Array Formula)
  }

data Action
  = Initialize
  | Receive Input

component
  :: forall q m
   . MonadQueryGov m
  => H.Component q Input Output m
component =
  H.mkComponent
    { initialState: \f -> { focus: f.focus, formulas: NotAsked }
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        , receive = Just <<< Receive
        }
    }
  where
  handleAction = case _ of
    Initialize -> do
      H.modify_ _ { formulas = Loading }
      res <- getFormulas
      H.modify_ _
        { formulas = case res of
            Left e -> Failure e
            Right fs -> Success fs
        }
    -- Doar evidențierea se schimbă la navigare; formulele nu se cer din nou.
    Receive f -> H.modify_ _ { focus = f.focus }

  render st =
    HH.div [ HP.class_ (HH.ClassName "container mx-auto px-6 py-6 space-y-4 max-w-4xl") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-2") ]
          [ HH.h1 [ HP.class_ (HH.ClassName "text-3xl font-bold") ] [ HH.text "Methodology" ]
          , HH.p [ HP.class_ (HH.ClassName "opacity-80") ]
              [ HH.text
                  "Every number on this site comes from one of the formulas below. Each one is \
                  \published with the exact query that computes it, the denominator it divides by, \
                  \and the cases in which it refuses to produce a number at all."
              ]
          ]
      , case st.formulas of
          NotAsked -> loading
          Loading -> loading
          Failure e -> failure e
          Success fs ->
            if null fs then
              HH.p [ HP.class_ (HH.ClassName "opacity-60") ] [ HH.text "No formulas are published." ]
            else
              HH.div [ HP.class_ (HH.ClassName "space-y-4") ]
                ( [ HH.p [ HP.class_ (HH.ClassName "text-sm opacity-60") ]
                      [ HH.text (pluralize (length fs) "published formula" <> ".") ]
                  ] <> map (formulaCard st.focus) fs
                )
      ]

  loading =
    HH.div [ HP.class_ (HH.ClassName "card bg-base-200") ]
      [ HH.div [ HP.class_ (HH.ClassName "card-body") ]
          [ HH.span [ HP.class_ (HH.ClassName "loading loading-dots loading-md") ] []
          , HH.p [ HP.class_ (HH.ClassName "opacity-70") ] [ HH.text "Loading the formulas…" ]
          ]
      ]

  failure e =
    HH.div [ HP.class_ (HH.ClassName "alert alert-error") ]
      [ HH.div [ HP.class_ (HH.ClassName "space-y-1") ]
          [ HH.p [ HP.class_ (HH.ClassName "font-medium") ] [ HH.text "The formulas could not be loaded." ]
          , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text (renderApiError e) ]
          ]
      ]

  formulaCard focus (Formula f) =
    let
      focused = focus == Just f.formulaId
    in
      HH.div
        [ HP.id f.formulaId
        , HP.class_
            ( HH.ClassName
                ("card bg-base-200 " <> (if focused then "ring-2 ring-primary" else ""))
            )
        ]
        [ HH.div [ HP.class_ (HH.ClassName "card-body gap-2") ]
            [ HH.div [ HP.class_ (HH.ClassName "flex flex-wrap items-baseline justify-between gap-2") ]
                [ HH.h2 [ HP.class_ (HH.ClassName "card-title text-lg") ] [ HH.text f.name ]
                , HH.span [ HP.class_ (HH.ClassName "font-mono text-xs opacity-60") ]
                    [ HH.text (f.formulaId <> maybe "" (\v -> " · version " <> formatInt v) f.version) ]
                ]
            , case f.expression of
                Nothing -> HH.text ""
                Just e ->
                  HH.pre [ HP.class_ (HH.ClassName "bg-base-300 rounded p-2 text-sm overflow-x-auto") ]
                    [ HH.code_ [ HH.text e ] ]
            , labelled "Field" (map (\x -> x) f.field)
            , labelled "Denominator" f.denominator
            -- Regula care face diferența între „n/a" și „0%".
            , labelled "Returns nothing when" f.nullWhen
            , listBlock "Reads from" f.inputs
            , listBlock "Edge cases" f.edgeCases
            , listBlock "Parameters" f.params
            , case f.spec of
                Nothing -> HH.text ""
                Just sp ->
                  HH.p [ HP.class_ (HH.ClassName "text-xs opacity-60") ]
                    [ HH.text ("Specified in " <> sp) ]
            , case f.sql of
                Nothing -> HH.text ""
                Just sql ->
                  -- `details` nativ: nicio stare, niciun JavaScript, și se poate deschide
                  -- înainte de a se încărca orice.
                  HH.details [ HP.class_ (HH.ClassName "collapse-arrow") ]
                    [ HH.summary [ HP.class_ (HH.ClassName "cursor-pointer text-sm link link-hover") ]
                        [ HH.text "Show the query that computes this" ]
                    , HH.pre
                        [ HP.class_
                            (HH.ClassName "bg-base-300 rounded p-2 mt-2 text-xs overflow-x-auto whitespace-pre")
                        ]
                        [ HH.code_ [ HH.text sql ] ]
                    ]
            ]
        ]

  labelled title = case _ of
    Nothing -> HH.text ""
    Just value ->
      HH.div_
        [ HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-60") ] [ HH.text title ]
        , HH.p [ HP.class_ (HH.ClassName "text-sm") ] [ HH.text value ]
        ]

  listBlock title values =
    if null values then HH.text ""
    else
      HH.div_
        [ HH.div [ HP.class_ (HH.ClassName "text-xs uppercase tracking-wide opacity-60") ] [ HH.text title ]
        , HH.ul [ HP.class_ (HH.ClassName "list-disc list-inside text-sm space-y-0.5") ]
            (map (\v -> HH.li_ [ HH.text v ]) values)
        ]
