---
name: add-explorer-page
description: >-
  Use when adding a new explorer list page or detail page to the dApp.
  Covers route definition, page-shaped capability, DTO, mock data, and
  component structure.
---

# Add Explorer / Detail Page

## When to use

- Adding a new explorer route (e.g. `/items`, `/proposals`, `/pools`).
- Adding a new detail route (e.g. `/items/:id`).
- Rebuilding an existing explorer page from scratch.

## Step-by-step

### 1. Define the route

Add a variant to the `Route` ADT in `src/Route.purs`. Add the codec in `src/Route/Codec.purs` (`routeCodec`, `parseRoute`, `printRoute`). Detail routes take an entity-id parameter (e.g. `ItemId`, or a Cardano `AssetClass` if appropriate).

### 2. Define a page-shaped capability + DTO

Before writing the component, define what data the page needs as **one composite type**:

```purescript
type ItemsPage =
  { items :: Array Item
  , total :: Int
  }
```

Add the DTO to `Capabilities.Query.Api.Types`. Add the capability method to `MonadQueryApi`:

```purescript
getItemsPage :: ItemsQuery -> m (Either String ItemsPage)
```

This ensures the component has one `RemoteData String ItemsPage`, not multiple `RemoteData` fields.

### 3. Add mock implementation

Add the mock in `Capabilities.Query.Api.Mock`. Keep mock data coherent with existing stubs (counts match list lengths, IDs cross-reference where they should, derived aggregates align).

### 4. Wire instances

Add the method to the `Default` implementation and to `AppM` / `DemoM` instances.

### 5. Build the component

Create the component module under `Components.Explorer.*` or `Components.Profile.*`.

**Explorer list pages** typical state:

```purescript
type ExplorerState a q =
  { items :: RemoteData String (Array a)
  , totalCount :: RemoteData String Int  -- or fold into a page DTO
  , query :: q
  , viewMode :: ViewMode
  }

data ViewMode = GridView | TableView
```

- Layout: KPI strip → filter bar → results (card grid or table) → pagination.
- Add shared render helpers in `Components.Shared.*` (or `Components.Explorer.RenderHelpers`) once the same patterns repeat across pages.

**Detail pages** typical state:

```purescript
type ProfileState info tab =
  { entityId :: EntityId
  , entity :: RemoteData String info
  , activeTab :: tab
  }
```

- Layout: Identity header → tabbed or timeline content → contextual actions.

### 6. Register in Home

Add the slot proxy (underscore-prefixed, e.g. `_itemsExplorer`) in `Components.Home`. Add the route dispatch case. Add navigation links in NavBar / Sidebar.

### 7. Update project docs

Update your project's spec/architecture docs (if any) so they reflect the new page and capability surface. Bump the CHANGELOG when user-facing.

## Worked example

The template ships a complete worked example. Read top-to-bottom in this order:

1. `src/Capabilities/Query/Api/Types.purs` — `Item`, `ItemId`, `ItemsQuery`, `ItemsPage`, `defaultItemsQuery`. The page-shaped DTO is `ItemsPage`.
2. `src/Capabilities/Query/Api/MonadQueryApi.purs` — the single capability seam (`getItemsPage`).
3. `src/Capabilities/Query/Api/Mock.purs` — coherent stub data (12 items, search applied before pagination so `total` updates as you type).
4. `src/Capabilities/Query/Api/Default.purs` — HTTP implementation via `affjax-web` with `HasApiEnv` row.
5. `src/AppM.purs` — `instance MonadQueryApi AppM where getItemsPage q = ask >>= \env -> getItemsPageDefault env q`.
6. `src/DemoM.purs` — `instance MonadQueryApi DemoM where getItemsPage = getItemsPageMock`.
7. `src/Components/Explorer/Items.purs` — the component itself: one `RemoteData String ItemsPage` in state, debounced search via `H.fork` + `MonadDelay`, DaisyUI table, pagination.
8. `src/Components/Home.purs` and `src/Route.purs` — how the route + slot are registered.

Copy this seven-step pattern when adding a new explorer. The names (`Item`, `Items`, etc.) are placeholders — rename freely.
