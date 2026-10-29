/**
 * Limitarea debitului, în fața proxy-ului.
 *
 * `query-api` spune în propria notă de design că e treaba gateway-ului, iar gateway-ul abia acum
 * există. Ce apără nu e BFF-ul — el doar mută octeți — ci baza din spate: `/activity` costă
 * secunde pe un db-sync viu, iar `/votes` numără peste trei milioane de rânduri.
 *
 * Două praguri, și al doilea nu e redundant:
 *
 *   1. **per client.** Cheia e primul salt din `x-forwarded-for`, nu adresa soclului.
 *
 *      __MĂSURAT PE DEPLOY, și rezultatul contează:__ 600 de cereri într-o rafală au produs 420 de
 *      refuzuri, deci pragul funcționează — dar cheia a fost `10.42.1.0` și `10.42.1.1`, adică
 *      adresele nodului, NU adresa clientului. Cauza e în amonte de BFF: traficul intră printr-un
 *      LoadBalancer care face SNAT, deci nici Traefik nu vede IP-ul real, iar `x-forwarded-for` fie
 *      lipsește, fie poartă tot adresa nodului.
 *
 *      Consecința, scrisă ca să nu fie descoperită la nevoie: __ca deployat, pragul ăsta e per-nod
 *      (două găleți), nu per-client__ — deci un client abuziv poate refuza serviciul celorlalți
 *      până la capătul ferestrei. Ce l-ar face per-client e `externalTrafficPolicy: Local` pe
 *      serviciul Traefik, care e infrastructură PARTAJATĂ de toate aplicațiile din cluster, deci
 *      nu se schimbă din acest repo. Până atunci pragul e generos tocmai pentru că e, de fapt, un
 *      al doilea plafon global.
 *   2. **global.** Plafonul pe care îl suportă baza, oricâți clienți ar fi. Un singur prag per
 *      client nu-l dă: zece clienți cinstiți pot depăși împreună ce un singur abuziv n-ar putea.
 *
 * Fereastră fixă, nu token bucket: o fereastră fixă greșește în favoarea clientului la margine
 * (poate trimite 2N în două secunde dacă nimerește granița), iar aici greșeala aceea e preferabilă
 * complexității — ce apărăm e o bază de date, nu o resursă scumpă per cerere.
 *
 * Fără dependență nouă: `@fastify/rate-limit` ar aduce un plugin întreg pentru patruzeci de linii.
 */

import { recordRateLimited } from './metrics.js';

const WINDOW_MS = 60_000;

/** Cheia unui client. Primul salt din XFF e cel mai apropiat de el; restul sunt proxy-uri. */
export function clientKey(request) {
  const xff = request.headers['x-forwarded-for'];
  if (typeof xff === 'string' && xff.length > 0) {
    const first = xff.split(',')[0].trim();
    if (first) return first;
  }
  return request.ip ?? 'unknown';
}

/**
 * Un contor pe fereastră fixă. `hit` întoarce ce a mai rămas, sau `null` când s-a depășit.
 */
function counter(limit) {
  const windows = new Map();

  // Măturat la fiecare fereastră: fără asta, harta crește cu fiecare client văzut vreodată, iar un
  // scraper care își schimbă IP-ul ar fi o scurgere de memorie în loc de un refuz.
  const sweep = setInterval(() => {
    const now = Date.now();
    for (const [key, w] of windows) if (w.resetAt <= now) windows.delete(key);
  }, WINDOW_MS);
  sweep.unref?.();

  return {
    hit(key) {
      const now = Date.now();
      const w = windows.get(key);
      if (!w || w.resetAt <= now) {
        windows.set(key, { count: 1, resetAt: now + WINDOW_MS });
        return { ok: true, retryAfter: 0 };
      }
      w.count += 1;
      if (w.count > limit) return { ok: false, retryAfter: Math.ceil((w.resetAt - now) / 1000) };
      return { ok: true, retryAfter: 0 };
    },
    size: () => windows.size,
  };
}

/**
 * Montează limitarea pe `/api/*`.
 *
 * NUMAI pe `/api/*`: fișierele statice sunt zeci de cereri la o încărcare de pagină și nu ating
 * baza, iar un prag care le-ar include ar rupe un refresh cu cache golit — adică exact utilizatorul
 * cinstit, și niciodată scraper-ul.
 */
export function registerRateLimit(fastify, { perClient, global: globalLimit }) {
  const byClient = counter(perClient);
  const overall = counter(globalLimit);

  fastify.addHook('onRequest', async (request, reply) => {
    if (!request.url.startsWith('/api/')) return;

    const key = clientKey(request);
    const client = byClient.hit(key);
    const all = overall.hit('*');
    const verdict = !client.ok ? { scope: 'client', retryAfter: client.retryAfter } : !all.ok ? { scope: 'global', retryAfter: all.retryAfter } : null;
    if (!verdict) return;

    // Cheia se logheaza: e singurul loc din care se vede dacă gateway-ul pune `x-forwarded-for`
    // sau dacă pragul per client s-a comportat, de fapt, global.
    fastify.log.warn(`[Rate limit] ${verdict.scope} cap hit by ${key} on ${request.method} ${request.url}`);
    recordRateLimited(verdict.scope);
    reply
      .code(429)
      .header('retry-after', String(verdict.retryAfter))
      .send({
        code: 'too_many_requests',
        message:
          verdict.scope === 'client'
            ? `More than ${perClient} API requests in a minute from this client. The data is public and the whole register is small — if you are reading it in bulk, do it slowly.`
            : `This gateway is over its overall limit of ${globalLimit} API requests a minute. Try again shortly.`,
      });
  });

  fastify.log.info(`[Rate limit] ${perClient}/min per client, ${globalLimit}/min overall, on /api/* only`);
}
