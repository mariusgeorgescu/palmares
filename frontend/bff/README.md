# BFF (Backend For Frontend)

A small Fastify server that:

1. **Serves** the built SPA from `../dist` (with SPA fallback to `index.html`).
2. **Proxies** `/api/<service>/*` to backend services configured in `config.js`.
3. **Injects** Basic Auth or API Key headers per service, so the browser never sees credentials.

## Running locally

```sh
# default port is 80 (needs root on macOS). Use PORT to override:
PORT=8080 node server.js
```

Or via npm scripts from the repo root:

```sh
npm run bff       # build the frontend then start the BFF
npm run bff:dev   # node --watch, no rebuild
```

## Adding a service

1. Edit `config.js`:
   ```js
   export const services = {
     api: {  // existing
       target: envVars.API_URL,
       username: envVars.API_USER,
       password: envVars.API_PASS,
     },
     ipfs: {  // new
       target: envVars.IPFS_GATEWAY_URL,
       noAuth: true,
     },
   };
   ```
2. Add the corresponding env vars to `envVars` (use `getEnv`/`requireEnv`).
3. Document them in the repo's root `.env.example`.
4. In the frontend, call the new service at `/api/ipfs/...` (path is rewritten — the prefix is stripped before hitting the backend).

## Auth modes per service

| Mode | Required fields | Header injected |
|------|-----------------|-----------------|
| Basic Auth | `username`, `password` | `Authorization: Basic <base64>` |
| API Key | `apiKey` | `api-key: <value>` |
| None | `noAuth: true` | (no auth header) |
| SSE / streaming | `streaming: true` | disables proxy timeouts |

## Env (template defaults)

| Var | Default | Used by |
|-----|---------|---------|
| `PORT` | `80` | Fastify listener |
| `BFF_HOST` | `0.0.0.0` | Fastify listener |
| `API_URL` | `http://localhost:8083` | `api` service |
| `API_USER` | `cardano` | `api` Basic Auth |
| `API_PASS` | `lovelace` | `api` Basic Auth |
