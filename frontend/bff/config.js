/**
 * Configuration for BFF services
 * Each service has its own target URL and authentication credentials.
 * All values come from environment variables.
 */

// Mask sensitive values for logging
function maskValue(value, showLength = true) {
  if (!value) return '(empty)';
  if (value.length <= 4) return '****';
  return showLength
    ? `${value.substring(0, 2)}${'*'.repeat(Math.min(value.length - 4, 20))}${value.substring(value.length - 2)} (length: ${value.length})`
    : '****';
}

// Read an env var or hard-fail if missing.
//
// The template's `getEnv(name, default)` is deliberately gone, and so are its 'cardano'/'lovelace'
// defaults. Testatum is fail-closed everywhere else — compose.yaml uses `${VAR:?}` for every
// password and interaction-api `die`s on an unset BASIC_USER — and .env.example records why: a
// placeholder that happens to be a real default somewhere is how `devonly` ended up authorising
// production-shaped boots. A BFF that silently proxies to localhost with guessed credentials is the
// same defect wearing a different hat.
function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`ERROR: Required environment variable ${name} is not set`);
    process.exit(1);
  }
  return value;
}

// Pragurile de debit au valori implicite, și NU trec prin `requireEnv`: un BFF care refuză să
// pornească fără ele ar face limitarea o condiție de disponibilitate, adică exact invers. Un număr
// neplauzibil (zero, negativ, text) e tratat ca „nesetat" — altfel o greșeală de tastare ar putea
// închide API-ul pentru toți.
function rateFromEnv(name, fallback) {
  const raw = process.env[name];
  const n = raw === undefined ? NaN : Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

export const rateLimits = {
  // Generos pentru un om: o încărcare de ecran face între două și șase cereri, iar graful face mai
  // multe. Strâns pentru un scraper, care face mii.
  perClient: rateFromEnv('PALMARES_RATE_LIMIT_PER_CLIENT', 240),
  global: rateFromEnv('PALMARES_RATE_LIMIT_GLOBAL', 1200),
};

const envVars = {
  PALMARES_QUERY_API_URL: requireEnv('PALMARES_QUERY_API_URL'),
  PALMARES_INTERACTION_API_URL: requireEnv('PALMARES_INTERACTION_API_URL'),
  PALMARES_INTERACTION_API_USER: requireEnv('PALMARES_INTERACTION_API_USER'),
  PALMARES_INTERACTION_API_PASS: requireEnv('PALMARES_INTERACTION_API_PASS'),
};

console.log('\n=== Environment Variables (Debug) ===');
for (const [key, value] of Object.entries(envVars)) {
  if (key.toLowerCase().includes('key') || key.toLowerCase().includes('pass') || key.toLowerCase().includes('secret')) {
    console.log(`${key}: ${maskValue(value)}`);
  } else {
    console.log(`${key}: ${value || '(not set)'}`);
  }
}
console.log('=====================================\n');

/**
 * Service definitions — the BFF proxies each entry at /api/<key>/*
 *
 * Basic Auth:
 *   'my-service': {
 *     target: envVars.MY_SERVICE_URL,
 *     username: envVars.MY_SERVICE_USER,
 *     password: envVars.MY_SERVICE_PASS,
 *   }
 *
 * API Key:
 *   'external-api': {
 *     target: envVars.EXTERNAL_API_URL,
 *     apiKey: envVars.EXTERNAL_API_KEY,
 *   }
 *
 * No auth (e.g. IPFS gateway):
 *   'ipfs-gateway': {
 *     target: envVars.IPFS_GATEWAY_URL,
 *     noAuth: true,
 *   }
 *
 * Streaming (SSE) — disables proxy timeouts:
 *   'chatbot': {
 *     target: envVars.CHATBOT_URL,
 *     noAuth: true,
 *     streaming: true,
 *   }
 */
export const services = {
  // query-api is public by a documented boot contract: it has no auth context at all
  // (QueryAppMonad.hs:14 — "query-api is public (rate limiting is the BFF's job)"). Sending it an
  // Authorization header would be noise, so `noAuth` is the accurate description, not a shortcut.
  query: {
    target: envVars.PALMARES_QUERY_API_URL,
    noAuth: true,
  },
  // interaction-api sits behind servant `BasicAuth "user-realm"` on all twelve write routes. The
  // credentials live here, server-side, and never reach the bundle. server.js strips the client's
  // own Authorization header before substituting this one, and deletes WWW-Authenticate from every
  // response, so a 401 can never pop the browser's native credential dialog.
  interaction: {
    target: envVars.PALMARES_INTERACTION_API_URL,
    username: envVars.PALMARES_INTERACTION_API_USER,
    password: envVars.PALMARES_INTERACTION_API_PASS,
    // Lista albă, și de ce există. Credențiala de mai sus se atașează la ORICE intră pe prefix,
    // ceea ce era intenționat — altfel SPA-ul din browser n-ar putea chema API-ul deloc — dar
    // efectul secundar era că poarta `BasicAuth` a interaction-api devenea decorativă: măsurat pe
    // deploy, `GET /api/interaction/tx-status/0000…` răspundea 200 fără nicio credențială, iar
    // `submit-tx` era la fel de deschis.
    //
    // Deci poarta e acum exact atât cât are nevoie SPA-ul, nu mai mult: cele nouă fluxuri plus
    // `submit-tx` pe POST, `/status` și `/tx-status/{txId}` pe GET. Lista e derivată din
    // `Capabilities/Interaction/{Types,Default}.purs` — dacă se adaugă un flux acolo, se adaugă și
    // aici, altfel formularul primește 403 de la propriul BFF.
    allow: [
      { method: 'GET', path: '/status' },
      { method: 'GET', prefix: '/tx-status/' },
      { method: 'POST', path: '/submit-tx' },
      { method: 'POST', path: '/claim-profile' },
      { method: 'POST', path: '/update-profile' },
      { method: 'POST', path: '/issue-attestation' },
      { method: 'POST', path: '/accept-attestation' },
      { method: 'POST', path: '/open-dispute' },
      { method: 'POST', path: '/resolve-dispute' },
      { method: 'POST', path: '/expire-dispute' },
      { method: 'POST', path: '/claim-credential' },
      { method: 'POST', path: '/withdraw-credential' },
    ],
  },
};
