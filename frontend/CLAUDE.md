# Cardano dApp Frontend Template — Project Guide

## Project Tooling

- **Language**: PureScript (`.purs`), not Haskell or TypeScript. Module names must match file paths (e.g. `Components.Home` → `src/Components/Home.purs`).
- **Package manager**: Spago (`spago.yaml` workspace/registry format). Extra packages pulled from git in `spago.yaml` workspace `extraPackages`.
- **Build**: `npm run build` (full: spago bundle + CSS + vite build) or `npm run build:spago` (JS only). Default entry is `MainDemo` (stub/mock data). Use `npm run build:prod` to bundle `Main` (production AppM with HTTP calls).
- **Dev**: `npm run dev` (build:spago + CSS + vite dev).
- **BFF**: `npm run bff` (build + serve via Fastify); `npm run bff:dev` (watch mode). BFF is the canonical production server (SPA fallback for path routing). Default port is 80 — use `PORT=8080 npm run bff` locally on macOS.
- **Formatting**: `npm run format` (purs-tidy, in-place); `npm run check-formatting` (CI check). 2-space indentation, no trailing whitespace, final newline.
- **After editing `.purs` files**: run `npx purs-tidy format-in-place <file>` then `npx spago build --json-errors` to format and typecheck.
- **Tests**: `test/` directory, test main: `Test.Main`.

## Key Dependencies

- `halogen` — UI framework
- `halogen-store` — global state management (StoreT)
- `halogen-daisyui` — DaisyUI component library
- `halogen-cardano-wallet-connect-component` — wallet connection (CIP-30)
- `cardano-capabilities` — Cardano wallet capabilities
- `halogen-router` — path-based routing (`MonadRouter`, `MonadNavigate`)
- `remotedata` — async data modeling
- `affjax-web` — HTTP client
- `argonaut-aeson-generic` — JSON codecs

Add `halogen-formless` when the dApp needs typed forms with validation.

## Architecture Decisions

### StoreT for global state
The app uses `halogen-store` (`StoreT Store.Action Store.Store Aff`) for global mutable state. `AppM = RouterT Route (ReaderT Env (StoreT Store.Action Store.Store Aff))`. The general Halogen rule "use Ref, avoid monad transformers beyond ReaderT" is relaxed here in favour of a structured store and reducer.

### Routing
- **Path-based (History API)** — URLs are pathnames (`/`, `/items`). No hash-based routing.
- Boundary modules: `Route` (ADT), `Route.Codec` (routing-duplex). History API integration via halogen-router (`MonadRouter`, `MonadNavigate`).
- Unknown paths render the `NotFound` route/page. Do not redirect unknown paths to home.

### Effect-Capability Narrowing
- Components use **intent-level capabilities** (e.g. `MonadDelay`, `MonadDomEvent`) instead of broad `MonadAff`/`MonadEffect` where a suitable capability exists.
- Broad effects belong at interpreter boundaries (AppM, DemoM).
- Constraint-selection ladder: (1) Pure, (2) Intent capability, (3) Broad monad only when no capability fits.
- Accepted exception: `Components.WalletConnectComponent` slot requires `MonadCIP30` and `MonadAff`; parents that host it inherit those.

### Env vs Store
- **Env** (`AppEnv`): read-only config — `apiBaseUrl`, `allowedNetworkId`. No mutable state.
- **Store** (`Store`): global mutable state — `walletApi`, `user`; actions `Connect`, `Disconnect`, `SetUser`, `ClearUser`; single pure reducer.

### MonadQueryApi Capability (example)
- Type class in `Capabilities.Query.Api.MonadQueryApi`. Types in `Capabilities.Query.Api.Types`. Results as `Either String a`.
- Default implementation in `Capabilities.Query.Api.Default` (takes env, calls API). Mock in `Capabilities.Query.Api.Mock`.
- Production: AppM delegates to Default. Demo/test: DemoM uses Mock. Default build uses `MainDemo` (`npm run dev`).
- Query env: `HasApiEnv r = ( apiBaseUrl :: String | r )` in `Capabilities.Query.Api.Env`. `AppEnv.Env` satisfies it.
- Rename `MonadQueryApi` / `Items*` / `Item` to match your domain.

### Async data
- Use **RemoteData per capability result**. For aggregate pages, prefer one composite capability and one `RemoteData` for the whole page.
- Handle `NotAsked` / `Loading` / `Failure` / `Success` in render per section.

