---
name: implementation-workflow
description: >-
  Use when building new features, pages, or capabilities. Covers
  design-first capabilities, stub-first development, coherent mock data,
  and the implementation approach conventions.
---

# Implementation Workflow

## When to use

- Building a new page, component, or capability method.
- Creating or updating stub/mock data.
- Starting a new milestone or feature branch.

## Design-first capabilities

Do not limit capability design to existing APIs or backend data types. Define new capability methods, domain types, and stubs when that is the better design choice; map from or adapt backend types at the boundary (e.g. in `Default` or FFI).

## Stub-first development

Develop the website first against stub data:

1. Define capability functions that make sense for the UI (read/write, queries, filters).
2. Provide instances backed by coherent stub data so the full UI can be built and tested without a live backend.
3. The default build (`npm run dev`, `npm run build`) uses `MainDemo` which wires mock implementations.

### Capabilities to stub

- **MonadQueryApi** — mock in `Capabilities.Query.Api.Mock` (e.g. `getItemsPageMock`), wired into `DemoM`.
- **MonadInteractionApi** (or equivalent) — when added, define the class and a stub instance that returns/simulates data consistent with the query stubs.

## Coherent stubs

Keep stub data coherent across capabilities:

- Counts match list lengths or agreed totals (e.g. `total` field aligns with `items.length`).
- IDs cross-reference: entities referenced in lists (e.g. by-owner, by-issuer) exist in the stub lookup tables.
- Aggregates and frequencies align with the underlying stub lists.
- When adding new stub entities or capabilities, update related stubs so lookups and lists stay consistent.

## Worked example in the template

The shipped scaffold demonstrates this end-to-end:

- `src/MainDemo.purs` is the **default bundle entry** (`build:spago --module MainDemo`). It runs `DemoM`, which wires `Capabilities.Query.Api.Mock` so the UI works with no backend.
- `src/Main.purs` is the **production entry** (`build:spago:prod`). It runs `AppM`, which wires `Capabilities.Query.Api.Default` (HTTP via `affjax-web`).
- `src/Capabilities/Query/Api/Mock.purs` shows what "coherent stub data" means in practice: search is applied **before** pagination so the `total` field updates as the user types — the mock and the eventual backend both behave that way.

Pattern to copy: stand up the mock first, build the whole UI against it, and only swap in `Default` when the backend exists.

## Reference

- **Effect-capability refactors**: when narrowing `MonadAff`/`MonadEffect` or adding intent-level effect capabilities, use skill **effect-capability-refactor** and rule `effect-capability-narrowing`.
- **Page-shaped capabilities**: when adding a page that needs data, use skill **capability-layer** to design `getXPage` + DTO before writing the component.
