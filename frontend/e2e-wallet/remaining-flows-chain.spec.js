// Cele patru fluxuri rămase, trimise pe preprod din browser.
//
// **TRIMITE TRANZACȚII REALE.** Cere `PALMARES_FLOWS_SUBMIT=1`, un nume care nu înseamnă altceva
// decât „ai voie să trimiți" și care nu se pune din greșeală. Ordinea nu e arbitrară:
//
//   1. `update-profile`      — independent
//   2. `claim-credential`    — cere un profil deținut și o cheie DRep CIP-95
//   3. `withdraw-credential` — cere revendicarea de la pasul 2 PROIECTATĂ, nu doar trimisă
//   4. `open-dispute`        — blochează 5 tADA până la o decizie; termenul e 30 de zile
//
// Împreună cu cele trei din M2-1, asta face **șapte din nouă** pe lanț. Ultimele două nu se pot
// încheia dintr-un browser obișnuit azi, și amândouă prin design:
//
//   * `resolve-dispute` întoarce deliberat o tranzacție NESEMNATĂ — validatorul oracolului cere
//     semnătura adminului, iar „no admin action is accepted over HTTP";
//   * `expire-dispute` nu cere nicio autoritate, dar cere ca termenul să fi trecut: 30 de zile.
//
// Fiecare pas e reluabil, fiindcă fiecare pas costă o tranzacție ireversibilă. Vezi
// `docs/deployment/m2-1-browser-attestation.md`.
import { expect, test } from 'cip30-test-wallet/playwright';

const SUBMIT = process.env.PALMARES_FLOWS_SUBMIT === '1';
const WALLET = 'palmaresFlows';

// Patru tranzacții plus proiecțiile lor. Latența măsurată a unei proiecții e ~45 s, dar fereastra
// rămâne largă: e mai ieftin să aștepți decât să re-trimiți.
test.describe.configure({ mode: 'serial', timeout: 60 * 60 * 1000 });
const PROJECTION_WAIT = 15 * 60 * 1000;

test.use({
  walletOptions: {
    name: WALLET,
    networkId: 0,
    ledger: { chain: { provider: 'koios', network: 'preprod' } },
  },
});

