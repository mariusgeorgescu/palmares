---
name: capability-layer
description: >-
  Use when adding or changing data fetching, defining composite page APIs,
  refactoring components to use page-shaped capabilities, integrating
  GraphQL, or defining new DTOs. Keeps MonadQueryApi as the single
  UI-facing seam.
---

# Capability Layer

## When to use

- Adding a new explorer, dashboard, or detail page that needs backend data.
- Refactoring a component that does multiple capability calls into a single page-shaped call.
- Defining new DTOs or composite functions in `Capabilities.Query.Api.Types`.
- Implementing or switching between Mock, REST, and GraphQL backends behind the capability.
- Extending `MonadQueryApi` with new methods.

## Instructions

### Core principle: one seam

`MonadQueryApi` (or a thin sibling) owns all data-fetching contracts. Components consume only these functions and stay unaware of transport (REST vs GraphQL vs mock).

### Page-shaped composite functions

New composite functions return bundled data to cut round-trips:

- `getItemsPage :: ItemsQuery -> m (Either String { items :: Array Item, total :: Int })`
- `getDashboardPage :: m (Either String DashboardPage)`
- `getEntityDetail :: EntityId -> m (Either String EntityDetail)` (primary entity + related edges)

For aggregate / dashboard pages (landing pages combining multiple domains), define a page-level composite first.

### DTOs

Add small DTOs alongside capability types (e.g., `ItemsPage`, `MonthlyCount`, `EntityDetail`) in `Capabilities.Query.Api.Types`. Reuse them for REST, GraphQL, and mocks.

### Aggregate and dashboard-style pages

- **Define a page-level composite first** for any route that shows data from multiple domains.
- **One page-shaped capability implies one main RemoteData** in the component (e.g. `RemoteData String DashboardPage`). Many separate `RemoteData` fields for one page is a sign to introduce a composite.
- **When adding a new page**: if it would call more than one capability, define `getXPage` / `getXData` and a DTO first; the page should call only that.

### GraphQL integration

- Implement GraphQL calls in a single module (e.g., `Capabilities.Query.Api.GraphQL`). Map responses into shared DTOs; do not expose GraphQL specifics to components.
- Prefer page-shaped GraphQL queries over frontend orchestration.
- Frontend parallelization is a secondary tool, not the default. Use it only when sections are truly independent, lazy-loaded, or sourced from different systems.
- Keep a feature flag / env switch to choose between Mock, REST, and GraphQL without touching component code.

### Data-loading strategy defaults

- One capability call per page when the UI always needs the data together.
- Accept one primary + one lazy secondary call when part of the page is optional, below the fold, or expensive.
- Do **not** use frontend parallelization to mask fragmented capability contracts. Fix the capability/query shape first.

### Mock sync

Update the Mock capability to serve new composite functions so the UI compiles and works offline/stubbed. Mocks must stay in sync with new capability functions.

### Adding a new method to MonadQueryApi (4-step pattern)

1. Add the standalone function in `MonadQueryApi.purs`.
2. Add the default (HTTP) implementation in `Default.purs`.
3. Add the mock (pure stub) implementation in `Mock.purs`.
4. Wire `DemoM` to use mock; `AppM` to use default.

## Worked example in the template

The five-file shape lives at `src/Capabilities/Query/Api/`:

- `Env.purs` — `HasApiEnv` row constraint pinning only the fields this capability needs from the reader env.
- `Types.purs` — DTOs (`Item`, `ItemsPage`) + query inputs (`ItemsQuery`, `defaultItemsQuery`).
- `MonadQueryApi.purs` — the class declaration + `HalogenM` instance so components can call methods without `lift`.
- `Default.purs` — HTTP implementation; one function per method, taking `Record (HasApiEnv r)`.
- `Mock.purs` — pure stub; same return shape, no env needed.

`AppM` and `DemoM` wire the two implementations to the same class:

```purescript
-- src/AppM.purs
instance MonadQueryApi AppM where
  getItemsPage q = ask >>= \env -> getItemsPageDefault env q

-- src/DemoM.purs
instance MonadQueryApi DemoM where
  getItemsPage = getItemsPageMock
```

When you add a method, mirror it in all four files (class, default, mock, AppM instance, DemoM instance — five edits).

## Reference

- **Effect capabilities** (`MonadDelay`, `MonadDomEvent`, etc.): use skill **effect-capability-refactor** when adding or narrowing effect constraints in components; keep query capabilities (`MonadQueryApi`) as the data seam and effect capabilities for UI/FFI intents.
