import Fastify from 'fastify';
import proxy from '@fastify/http-proxy';
import staticFiles from '@fastify/static';
import { readFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { rateLimits, services } from './config.js';
import { registerRateLimit } from './ratelimit.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const fastify = Fastify({
  logger: true
});

// Register CORS plugin to allow requests from frontend
await fastify.register(import('@fastify/cors'), {
  origin: true,
  credentials: true
});

// Limitarea debitului, înaintea oricărui proxy: ce apără e baza din spate, nu BFF-ul.
registerRateLimit(fastify, rateLimits);

/**
 * Create Basic Auth header from username and password
 */
function createBasicAuthHeader(username, password) {
  const credentials = Buffer.from(`${username}:${password}`).toString('base64');
  return `Basic ${credentials}`;
}

// Add hook to log ALL incoming requests for debugging
fastify.addHook('onRequest', async (request, reply) => {
  fastify.log.info(`[Request] ${request.method} ${request.url} from ${request.ip}`);
  if (request.url.startsWith('/api/')) {
    fastify.log.info(`[API Request] ${request.method} ${request.url} from ${request.ip} - Should be handled by proxy`);
  }
});

// Add global hook to remove WWW-Authenticate header from all proxy responses
fastify.addHook('onSend', async (request, reply, payload) => {
  if (request.url.startsWith('/api/')) {
    const wwwAuth = reply.getHeader('www-authenticate');
    if (wwwAuth) {
      reply.removeHeader('www-authenticate');
      fastify.log.info(`Removed WWW-Authenticate header from response for ${request.url}`);
    }
    fastify.log.info(`[Proxy Response] ${request.method} ${request.url} -> Status: ${reply.statusCode}`);
  }
  return payload;
});

// Add hook to log errors
fastify.addHook('onError', async (request, reply, error) => {
  if (request.url && request.url.startsWith('/api/')) {
    fastify.log.error(`[Proxy Error Hook] ${request.method} ${request.url}: ${error.message}`);
    fastify.log.error(`[Proxy Error Hook] Code: ${error.code}, Name: ${error.name}`);
  }
});

/**
 * Register proxy routes for each service
 * IMPORTANT: Proxy must be registered BEFORE static files to avoid conflicts
 */
