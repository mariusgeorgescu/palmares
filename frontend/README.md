# Testatum — frontend

The interface and the BFF for **Testatum**, a governance track-record registry on Cardano. PureScript
0.15.16 + Halogen 7, Tailwind v4 + daisyUI 5 (theme `dim`), bundled by Vite, served together with a
Fastify BFF that proxies both backend APIs from one origin.

Deployed at [gov.cardano.vip](https://gov.cardano.vip). The repository root holds the backend; this
directory is self-contained apart from the APIs it reads.

## What is in here

Nineteen explorer screens — the governance read surface (DReps, proposals, votes, SPOs, the
committee, treasury withdrawals, delegations, activity) and the registry itself (profiles, vouches,
challenges, with a detail page for each). Nine write flows behind a wallet gate, each one showing
what the transaction does, decoded from the transaction rather than echoed from the form. A Cytoscape
delegation graph and an embeddable card.

Two bundles from one source tree: `Main` (real HTTP, `AppM`) and `MainDemo` (recorded fixtures,
`DemoM`). The second is what the Playwright fixture suite runs against, which is why the mocks
honour their filter arguments — a mock that ignores them makes that suite blind to a filter that
never reaches the API, and exactly that defect once shipped.

## Running it

```sh
npm install
npx spago install

npm run dev            # MainDemo on vite dev — recorded fixtures, no backend needed
npm run test           # 201 PureScript unit tests
npm run test:e2e       # builds the demo bundle, runs 76 Playwright tests against it
```

Against real APIs you need the BFF, and it is **fail-closed**: it refuses to start without every
variable, rather than silently proxying nowhere.

```sh
npm run build:prod
PALMARES_QUERY_API_URL=http://127.0.0.1:8083 \
PALMARES_INTERACTION_API_URL=http://127.0.0.1:8082 \
PALMARES_INTERACTION_API_USER=<operator> \
PALMARES_INTERACTION_API_PASS=<secret> \
PORT=4176 node bff/server.js
```

The write routes sit behind HTTP Basic that the operator issues; those credentials live in the BFF,
server-side, and never reach the bundle. The BFF forwards only the calls the interface makes — see
the allowlist in `bff/config.js` and why it exists.

No backend at hand? The deployed read API answers from any origin, so a local production bundle can
read it directly:

```sh
VITE_PALMARES_QUERY_BASE_URL=https://gov.cardano.vip/api/query npm run build:prod
npx vite preview --port 4178
```

That is how the screens were last verified against real data without a local chain.

## Layout

| Path | What |
| --- | --- |
| `src/Components/Explorer/` | the nineteen screens |
| `src/Components/Write/` | the nine flows, the wallet gate, the signing summary |
| `src/Components/Shared/` | `Pager`, `OnchainId`, `StatusChip`, `DRepIdentity`, `MetricInfo`, `Anchor` |
| `src/Capabilities/Query/Gov/` | `MonadQueryGov` (the class), `Default` (HTTP), `Mock` + `Fixtures` (demo), `Types` (decoders) |
| `src/Capabilities/Interaction/` | the write capability: flow paths, request bodies, oracle status |
| `src/Capabilities/Wallet/` | the CIP-30/CIP-95 gate |
| `src/Route.purs`, `src/Route/` | routes, their codec, and the one place URLs are built |
| `bff/` | the Fastify server, its service config and the proxy allowlist |
| `e2e/`, `e2e-live/`, `e2e-wallet/`, `test/` | the four suites — see `e2e-wallet/README.md` for the two gates |

## The documents that matter

- [`CLAUDE.md`](./CLAUDE.md) — the architecture, and the traps this repository has actually hit
- [`e2e-wallet/README.md`](./e2e-wallet/README.md) — the wallet suite, its gates, and what it cannot cover
- `../docs/usecases/api-screen-map.md` — the wire contract, API route by API route
- `../docs/audit/README.md` §3 and `../docs/audit/08-multi-perspective-review-2026-10-29.md` — the current backlog
