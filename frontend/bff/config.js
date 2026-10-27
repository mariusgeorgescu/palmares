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
  },
};
