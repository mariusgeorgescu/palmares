// Verificare de unică folosință: abonamentul la `refreshKey` chiar declanșează o reinterogare?
// Singura schimbare de `Store` pe care o pot provoca dintr-un browser fără lanț e conectarea unui
// wallet — deci testul numără cererile către `/api/query/profiles` în jurul ei. Cu selectorul
// mutat pe tot `Store`-ul trebuie să crească; cu `selectEq _.refreshKey` (cel real) trebuie să NU
// crească, fiindcă o conectare nu e o scriere confirmată.
import { expect, test } from 'cip30-test-wallet/playwright';
import { connectFromNavbar } from '../e2e-wallet/connect.js';

const WALLET = 'refreshProbe';
test.use({ walletOptions: { name: WALLET, networkId: 0 } });

test('a store change reaches the list component', async ({ page }) => {
  const hits = [];
  page.on('request', (r) => {
    if (r.url().includes('/api/query/profiles')) hits.push(r.url());
  });

  await page.goto('/profiles');
  await expect.poll(() => hits.length, { timeout: 15_000 }).toBeGreaterThan(0);
  const before = hits.length;

  await connectFromNavbar(page, WALLET);
  await page.waitForTimeout(2500);

  console.log(`REQUESTS before=${before} after=${hits.length}`);
});
