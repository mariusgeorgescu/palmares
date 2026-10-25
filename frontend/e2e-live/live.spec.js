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
  ['/', 'Palmares — Cardano governance track record'],
  ['/dreps', 'DReps — Palmares'],
  ['/gov-actions', 'Governance actions — Palmares'],
  ['/votes', 'Votes — Palmares'],
  ['/spos', 'Stake pool operators — Palmares'],
  ['/committee', 'Constitutional committee — Palmares'],
  ['/treasury', 'Treasury withdrawals — Palmares'],
  ['/delegations', 'Delegations — Palmares'],
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

  test.describe('at phone width', () => {
    test.use({ viewport: { width: 390, height: 844 } });
    for (const [path] of ROUTES) {
      test(`${path} does not scroll sideways`, async ({ page }) => {
        await page.goto(path);
        await page.waitForLoadState('networkidle');
        const overflow = await page.evaluate(() => {
          const e = document.scrollingElement;
          return e.scrollWidth - e.clientWidth;
        });
        expect(overflow).toBeLessThanOrEqual(1);
      });
    }
  });
});
