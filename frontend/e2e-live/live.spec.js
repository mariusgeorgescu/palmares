// E2E împotriva DEPLOYULUI, nu a fixturilor: `npm run e2e:live`.
//
// Suita din `e2e/` rulează pe bundle-ul demo și poate asserta cifre exacte, pentru că payload-urile
// sunt înregistrate. Aici nu se poate asserta nicio cifră: datele sunt vii și, cât timp db-sync
// reface istoria, cele mai multe ecrane sunt goale. Ce se verifică sunt invariantele integrării —
// lucrurile care trebuie să fie adevărate indiferent câte DRep-uri are lanțul:
//
//   * pagina se servește și SPA-ul pornește pe ruta cerută direct (nu pe dashboard);
//   * `/api/query` trece prin BFF ÎN ACELAȘI ORIGIN, deci fără CORS;
//   * cele opt headere de prospețime ajung la browser — motivul pentru care există BFF-ul;
//   * nimic nu derulează lateral pe un ecran de telefon;
//   * metodologia, singurul ecran care nu depinde de starea lanțului, se umple din API-ul viu.
//
// `PALMARES_LIVE_URL` schimbă ținta; implicit e preprod-ul public.
import { expect, test } from '@playwright/test';

const ROUTES = [
  ['/', 'Palmares — an on-chain register of who vouches for whom'],
  ['/dreps', 'DReps — Palmares'],
  ['/gov-actions', 'Governance actions — Palmares'],
  ['/votes', 'Votes — Palmares'],
  ['/spos', 'Stake pool operators — Palmares'],
  ['/committee', 'Constitutional committee — Palmares'],
  ['/treasury', 'Treasury withdrawals — Palmares'],
  ['/delegations', 'Delegations — Palmares'],
  ['/activity', 'Activity — Palmares'],
  ['/profiles', 'Profiles — Palmares'],
  ['/attestations', 'Vouches — Palmares'],
  ['/disputes', 'Challenges — Palmares'],
  ['/graph', 'Delegation graph — Palmares'],
  ['/methodology', 'Methodology — Palmares'],
];

const FRESHNESS_HEADERS = [
  'x-chain-epoch',
  'x-chain-slot',
  'x-chain-block-time',
  'x-data-lag-seconds',
  'x-data-source',
  'x-attest-slot',
  'x-attest-lag-seconds',
  'x-attest-state',
];