## Module Layout

- **Top-level app modules**: `AppM`, `DemoM`, `Store`, `Main`, `MainDemo`, `AppEnv`.
- **Components**: `Components.*` (e.g. `Components.Home`, `Components.Layout.NavBar`, `Components.Explorer.*`).
- **Capabilities**: `Capabilities.*` (e.g. `Capabilities.LogMessages`, `Capabilities.Delay`, `Capabilities.DomEvent`, `Capabilities.Query.Api.MonadQueryApi`).
- **Validation**: `Validation.*` (when you add forms) — pure Layer 3, no `m` constraints.
- **App utilities**: `App.Utils` at `src/App/Utils.purs` (add when needed).

## Intent Capabilities

| Capability | Module | Use for |
| ---------- | ------ | ------- |
| MonadDelay | Capabilities.Delay | Delays, debounce, timeouts |
| MonadDomEvent | Capabilities.DomEvent | DOM event prevention |

Add `MonadDomFocus`, `MonadGetTime`, `MonadPlaySound`, `CopyToClipboard`, `ScrollToTop`, etc. as your features need them — see the `effect-capability-refactor` skill.

## Dependent Repositories

These repos are pulled via `spago.yaml` workspace `extraPackages`.

### purescript-halogen-daisyui
- Modules: `Halogen.DaisyUI.*`. Barrel modules `Halogen.DaisyUI.Utils` and `Halogen.DaisyUI.Components`.
- Component helpers are `render*` (e.g. `renderToasts`, `renderButton`).

### halogen-cardano-wallet-connect-component
- Module: `Components.WalletConnectComponent`; exports `Slot`, `_walletConnect`, `Query`, `Output`, `Input`, `component`.
- Uses `handleQuery` for parent-driven updates; raises `Output` for wallet events. Requires `MonadCIP30` and `MonadAff`.

### purescript-cardano-capabilities
- Modules: `Cardano.Capabilities.*`. Marker type class with standalone functions (e.g. `enableWallet`, `getNetworkName`).
- Consumer declares empty instance (`instance MonadCIP30 AppM`) and uses the functions.

### purescript-cip30 / cardano-serialization-lib
- Low-level bindings; treat as upstream FFI/capability backends.

## Component Reuse

- **Prefer upstream**: Check `purescript-halogen-daisyui` (`Halogen.DaisyUI.*`) before implementing new reusable UI components.
- **DaisyUI-first**: Use DaisyUI primitives (card, button, input, badge, modal, etc.) and expose via Halogen HTML. Custom components only when no DaisyUI primitive fits.

## Workflow Guides

Reference these when performing the corresponding tasks. Read the full file for step-by-step instructions.

| Workflow | File | When to use |
| -------- | ---- | ----------- |
| Add Explorer/Detail Page | `.cursor/skills/add-explorer-page/SKILL.md` | Adding a new explorer list or detail route/page |
| Add Write-Side Interaction | `.cursor/skills/add-interaction/SKILL.md` | Implementing write actions (submit, vote, transfer) |
| Capability Layer | `.cursor/skills/capability-layer/SKILL.md` | Adding/changing data fetching, composite page APIs, new DTOs, GraphQL |
| Effect-Capability Refactor | `.cursor/skills/effect-capability-refactor/SKILL.md` | Narrowing MonadAff/MonadEffect to intent capabilities |
| Implementation Workflow | `.cursor/skills/implementation-workflow/SKILL.md` | Design-first capabilities, stub-first development, coherent mocks |
| Post-Plan Review | `.cursor/skills/post-plan-review/SKILL.md` | Post-task refactoring/deduplication review before marking done |

## Commit Conventions

- Conventional commits when focused: `<type>(<scope>): <short summary>`. Descriptive sentence-style acceptable for broad changes.
- Types: `feat`, `fix`, `docs`, `chore`, `refactor`.
- Scope inferred from paths: `src/Components/Explorer/*` → `explorer`, `src/Capabilities/*` → `capability`, `bff/*` → `bff`, etc.
- Rules: <= 72 chars, imperative mood, capitalize first letter, no trailing period.
- Pre-commit: if diff includes `.purs` files, `npm run check-formatting` and `spago build --json-errors` should pass.
- For user-facing changes, add entry in `CHANGELOG.md` (Keep a Changelog format) — start one when you have your first user-facing release.