for (const [serviceName, serviceConfig] of Object.entries(services)) {
  const { target } = serviceConfig;
  
  // Determine authentication method
  const hasBasicAuth = serviceConfig.username && serviceConfig.password;
  const hasApiKey = serviceConfig.apiKey;
  
  if (!hasBasicAuth && !hasApiKey && !serviceConfig.noAuth) {
    fastify.log.warn(`[Proxy Config] Skipping ${serviceName} - no authentication method configured`);
    continue;
  }

  // Prepare authentication header
  let authHeader = null;
  let authHeaderName = 'Authorization';
  
  if (hasBasicAuth) {
    const { username, password } = serviceConfig;
    authHeader = createBasicAuthHeader(username, password);
  } else if (hasApiKey) {
    authHeader = serviceConfig.apiKey;
    authHeaderName = 'api-key';
  }

  // Register proxy for this service. Streaming services (SSE) disable the
  // body/overall timeouts so long-lived responses aren't guillotined mid-stream.
  const undiciConfig = {
    connectTimeout: 60000,
    headersTimeout: 60000,
    bodyTimeout: serviceConfig.streaming ? 0 : 60000,
  };

  const authMethod = hasBasicAuth ? 'Basic Auth' : hasApiKey ? 'API Key' : 'No Auth';
  fastify.log.info(`[Proxy Config] Registering ${serviceName} with ${authMethod}`);

  // Calea cerută, fără prefix și fără șirul de interogare — forma în care o compară lista albă.
  const upstreamPath = (url) => {
    const withoutPrefix = url.slice(`/api/${serviceName}`.length) || '/';
    const q = withoutPrefix.indexOf('?');
    return q === -1 ? withoutPrefix : withoutPrefix.slice(0, q);
  };

  const allow = serviceConfig.allow;
  const isAllowed = (method, path) =>
    !allow ||
    allow.some(
      (r) => r.method === method && (r.path !== undefined ? r.path === path : path.startsWith(r.prefix))
    );

  await fastify.register(proxy, {
    upstream: target,
    prefix: `/api/${serviceName}`,
    rewritePrefix: '/',
    // Refuzul se dă AICI, înainte ca `rewriteRequestHeaders` să atașeze credențiala operatorului.
    // Un serviciu fără `allow` (query-api) trece nefiltrat, fiindcă e public prin contract.
    preHandler: (request, reply, done) => {
      const path = upstreamPath(request.url);
      if (isAllowed(request.method, path)) return done();
      fastify.log.warn(`[Proxy Deny] ${request.method} /api/${serviceName}${path} is not on the allowlist`);
      reply.code(403).send({
        code: 'forbidden',
        message: `${request.method} ${path} is not proxied. This gateway forwards only the calls the interface makes.`,
      });
    },
    timeout: serviceConfig.streaming ? 0 : 60000,
    undici: undiciConfig,
    rejectUnauthorized: process.env.NODE_TLS_REJECT_UNAUTHORIZED !== '0',
    disableRequestLogging: false,
    keepAlive: true,
    errorHandler: (error, request, reply) => {
      fastify.log.error(`[Proxy Error Handler] ${request.method} ${request.url}: ${error.message}`);
      reply.code(502).send({
        error: 'Bad Gateway',
        message: error.message,
        code: error.code,
        upstream: target
      });
    },
    replyOptions: {
      rewriteRequestHeaders: (originalReq, headers) => {
        const rewrittenPath = originalReq.url.replace(`/api/${serviceName}`, '');
        fastify.log.info(`[Proxy] ${originalReq.method} ${originalReq.url} -> ${target}${rewrittenPath}`);
        
        const { authorization, 'api-key': apiKey, ...restHeaders } = headers;
        if (authHeader) {
          return { ...restHeaders, [authHeaderName]: authHeader };
        }
        return restHeaders;
      }
    }
  });

  fastify.log.info(`[Proxy Config] Registered ${serviceName} -> ${target} (${authMethod})`);
}

/**
 * Health check endpoint
 */
fastify.get('/health', async (request, reply) => {
  return { status: 'ok', services: Object.keys(services) };
});

// `/api/test` și `/test-connectivity` au fost șterse. A doua publica neautentificat numele DNS
// din cluster și porturile ambelor servicii de backend, iar prima întorcea IP-ul apelantului așa
// cum îl vede clusterul — amândouă măsurate live pe gov.cardano.vip. `/health` de mai sus răspunde
// la întrebarea pe care o are un operator și numește doar cheile serviciilor, nu țintele lor.

// Register static file serving for frontend
await fastify.register(staticFiles, {
  root: join(__dirname, '../dist'),
  prefix: '/',
  decorateReply: false
});

// SPA fallback - serve index.html for all non-API routes
fastify.setNotFoundHandler(async (request, reply) => {
  // Don't serve index.html for API routes
  if (request.url.startsWith('/api/')) {
    return reply.code(404).send({ error: 'Not found' });
  }
  // Serve index.html for SPA routes
  try {
    const indexPath = join(__dirname, '../dist/index.html');
    const indexContent = await readFile(indexPath, 'utf-8');
    return reply.type('text/html').send(indexContent);
  } catch (error) {
    fastify.log.error(`Error serving index.html: ${error.message}`);
    return reply.code(500).send({ error: 'Internal server error' });
  }
});

/**
 * Start the server
 */
const start = async () => {
  try {
    const port = process.env.PORT || process.env.BFF_PORT || 80;
    const host = process.env.BFF_HOST || '0.0.0.0';

    await fastify.listen({ port, host });
    fastify.log.info(`Server listening on http://${host}:${port}`);
    fastify.log.info(`Available services: ${Object.keys(services).join(', ') || 'none'}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();