test.describe('the deployed site', () => {
  for (const [path, title] of ROUTES) {
    test(`${path} is served and boots on its own route`, async ({ page }) => {
      const response = await page.goto(path);
      expect(response.status()).toBe(200);
      // Titlul e per-rută, deci dovedește că routerul a citit adresa cerută. Un SPA care cade
      // înapoi pe pagina de pornire ar servi tot 200.
      //
      // E ȘI testul de ordonare: `toHaveTitle` așteaptă cinci secunde, iar titlul se pune în
      // inițializarea rădăcinii. Dacă un ecran blochează inițializarea pe cererea lui, linia asta
      // cade pe orice rută lentă — și chiar a căzut, pe `/activity`, care răspunde în 12 secunde
      // pe baza vie.
      await expect(page).toHaveTitle(title);
      await expect(page.getByRole('navigation', { name: 'Main' })).toBeVisible();
    });
  }

  test('an unknown path renders the not-found screen, not the dashboard', async ({ page }) => {
    await page.goto('/this-does-not-exist');
    await expect(page.getByRole('heading', { name: 'Not found' })).toBeVisible();
  });

  test('the API answers through the same origin, with no CORS in the way', async ({ request, baseURL }) => {
    const health = await request.get(`${baseURL}/api/query/health`);
    expect(health.status()).toBe(200);
    expect((await health.json()).service).toBe('query-api');
  });

  test('all eight freshness headers reach the browser', async ({ page }) => {
    // Anume catalogul de formule, și anume unul cu 200: middleware-ul care pune headerele e al
    // lui query-api, deci un 503 de la proxy — care e răspunsul LUI, nu al serverului — n-are de
    // unde să le aibă, iar un test care prinde prima cerere oarecare ar măsura asta.
    const seen = page.waitForResponse(
      (r) => r.url().includes('/api/query/metrics/formulas') && r.status() === 200
    );
    await page.goto('/methodology');
    const headers = (await seen).headers();
    for (const h of FRESHNESS_HEADERS) {
      expect(headers, `missing ${h}`).toHaveProperty(h);
    }
  });

  test('the methodology screen fills from the live API', async ({ page }) => {
    // Singurul ecran cu conținut garantat: formulele sunt un catalog static al serverului, nu
    // ceva ce db-sync trebuie să ajungă din urmă.
    await page.goto('/methodology');
    await expect(page.getByText(/published formulas?\./)).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Participation rate' })).toBeVisible();
  });

  // Calea de scriere, pe deploy. A existat în cod cu mult înainte să existe în cluster: pod-ul era
  // la `replicas: 0`, deci `/write` arăta formularul și cădea pe butonul de construire. Testele de
  // aici afirmă exact ce lipsea — că e un server adevărat în spate, cu providerul și scripturile
  // lui, nu doar un ecran.
  test('the write API is actually there, on the provider it claims', async ({ request, baseURL }) => {
    const res = await request.get(`${baseURL}/api/interaction/status`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.network).toBe('preprod');
    // `node + Kupo`, nu `ogmios + kupo`: alegerea e măsurată, iar un provider schimbat pe furiș e
    // exact lucrul care rupe construirea fără să schimbe niciun ecran.
    expect(body.provider).toBe('node-kupo');
    // Cele cinci scripturi de referință se rezolvă. Fără ele nicio tranzacție nu se poate construi,
    // iar răspunsul ar fi un 200 care arată sănătos.
    expect(body.deployed_scripts).toBe(true);
    expect(typeof body.oracle_paused).toBe('boolean');
    expect(body.oracle.min_utxo_lovelace).toBeGreaterThan(0);
  });

  test('the write screen asks for a wallet before it shows a form', async ({ page }) => {
    await page.goto('/write?flow=claim-profile');
    // Poarta întâi: niciun cîmp pînă nu se știe ce portofel și ce rețea.
    await expect(page.getByRole('textbox')).toHaveCount(0);
    // Textul ANUME, nu `/wallet/i`: biblioteca de dApp ține în pagină un card ascuns („You do not
    // have any wallet installed yet !") pe care un regex larg îl prinde primul, și un test care
    // afirmă ceva ascuns nu afirmă nimic.
    await expect(page.getByText('No Cardano wallet is installed in this browser.')).toBeVisible();
    await expect(page.getByText('Connect a wallet that can write here, and this form appears.'))
      .toBeVisible();
    // Și cele nouă fluxuri sînt acolo, fără portofel: ce POȚI scrie aici se citește înainte de a
    // conecta ceva.
    await expect(page.getByText('The nine things this registry lets you write', { exact: false }))
      .toBeVisible();
    // Și nu „nu se poate scrie acum": oracolul răspunde, deci ecranul nu trebuie să fie blocat pe
    // necunoscut. Asta e ce s-ar vedea dacă interaction-api ar fi iar la zero replici.
    await expect(page.getByText(/cannot tell whether this protocol is paused/)).toHaveCount(0);
  });

  // Simptomul pe care îl vede un om, și cauza lui.
  //
  // Ecranul `/votes` scria „No votes have been recorded yet." pe un lanț cu 3.243.997 de voturi.
  // Nu era gol: ecranul cere `?is_final=true` (filtrul „Final vote only", cel implicit), iar
  // `is_final` e un semi-join pe matview-ul `palmares.vote_partition` — care avea ZERO rânduri,
  // fiindcă bucla de refresh cădea la fiecare tick. `REFRESH MATERIALIZED VIEW CONCURRENTLY`
  // construiește conținutul nou într-o tabelă TEMPORARY, iar `palmares_owner` nu avea dreptul:
  // `REVOKE ALL ON DATABASE ... FROM PUBLIC` din `sql/050_roles.sql` îl luase. `drep_metrics` se
  // reîmprospătează PRIMUL și eșecul scurtcircuitează restul, deci o singură permisiune lipsă
  // golea ambele matview-uri.
  //
  // Testul afirmă relația, nu un număr: dacă există voturi, filtrul implicit nu poate întoarce
  // zero. Un prag fix ar fi expirat odată cu lanțul.
  test('the default votes filter is not empty while votes exist', async ({ request, baseURL }) => {
    const all = await (await request.get(`${baseURL}/api/query/votes?limit=1`)).json();
    if (all.total === 0) {
      test.skip(true, 'No votes on this chain yet — nothing for the filter to lose.');
    }
    const final = await (await request.get(`${baseURL}/api/query/votes?is_final=true&limit=1`)).json();
    expect(
      final.total,
      `${all.total} votes exist but the default filter returns ${final.total}: ` +
        'palmares.vote_partition is probably empty, which means the matview refresh is failing.'
    ).toBeGreaterThan(0);
    // Și e un SUBSET: un vot final per (rol, votant, acțiune), deci strict mai puțin decât tot.
    expect(final.total).toBeLessThanOrEqual(all.total);
  });

  test('the metrics have been computed at least once', async ({ request, baseURL }) => {
    // `metrics_as_of_epoch: null` e cealaltă față a aceluiași defect, și singurul loc din API care
    // spune „matview-urile nu s-au reîmprospătat niciodată".
    const st = await (await request.get(`${baseURL}/api/query/status`)).json();
    expect(st.metrics_as_of_epoch, 'null means the drep_metrics refresh has never succeeded')
      .not.toBeNull();
  });

  test.describe('at phone width', () => {
    test.use({ viewport: { width: 390, height: 844 } });
    for (const [path] of ROUTES) {
      test(`${path} does not scroll sideways`, async ({ page }) => {
        // `domcontentloaded`, NU `networkidle`: pe baza vie `/activity` răspunde în peste cinci
        // minute (măsurat 2026-10-25, vezi nota din README), iar `networkidle` nu se așază cît
        // timp cererea e în zbor — testul expira pe latența serverului, nu pe derulare. Ce se
        // măsoară aici e cadrul paginii, iar el e desenat înainte de date; tabelul plin e acoperit
        // de suita pe fixturi.
        await page.goto(path, { waitUntil: 'domcontentloaded' });
        await page.getByRole('navigation', { name: 'Main' }).waitFor();
        const overflow = await page.evaluate(() => {
          const e = document.scrollingElement;
          return e.scrollWidth - e.clientWidth;
        });
        expect(overflow).toBeLessThanOrEqual(1);
      });
    }
  });
});