test.describe('the remaining write flows, on chain from the browser', () => {
  test.skip(
    !SUBMIT,
    'SUBMITS REAL TRANSACTIONS. One command:\n' +
      '  PALMARES_WALLET_URL=https://gov.cardano.vip PALMARES_FLOWS_SUBMIT=1 \\\n' +
      '    npx playwright test --config playwright.wallet.config.js ' +
      'e2e-wallet/remaining-flows-chain.spec.js\n' +
      'Everything here is already proven to the signature by all-flows-sign.spec.js.'
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

  const set = async (page, label, value) => {
    const f = page.getByLabel(label, { exact: false }).first();
    const tag = await f.evaluate((el) => el.tagName.toLowerCase());
    if (tag === 'select') await f.selectOption(value);
    else await f.fill(value);
  };

  // Reîncarcă în buclă: ecranele registrului își cer datele o dată, la montare, deci o așteptare pe
  // o pagină încărcată înainte de proiecție stă pe un DOM înghețat.
  const awaitProjection = async (page, what, url, locatorOf) => {
    const started = Date.now();
    const deadline = started + PROJECTION_WAIT;
    for (;;) {
      await page.goto(url);
      try {
        await locatorOf().waitFor({ state: 'visible', timeout: 15_000 });
        console.log(`[flows] ${what} projected after ${Math.round((Date.now() - started) / 1000)}s`);
        return;
      } catch {
        if (Date.now() > deadline) {
          throw new Error(`${what} never appeared on ${url} (reloaded throughout)`);
        }
      }
    }
  };

  const buildSignSubmit = async (page, label) => {
    await page.getByRole('button', { name: /Build the transaction/ }).click();
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 180_000 });
    await expect(page.getByText(/Pays a network fee of/)).toBeVisible();

    await page.getByRole('button', { name: /Sign and submit/ }).click();
    // Propoziția exactă — `/submitted/i` prinde textul introductiv al ecranului.
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
    console.log(`[flows] ${label} submitted: ${txId}`);
    return txId;
  };

  const connect = async (page, flow) => {
    await withCip142(page);
    await page.goto(`/write?flow=${flow}`);
    await page.getByRole('button', { name: `Connect ${WALLET}` }).click();
    await expect(page.getByText('ready', { exact: true })).toBeVisible();
  };

  // Profilul pe care îl folosim: cel de EMITENT din M2-1, ca să nu atingem subiectul atestării
  // acceptate. Citit din registru, nu dintr-o constantă.
  const mine = async (request) => {
    const profiles = await (await request.get('/api/query/profiles?limit=200')).json();
    const issuer = profiles.items.find((p) => (p.name || '').match(/^m2-1-.*-issuer$/));
    expect(issuer, 'the m2-1 issuer profile must exist; run m2-1-chain.spec.js first').toBeTruthy();
    const attestations = await (await request.get('/api/query/attestations?limit=200')).json();
    const att = attestations.items.find((a) => (a.name || '').match(/^m2-1-.*-attestation$/));
    expect(att, 'the m2-1 attestation must exist').toBeTruthy();

    // Pentru dispută se alege o atestare care nu are DEJA una deschisă.
    //
    // Pasul 4 ținea atestarea M2-1, deci testul nu putea rula de două ori: după prima dispută
    // ecranul refuză cu „A dispute is already open against this attestation. Wait for it to be
    // resolved before opening another" — o curtoazie off-chain scrisă tot de noi. Refuzul vine
    // ÎNAINTE de construire, deci nu se pierde nimic pe lanț, dar testul pica obscur pe lipsa
    // ecranului de sumar în loc să spună de ce.
    //
    // `open_dispute_count` e chiar câmpul pe care query-api îl întoarce pentru asta, deci întrebarea
    // se pune datelor, nu unei presupuneri despre ele.
    const free = attestations.items.find((a) => (a.open_dispute_count ?? 0) === 0);
    expect(
      free,
      `all ${attestations.items.length} attestations already have an open dispute; resolve or ` +
        'expire one before running this'
    ).toBeTruthy();

    return {
      profileId: issuer.id,
      profileName: issuer.name,
      disputableId: free.id,
      disputableName: free.name,
    };
  };

  const marker = `flows-${Date.now()}`;

  test('update-profile, claim-credential, withdraw-credential, open-dispute', async ({
    page,
    request,
    wallet,
  }) => {
    const { profileId, profileName, disputableId, disputableName } = await mine(request);
    const drepId = wallet.drepId;
    expect(drepId).toMatch(/^drep1/);

    // 1. update-profile. Descrierea se schimbă, iar proiecția trebuie s-o arate — altfel „a trecut"
    //    nu spune nimic despre ce s-a scris.
    if (process.env.PALMARES_FLOWS_SKIP_UPDATE !== '1') {
      await connect(page, 'update-profile');
      await set(page, 'Profile', profileId);
      await set(page, 'Image URI', 'ipfs://palmares-flows-updated');
      await set(page, 'Description', `${marker} updated from the browser`);
      await buildSignSubmit(page, 'update-profile');
      await awaitProjection(page, 'update-profile', '/profiles', () =>
        page.getByText(`${marker} updated from the browser`)
      );
    }

    // 2. claim-credential. Ruta o spune: „Needs BOTH parties: the transaction spends the profile's
    //    user token and must also be authorised by the credential." Deci tranzacția cere și un
    //    martor al cheii DRep, nu doar al cheii de plată — iar portofelul le deține pe amândouă.
    if (process.env.PALMARES_FLOWS_SKIP_CLAIM !== '1') {
      await connect(page, 'claim-credential');
      await set(page, 'Profile', profileId);
      await set(page, 'Credential', drepId);
      await set(page, 'Name', `${marker}-credential`);
      await set(page, 'Description', 'credential claimed from the browser');
      await set(page, 'Image URI', 'ipfs://palmares-flows-credential');
      await buildSignSubmit(page, 'claim-credential');

      // Cardul profilului trebuie să numească acum credențiala. „Claims no on-chain governance
      // credential." e textul de dinainte, deci dispariția lui e jumătate din afirmație.
      await awaitProjection(page, 'credential claim', '/profiles', () =>
        page.locator('.card', { hasText: profileName }).getByText(/Claims drep1/)
      );
    }

    // 3. withdraw-credential — abia posibil după ce revendicarea e PROIECTATĂ, nu doar trimisă.
    if (process.env.PALMARES_FLOWS_SKIP_WITHDRAW !== '1') {
      await connect(page, 'withdraw-credential');
      await set(page, 'Profile', profileId);
      await set(page, 'Credential', drepId);
      await set(page, 'Name', `${marker}-withdrawal`);
      await set(page, 'Description', 'credential withdrawn from the browser');
      await set(page, 'Image URI', 'ipfs://palmares-flows-withdrawal');
      await buildSignSubmit(page, 'withdraw-credential');

      await awaitProjection(page, 'credential withdrawal', '/profiles', () =>
        page
          .locator('.card', { hasText: profileName })
          .getByText('Claims no on-chain governance credential.')
      );
    }

    // 4. open-dispute. Singurul flux care blochează bani: 5 tADA până la o decizie, iar termenul e
    //    de 30 de zile. Ecranul o spune în cuvinte înainte de construire.
    if (process.env.PALMARES_FLOWS_SKIP_DISPUTE !== '1') {
      await connect(page, 'open-dispute');
      await expect(
        page.getByText('Locks 5 ADA from your wallet until the dispute resolves.', { exact: false })
      ).toBeVisible();
      console.log(`[flows] disputing ${disputableName} (nothing open against it)`);
      await set(page, 'Attestation', disputableId);
      await set(page, 'Your profile', profileId);
      await set(page, 'Name', `${marker}-dispute`);
      await set(page, 'Description', 'contested from the browser');
      await set(page, 'Image URI', 'ipfs://palmares-flows-dispute');
      await buildSignSubmit(page, 'open-dispute');

      await awaitProjection(page, 'dispute', '/disputes', () =>
        page.getByText(`${marker}-dispute`)
      );
    }

    console.log('[flows] DONE');
  });
});
