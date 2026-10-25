# Cardano dApp Frontend Template

A starting point for Cardano dApp frontends using **PureScript + Halogen**, with **CIP-30 wallet connect**, **Fastify BFF**, **Vite**, and **multi-stage Docker**. Derived from a production dApp; opinionated, not minimal.

Out of the box you get:

- The ReaderT + StoreT + RouterT architecture from [Real World Halogen](https://thomashoneyman.com/guides/real-world-halogen/).
- Path-based routing with SPA fallback.
- A worked **page-shaped capability** (`MonadQueryApi`) with `Default` (HTTP via `affjax-web`), `Mock`, and `AppM`/`DemoM` wiring.
- A working CIP-30 wallet connect via `halogen-cardano-wallet-connect-component`.
- DaisyUI + Tailwind v4 styling.
- A Fastify **BFF** that serves the SPA and proxies `/api/<service>/*` with credential injection.
- A multi-stage **Dockerfile** that ships only the BFF + built assets, plus a `docker-compose.yml` skeleton.
- Cursor `.cursor/rules` (architecture, conventions, effect-capability narrowing) and `.cursor/skills` (add-explorer-page, add-interaction, capability-layer, effect-capability-refactor, implementation-workflow, post-plan-review).

## Quickstart

```sh
git clone <this-repo> my-dapp
cd my-dapp
npm install
npx spago install
npm run dev          # vite dev on http://localhost:5173 — runs MainDemo (mocked data)
```

For the BFF locally:

```sh
PORT=8080 npm run bff   # builds, then serves dist/ + /api/* on http://localhost:8080
```

For Docker:

```sh
docker build -t cardano-dapp-frontend-template:dev .
docker compose up frontend
```

## Project layout

```
.
├── .cursor/                Halogen + project rules, skills, hooks, commands
├── bff/                    Fastify BFF (proxy + static + SPA fallback)
├── scripts/build-image.sh  Docker buildx wrapper
├── src/
│   ├── Main.purs           Production entry (AppM)
│   ├── MainDemo.purs       Demo entry (DemoM with mock data) — default bundle
│   ├── AppM.purs           RouterT + ReaderT + StoreT + Aff
│   ├── DemoM.purs          Mock interpreter
│   ├── AppEnv.purs         apiBaseUrl, allowedNetworkId
│   ├── Store.purs          walletApi, user (Connect/Disconnect actions)
│   ├── Route.purs          Home | Items | NotFound
│   ├── Route/Codec.purs    routing-duplex codec
│   ├── Capabilities/
│   │   ├── LogMessages.purs
│   │   ├── Delay.purs           MonadDelay (debounce, timeouts)
│   │   ├── DomEvent.purs        MonadDomEvent (preventDefault)
│   │   └── Query/Api/           Example page-shaped query capability
│   └── Components/
│       ├── Home.purs            Router host
│       ├── Layout/NavBar.purs   NavBar + WalletConnect slot
│       └── Explorer/Items.purs  Worked explorer page (RemoteData + debounce)
├── index.html
├── vite.config.js          Cardano-flavored Vite (libsodium fix, polyfills, wasm)
├── spago.yaml              CIP-30 stack
├── package.json
├── Dockerfile              Multi-stage (Node 23 → Alpine)
├── docker-compose.yml      Frontend service + commented backend placeholder
├── .env.example
└── CLAUDE.md               Project guide for Claude Code / Cursor
```

## Customizing for your dApp

1. **Domain types**: rename `MonadQueryApi`, `Item`, `ItemId`, `ItemsQuery`, `ItemsPage` to your domain (e.g. `MonadQueryGov`, `Proposal`, `ProposalId`, ...). The four-file pattern (`MonadQueryApi.purs`, `Types.purs`, `Default.purs`, `Mock.purs`) and the `getItemsPage` shape are the templates to copy.
2. **BFF services**: edit `bff/config.js` and add env vars to `.env.example`. The `api` service name is a placeholder — rename and add more (`ipfs`, `tx`, etc.) following the same shape.
3. **Build-time config**: when you need `VITE_*` env vars in PureScript (e.g. to switch network), add an `AppEnv.js` FFI module that reads `import.meta.env.VITE_*`.
4. **Image names**: search-and-replace `your-org/cardano-dapp-frontend` across `Dockerfile`, `docker-compose.yml`, `scripts/build-image.sh`, and the `deploy-dev`/`deploy-prod` scripts in `package.json`.
5. **Production bundle**: `npm run build:prod` bundles `Main` (AppM with real HTTP) instead of `MainDemo`.
6. **Tailwind theme**: edit `data-theme="dim"` in `index.html` and `src/style.css` — DaisyUI ships many themes.

## Conventions

See [CLAUDE.md](./CLAUDE.md) for the full project guide and `.cursor/rules/` for the granular architecture rules used by Cursor and Claude Code.
