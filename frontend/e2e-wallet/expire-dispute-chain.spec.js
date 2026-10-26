// `expire-dispute`: ultimul flux care se poate închide fără o cheie, și singurul care așteaptă o
// DATĂ în loc de o decizie.
//
// **TRIMITE O TRANZACȚIE REALĂ.** Cere `PALMARES_FLOWS_SUBMIT=1`, ca restul trimiterilor.
//
// Nu cere nicio autoritate, și asta e intenția: ruta o spune pe față — *„needs no authority at all
// — that is the point, since an exit the oracle admin can gate is not an exit"*. Cere în schimb ca
// termenul disputei să fi trecut: `dispute_timeout_ms` e 2.592.000.000 ms, adică 30 de zile de la
// deschidere. Disputa deschisă pe 2026-10-25 devine expirabilă pe **2026-11-24**.
//
// __De ce există fișierul deși nu poate trece încă.__ Am argumentat o dată că un test care nu poate
// trece decât peste o lună „se strică în tăcere până atunci" — și era inconsecvent, fiindcă
// `m2-1-chain.spec.js` trăia deja exact așa, sărit implicit, de zile întregi. Un test sărit e
// vizibil în raport, poate fi citit și revizuit azi, și rulează într-o comandă în ziua în care are
// ce face. Unul nescris nu e niciunul din lucrurile astea.
//
// Testul verifică ÎNTÂI că disputa e chiar expirabilă și se oprește cu un mesaj care spune data,
// nu cu un eșec obscur: rulat prea devreme, trebuie să explice de ce, nu să pară rupt.
import { expect, test } from 'cip30-test-wallet/playwright';

const SUBMIT = process.env.PALMARES_FLOWS_SUBMIT === '1';
const WALLET = 'palmaresFlows';

test.describe.configure({ timeout: 30 * 60 * 1000 });
const PROJECTION_WAIT = 15 * 60 * 1000;

test.use({
  walletOptions: {
    name: WALLET,
    networkId: 0,
    ledger: { chain: { provider: 'koios', network: 'preprod' } },
  },
});

