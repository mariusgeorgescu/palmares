-- | Punctul de intrare al suitei. Fiecare task din plan își adaugă aici spec-ul; agregatorul nu
-- | conține aserțiuni proprii.
module Test.Palmares where

import Prelude

import Effect (Effect)
import Effect.Aff (launchAff_)
import Test.Capabilities.DashboardSpec as DashboardSpec
import Test.Capabilities.ActionSpec as ActionSpec
import Test.Capabilities.DRepDetailSpec as DRepDetailSpec
import Test.Capabilities.DRepListSpec as DRepListSpec
import Test.Capabilities.HttpSpec as HttpSpec
import Test.Capabilities.StatusSpec as StatusSpec
import Test.FormatSpec as FormatSpec
import Test.Capabilities.SearchSpec as SearchSpec
import Test.Capabilities.VoteSpec as VoteSpec
import Test.Query.PageSpec as PageSpec
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner (runSpec)

main :: Effect Unit
main = launchAff_ $ runSpec [ consoleReporter ] do
  HttpSpec.spec
  StatusSpec.spec
  PageSpec.spec
  DashboardSpec.spec
  FormatSpec.spec
  DRepListSpec.spec
  DRepDetailSpec.spec
  ActionSpec.spec
  VoteSpec.spec
  SearchSpec.spec
