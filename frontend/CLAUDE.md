# Testatum frontend — project guide

Testatum is a governance track-record registry on Cardano. This directory holds its interface and
the BFF in front of it; the backend is at the repository root. See [README.md](./README.md) for what
the screens are and how to run them.

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

### The read capability: `MonadQueryGov`
- Type class in `Capabilities.Query.Gov.MonadQueryGov`. Decoders in `Capabilities.Query.Gov.Types`. Results as `Either ApiError a`.
- `Capabilities.Query.Gov.Default` is the HTTP instance (takes env, calls query-api); `Mock` is the demo instance over `Fixtures`.
- Production: `AppM` delegates to `Default`. Demo and the Playwright fixture suite: `DemoM` uses `Mock`. `npm run dev` builds `MainDemo`.
- Query env: `HasGovEnv r = ( queryBaseUrl :: String | r )` in `Capabilities.Query.Gov.Env`. `AppEnv.Env` satisfies it.
- Adding a route means five touches: the class, `Default`, `Mock`, a fixture, and the two instances. If that feels heavy for one route, it is — but every one of the five is what makes the demo bundle real.
- **The mocks honour their filter arguments.** They used not to, and that made the fixture suite — the only suite that renders a screen — structurally unable to see a filter that never reaches the API. Keep them honest when you add one.

### The write capability: `MonadInteract`
- `Capabilities.Interaction.Types` holds the nine flow paths, the request bodies, and the oracle status. `flowPath` is written literally, not derived from constructor names, so renaming a type cannot silently move a route.
- Enum values that travel on the wire must match the server exactly. `disputeVerdicts` once offered `dismissed` where the wire enum is `upheld | rejected | expired`, which made half of the only decision form unsubmittable. Check against `DomainTypes/Core/Types.hs` before you add one.

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

## Traps measured in this repository

Each of these cost a real defect. They are listed because the next person — or the next agent — will
otherwise pay for them again.

- **`parseRoute` is not on the runtime path.** `AppBase.purs` calls `mkRouter routeCodec`, so the
  router parses with the **codec**; `parseRoute` is used only by tests. A trailing-slash fix was put
  in `parseRoute`, the unit test passed, and `/profiles/` still rendered "Not found" in a browser.
  The live normalisation is `normaliseTrailingSlash` in `App.SpaLinkInterceptor`, called from `Main`.
- **A filter can reach the URL and not the request.** `RegistryFilters` has two consumers that must
  agree: the route codec, and `registryPairs` in `Route/GovQueries.purs` which builds the query
  string. A field added to one and not the other gives a correct URL, a correct page title, and an
  unfiltered response. `DRepListSpec` now pins the two against each other.
- **Importing a component into a test can drag CSL into Node.** `cardano-serialization-lib` has
  eager calls in its glue, so importing anything that reaches it makes the test runner die at
  *import* with `require is not defined in ES module scope`. Keep pure policy in modules that do not
  touch the wallet or the transaction summary — that is why `writeGate` lives in `Write.Flows`.
- **`prettier` is not this project's formatter.** `purs-tidy` is, for PureScript, and there is no
  config for anything else. Running prettier rewrites files wholesale with defaults nobody chose.
- **Say nothing the chain does not enforce.** Copy claiming a deposit is forfeited, or that a script
  credential is proved the same way a key is, was false against the validators — and false copy about
  money or about proof is the most expensive kind this product can ship. Check the validator, cite the
  trace code in the comment.
- **Select by property, never by position.** Six defects of the form `items[0]`, `.nth(1)`,
  `find (not <<< verdict)` have been found here; one of them failed *after* an irreversible
  transaction had been submitted.

## Commit Conventions

- Conventional commits when focused: `<type>(<scope>): <short summary>`. Descriptive sentence-style acceptable for broad changes.
- Types: `feat`, `fix`, `docs`, `chore`, `refactor`.
- Scope inferred from paths: `src/Components/Explorer/*` → `explorer`, `src/Capabilities/*` → `capability`, `bff/*` → `bff`, etc.
- Subject lines in this repository run long — 90 to 110 characters is normal — because the subject states what changed and the body says why it was wrong. Follow the practice, not a character count.
- Bodies are in Romanian and explain the reasoning, the measurement, and what was deliberately not done. A commit that only restates the diff is a commit nobody will read twice.
- Pre-commit: if diff includes `.purs` files, `npm run check-formatting` and `spago build --json-errors` should pass.
- For user-facing changes, add entry in `CHANGELOG.md` (Keep a Changelog format) — start one when you have your first user-facing release.