test.describe('expire-dispute, on chain from the browser', () => {
  test.skip(
    !SUBMIT,
    'SUBMITS A REAL TRANSACTION, and only works once a dispute is past its 30-day deadline.\n' +
      '  PALMARES_WALLET_URL=https://gov.cardano.vip PALMARES_FLOWS_SUBMIT=1 \\\n' +
      '    npx playwright test --config playwright.wallet.config.js ' +
      'e2e-wallet/expire-dispute-chain.spec.js\n' +
      'Needs no key and no authority — that is the point of the flow. The dispute opened on ' +
      '2026-10-25 becomes expirable on 2026-11-24.'
  );

  const withCip142 = async (page) => {
    await page.addInitScript((walletName) => {
      const install = () => {
        const w = window.cardano?.[walletName];
        if (!w || w.__cip142Patched) return false;
        w.__cip142Patched = true;
        const original = w.enable.bind(w);
        w.enable = async (opts) => {
          const api = await original(opts);
          api.cip142 = { getNetworkMagic: async () => 1 };
          return api;
        };
        w.supportedExtensions = [...(w.supportedExtensions ?? []), { cip: 142 }];
        return true;
      };
      if (!install()) {
        const t = setInterval(() => {
          if (install()) clearInterval(t);
        }, 25);
      }
    }, WALLET);
  };

  const awaitProjection = async (page, what, url, locatorOf) => {
    const started = Date.now();
    const deadline = started + PROJECTION_WAIT;
    for (;;) {
      await page.goto(url);
      try {
        await locatorOf().waitFor({ state: 'visible', timeout: 15_000 });
        console.log(`[expire] ${what} projected after ${Math.round((Date.now() - started) / 1000)}s`);
        return;
      } catch {
        if (Date.now() > deadline) {
          throw new Error(`${what} never appeared on ${url} (reloaded throughout)`);
        }
      }
    }
  };

  test('closes an undecided dispute whose deadline has passed', async ({ page, request }) => {
    // Disputa nedecisă. Dacă nu există niciuna, nu e un eșec al fluxului.
    const disputes = await (await request.get('/api/query/disputes?limit=200')).json();
    const undecidedAll = disputes.items.filter((d) => !d.verdict);
    test.skip(!undecidedAll.length, 'No undecided dispute to expire. Open one first (open-dispute).');

    // ÎNAINTE de orice: CARE dintre ele e expirabilă? Serverul e singura autoritate pe întrebarea
    // asta, iar refuzul lui numește exact motivul.
    //
    // Se întreabă despre FIECARE dispută nedecisă, nu doar despre prima. Varianta de dinainte lua
    // `items.find(...)`, adică presupunea o ordonare — iar cu două dispute nedecise cu termene
    // diferite presupunerea aia alege greșit și testul se sare degeaba. E aceeași familie de defect
    // ca `nth(1)` pe dock: o ordine presupusă în loc de o proprietate verificată.
    // Adrese REALE în sondă, altfel serverul se oprește la validarea formei și nu ajunge niciodată
    // să se uite la termen — iar testul ar cădea obscur în loc să spună data. Măsurat: cu adrese
    // goale răspunsul nu conține `DisputeNotStaleYet`, deci garda nu se declanșa.
    const probeAddr =
      '009493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e' +
      '32c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dc';
    let undecided = null;
    let lastRefusal = '';
    for (const d of undecidedAll) {
      const probe = await request.post('/api/interaction/expire-dispute', {
        data: {
          dispute_id: d.id,
          user_addresses: { usedAddresses: [probeAddr], changeAddress: probeAddr },
        },
        failOnStatusCode: false,
      });
      const text = await probe.text();
      if (!text.includes('DisputeNotStaleYet')) {
        undecided = d;
        break;
      }
      lastRefusal = text.slice(0, 160);
    }

    test.skip(
      !undecided,
      `None of the ${undecidedAll.length} undecided dispute(s) is past its deadline yet. ` +
        `The server says: ${lastRefusal}`
    );

    await withCip142(page);
    await page.goto(`/write?flow=expire-dispute&subject=${encodeURIComponent(undecided.id)}`);
    await page.getByRole('button', { name: `Connect ${WALLET}` }).click();
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    await page.getByLabel('Dispute', { exact: false }).first().fill(undecided.id);

    await page.getByRole('button', { name: /Build the transaction/ }).click();
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 180_000 });
    await expect(page.getByText(/Pays a network fee of/)).toBeVisible();

    await page.getByRole('button', { name: /Sign and submit/ }).click();
    await expect(
      page.getByText('Submitted. The node has it; it is not in a block yet.')
    ).toBeVisible({ timeout: 180_000 });

    // Id-ul se citeste din CHIPUL de identificator, nu dintr-un `<code>`.
    //
    // Regresie proprie: cardul de trimitere arata id-ul intr-un `<code class="font-mono">` pana cand
    // chipul l-a inlocuit, iar `data-copy` poarta acum valoarea INTREAGA — ceea ce e si mai bun,
    // fiindca textul vizibil poate fi scurtat.
    //
    // A costat exact ce trebuia sa coste: testul a picat DUPA ce tranzactia plecase deja pe lant.
    // Un test care raporteaza esec pentru o operatie ireversibila reusita e felul de defect care
    // face pe cineva s-o repete.
    const txId = await page.locator('[data-copy]').last().getAttribute('data-copy');
    expect(txId).toMatch(/^[0-9a-f]{64}$/);
    console.log(`[expire] submitted: ${txId}`);

    // Criteriul: rândul arată `expired`. Nu `upheld` și nu `dismissed` — o expirare NU e o
    // constatare împotriva niciuneia dintre părți, iar registrul trebuie s-o spună ca atare.
    const row = () =>
      page.getByRole('row', { name: new RegExp(undecided.name || undecided.id.slice(-12)) });
    await awaitProjection(page, 'expiry', '/disputes', () => row().getByText('expired'));

    console.log(`[expire] DONE dispute=${undecided.id} tx=${txId}`);
  });
});
