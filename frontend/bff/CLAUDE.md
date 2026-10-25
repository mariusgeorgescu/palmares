# BFF (Backend For Frontend) Conventions

## Role

Serves static frontend from `../dist`; proxies `/api/{service-name}/*` to backend services; injects auth (Basic or API Key). Frontend never receives or sends credentials.

## Config

- Services defined in `config.js` via exported `services` object. Each entry: `target` (backend URL) and either `username`/`password` (Basic Auth) or `apiKey`. All values from environment variables.
- Use `getEnv` / `requireEnv` for env access; mask secrets in logs (e.g. `maskValue`).

## Server Setup

- Register proxy routes for each service **before** `@fastify/static`, so `/api/*` is handled by proxy.
- Proxy options: `prefix: "/api/${serviceName}"`, `rewritePrefix: '/'`; inject auth in `rewriteRequestHeaders`. Strip `WWW-Authenticate` in `onSend`.
- SPA fallback: 404 handler serves `dist/index.html` for non-API routes; return 404 JSON for `/api/*` misses.

## Frontend Contract

- Frontend uses base URL `/api/<service-name>` (template ships `/api/api`). Paths appended in code are sent as-is to the backend after prefix rewrite.
- Adding a new service: add to `config.js` and, if needed, a new base URL in frontend Env/capability.
