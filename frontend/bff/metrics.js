/**
 * Metrici Prometheus, pe un PORT SEPARAT.
 *
 * Separat dinadins: BFF-ul servește SPA-ul pe portul public, iar gateway-ul rutează `/` către el —
 * deci orice cale nouă de pe portul acela e publică. Volumele de trafic nu sunt un secret, dar
 * proiectul a mai șters o dată două rute operaționale (`/api/test`, `/test-connectivity`) exact
 * pentru că publicau lucruri despre cluster, iar un endpoint operațional public e o decizie pe care
 * nimeni nu trebuie s-o ia din neatenție. Prometheus din cluster ajunge la portul ăsta prin Service,
 * gateway-ul nu-l rutează.
 *
 * Trei familii, și niciuna nu poartă o cale: numărul de rute e nemărginit (identificatori în URL),
 * iar o etichetă cu cardinalitate nemărginită e felul standard în care se omoară un Prometheus.
 * Serviciul (`query`/`interaction`/`app`) e tot ce trebuie pentru a răspunde la „ce s-a rupt".
 *
 * Histogramă nu, sumă și număr da: `rate(sum)/rate(count)` dă latența medie, care e suficientă ca
 * să vezi o încetinire. O histogramă scrisă de mână ar fi cinci ori codul, pentru percentile pe
 * care nu le citește încă nimeni.
 */

import Fastify from 'fastify';

const requests = new Map(); // "service|method|status" -> count
const durations = new Map(); // "service" -> { sum, count }
const refusals = new Map(); // "scope" -> count

const bump = (map, key, by = 1) => map.set(key, (map.get(key) ?? 0) + by);

/** Din ce serviciu face parte o cerere. Fără cale, fără identificatori. */
export function serviceOf(url) {
  if (url.startsWith('/api/query')) return 'query';
  if (url.startsWith('/api/interaction')) return 'interaction';
  return 'app';
}

export function recordRequest({ url, method, statusCode, durationMs }) {
  const service = serviceOf(url);
  bump(requests, `${service}|${method}|${statusCode}`);
  const d = durations.get(service) ?? { sum: 0, count: 0 };
  durations.set(service, { sum: d.sum + durationMs / 1000, count: d.count + 1 });
}

export function recordRateLimited(scope) {
  bump(refusals, scope);
}

/** Expunerea, în formatul text al Prometheus. */
export function exposition() {
  const lines = [
    '# HELP palmares_bff_requests_total Requests served by the gateway, by service and status.',
    '# TYPE palmares_bff_requests_total counter',
  ];
  for (const [key, count] of requests) {
    const [service, method, status] = key.split('|');
    lines.push(`palmares_bff_requests_total{service="${service}",method="${method}",status="${status}"} ${count}`);
  }
  lines.push(
    '# HELP palmares_bff_request_duration_seconds Time spent serving requests, by service.',
    '# TYPE palmares_bff_request_duration_seconds summary'
  );
  for (const [service, d] of durations) {
    lines.push(`palmares_bff_request_duration_seconds_sum{service="${service}"} ${d.sum.toFixed(6)}`);
    lines.push(`palmares_bff_request_duration_seconds_count{service="${service}"} ${d.count}`);
  }
  lines.push(
    '# HELP palmares_bff_rate_limited_total Requests refused by the gateway rate limit, by which cap.',
    '# TYPE palmares_bff_rate_limited_total counter'
  );
  // Cele două praguri se publică și pe zero: o serie care apare abia la primul refuz nu se poate
  // pune într-o alertă („rate() peste o serie care nu există" nu e zero, e nimic).
  for (const scope of ['client', 'global']) {
    lines.push(`palmares_bff_rate_limited_total{scope="${scope}"} ${refusals.get(scope) ?? 0}`);
  }
  return lines.join('\n') + '\n';
}

/**
 * Pornește ascultătorul de metrici și cuplează măsurarea la instanța principală.
 *
 * Un eșec aici NU oprește BFF-ul: dacă portul e ocupat, situl trebuie să servească în continuare.
 * Metricile sunt pentru operator, iar indisponibilitatea lor nu e o indisponibilitate a produsului.
 */
export async function registerMetrics(fastify, { port }) {
  fastify.addHook('onRequest', async (request) => {
    request.metricsStart = process.hrtime.bigint();
  });
  fastify.addHook('onResponse', async (request, reply) => {
    if (request.metricsStart === undefined) return;
    const durationMs = Number(process.hrtime.bigint() - request.metricsStart) / 1e6;
    recordRequest({ url: request.url, method: request.method, statusCode: reply.statusCode, durationMs });
  });

  const app = Fastify({ logger: false });
  app.get('/metrics', async (_request, reply) => {
    reply.header('content-type', 'text/plain; version=0.0.4; charset=utf-8');
    return exposition();
  });
  try {
    await app.listen({ port, host: '0.0.0.0' });
    fastify.log.info(`[Metrics] /metrics on :${port} (separate port; the gateway does not route it)`);
  } catch (error) {
    fastify.log.warn(`[Metrics] could not listen on :${port}: ${error.message}. The site is unaffected.`);
  }
}
