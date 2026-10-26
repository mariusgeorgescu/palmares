// Fiecare flux de scriere care POATE fi construit, dus până la ultima margine: construit de
// serverul adevărat, decodat în browser, semnat cu cheia portofelului — și oprit la `POST
// /submit-tx`, singurul pas ireversibil.
//
// De ce nu toate nouă: trei dintre ele au dependențe de STARE pe care doar o trimitere le poate
// crea, iar două nu se pot încheia dintr-un browser obișnuit nici în principiu. Măsurat pe deploy
// la 2026-10-25:
//
//   | fluxul | se poate construi? | de ce |
//   | --- | --- | --- |
//   | claim-profile        | DA  | dovedit pe lanț (M2-1) |
//   | issue-attestation    | DA  | dovedit pe lanț (M2-1) |
//   | accept-attestation   | DA  | dovedit pe lanț (M2-1) |
//   | update-profile       | DA  | portofelul deține două profiluri |
//   | claim-credential     | DA  | portofelul are cheie DRep CIP-95 |
//   | open-dispute         | DA  | există 20 de atestări; blochează un depozit de 5 tADA |
//   | withdraw-credential  | NU  | cere o revendicare de credențială DEJA pe lanț |
//   | resolve-dispute      | NU  | cere o dispută nedecisă ȘI semnătura adminului oracolului — ruta
//   |                      |     | întoarce o tranzacție NESEMNATĂ pentru admin, prin design |
//   | expire-dispute       | NU  | cere o dispută nedecisă trecută de termen: `dispute_timeout_ms`
//   |                      |     | e 2.592.000.000 ms = 30 de zile |
//
// Cele cinci dispute existente pe preprod sînt toate `verdict: upheld`, deci nici resolve nici
// expire nu au pe ce lucra. Asta nu e o lipsă de acoperire din neglijență, e o dependență: ultimele
// trei rânduri cer, în ordine, o trimitere, cheia ownerului, și treizeci de zile.
import { expect, test } from 'cip30-test-wallet/playwright';

const FUNDED = process.env.PALMARES_WALLET_FUNDED === '1';
const WALLET = 'palmaresFlows';

test.use({
  walletOptions: {
    name: WALLET,
    networkId: 0,
    // Modul chain: serverul alege intrări reale, iar registrul sintetic nu le cunoaște — fără el
    // wallet-ul refuză să semneze cu `CHW_UNRESOLVED_INPUT`.
    ledger: { chain: { provider: 'koios', network: 'preprod' } },
  },
});

test.describe.configure({ mode: 'serial', timeout: 10 * 60 * 1000 });

test.describe('every buildable write flow, signed but not submitted', () => {
  test.skip(
    !FUNDED,
    'Needs PALMARES_WALLET_FUNDED=1: input selection is the server\'s, so the wallet needs UTxOs.'
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

  // Ce deține portofelul, citit din registru. O constantă ar expira la prima rulare pe alt lanț.
  const stateFrom = async (request) => {
    const profiles = await (await request.get('/api/query/profiles?limit=200')).json();
    const attestations = await (await request.get('/api/query/attestations?limit=200')).json();
    const mine = profiles.items.filter((p) => (p.name || '').startsWith('m2-1-'));
    expect(
      mine.length,
      'this wallet owns no profile here; run m2-1-chain.spec.js first'
    ).toBeGreaterThan(0);
    return { profileId: mine[0].id, attestationId: attestations.items[0].id };
  };

  // Construiește prin serverul adevărat, cere sumarul decodat, semnează, și oprește trimiterea.
  // Întoarce AMBELE corpuri: cel de construire (care poartă câmpurile fluxului) și cel de
  // trimitere (care poartă doar `tx_unsigned` și `tx_wit`). Prima variantă le-a confundat și a
  // căutat `profile_id` în corpul de trimitere — unde nu există, fiindcă la pasul acela fluxul s-a
  // transformat deja într-o tranzacție.
  const signButDoNotSubmit = async (page, wallet, flow, fill) => {
    const builds = [];
    // `continue()`, nu `fulfill()`: construirea TREBUIE să ajungă la serverul adevărat, altfel nu
    // există tranzacție de decodat și de semnat. Se citește doar corpul, în trecere.
    await page.route(`**/api/interaction/${flow}`, async (route) => {
      builds.push(route.request().postDataJSON());
      await route.continue();
    });

    const submits = [];
    await page.route('**/api/interaction/submit-tx', async (route) => {
      submits.push(route.request().postDataJSON());
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify('0'.repeat(64)),
      });
    });
    await page.route('**/api/interaction/tx-status/**', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: 'false' })
    );

    await withCip142(page);
    await page.goto(`/write?flow=${flow}`);
    await page.getByRole('button', { name: `Connect ${WALLET}` }).click();
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    const signsBefore = (await wallet.calls('signTx')).length;
    await fill();

    await page.getByRole('button', { name: /Build the transaction/ }).click();

    // R8: sumarul decodat ÎNAINTE de semnătură, pentru fiecare flux și nu doar pentru primul.
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 180_000 });
    await expect(page.getByText(/Pays a network fee of/)).toBeVisible();

    await page.getByRole('button', { name: /Sign and submit/ }).click();
    await expect.poll(() => submits.length, { timeout: 180_000 }).toBe(1);

    const signs = await wallet.calls('signTx');
    expect(signs.length, 'the wallet must have signed exactly once more').toBe(signsBefore + 1);
    const last = signs[signs.length - 1];
    const [txArg, partial] = last.args;

    expect(partial, 'partial signing: the server assembles from the witness').toBe(true);
    expect(submits[0].tx_unsigned, 'what was sent must be what was signed').toBe(txArg);
    expect(submits[0].tx_wit).toBe(last.result);
    expect(
      submits[0].tx_wit.toLowerCase(),
      'the witness must carry THIS wallet key'
    ).toContain(wallet.paymentPublicKeyHex.toLowerCase());

    // Propoziția exactă — `/submitted/i` prinde copy, nu stare.
    await expect(
      page.getByText('Submitted. The node has it; it is not in a block yet.')
    ).toBeVisible({ timeout: 60_000 });
    // Și nimic n-a plecat: aplicația nu cheamă `submitTx`-ul portofelului, iar ruta e interceptată.
    expect(await wallet.calls('submitTx')).toHaveLength(0);

    expect(builds.length, 'the build request must have been seen').toBe(1);
    return { build: builds[0], submit: submits[0] };
  };

  test('update-profile', async ({ page, request, wallet }) => {
    const { profileId } = await stateFrom(request);
    const { build } = await signButDoNotSubmit(page, wallet, 'update-profile', async () => {
      await set(page, 'Profile', profileId);
      await set(page, 'Image URI', 'ipfs://palmares-flow-update');
      await set(page, 'Description', 'edited from the browser, not submitted');
    });
    expect(build.profile_id).toBe(profileId);
  });

  test('claim-credential', async ({ page, request, wallet }) => {
    const { profileId } = await stateFrom(request);
    // Id-ul DRep al portofelului, CIP-129. Vine din cheia reală, deci dovada de credențială pe care
    // o cere fluxul e una adevărată.
    const drepId = wallet.drepId;
    expect(drepId).toMatch(/^drep1/);

    const { build } = await signButDoNotSubmit(page, wallet, 'claim-credential', async () => {
      await set(page, 'Profile', profileId);
      await set(page, 'Credential', drepId);
      await set(page, 'Name', 'flow-probe credential claim');
      await set(page, 'Description', 'claimed from the browser, not submitted');
      await set(page, 'Image URI', 'ipfs://palmares-flow-credential');
    });
    expect(build.profile_id).toBe(profileId);
    expect(build.credential).toContain('drep1');
  });

  test('open-dispute', async ({ page, request, wallet }) => {
    const { profileId, attestationId } = await stateFrom(request);
    const { build } = await signButDoNotSubmit(page, wallet, 'open-dispute', async () => {
      // Ce face fluxul ăsta diferit de celelalte opt: blochează bani. Consecința trebuie să fie pe
      // ecran ÎNAINTE de construire, în cuvinte, nu doar în sumarul de după.
      //
      // Afirmația de dinainte era după trimitere, unde cardul de sumar e deja înlocuit de cel de
      // trimitere — deci cerea un text care tocmai dispăruse. Greșeala era a testului; ecranul
      // arată exact ce trebuie.
      await expect(
        page.getByText('Locks 5 ADA from your wallet until the dispute resolves.', {
          exact: false,
        })
      ).toBeVisible();
      await set(page, 'Attestation', attestationId);
      await set(page, 'Your profile', profileId);
      await set(page, 'Name', 'flow-probe dispute');
      await set(page, 'Description', 'contested from the browser, not submitted');
      await set(page, 'Image URI', 'ipfs://palmares-flow-dispute');
    });
    expect(build.attestation_id).toBe(attestationId);
    expect(build.opened_by_profile_id).toBe(profileId);
  });

  // Cele două fluxuri de dispută, acoperite cât se poate — iar „cât se poate" e afirmația.
  //
  // Nu se semnează niciunul: la `resolve-dispute` semnătura e a adminului oracolului și nu o avem,
  // iar la `expire-dispute` nu există tranzacție de semnat. Ce se afirmă aici e că ruta răspunde
  // adevărul: o tranzacție pentru prima, un refuz numit pentru a doua.

  // SKIP, nu o aserțiune dură — a treia oară cînd lecția asta mă prinde, deci de data asta o scriu
  // ca regulă, nu ca excepție.
  //
  // Testul cere o dispută NEDECISĂ, iar asta e stare de lanț care se schimbă sub el: azi n-a mai
  // existat niciuna fiindcă una a fost rezolvată și cealaltă expirată, exact în tura în care cele
  // două fluxuri au fost închise. Un test care pică fiindcă produsul a făcut ce trebuia e zgomot,
  // nu semnal — iar sărit, spune limpede ce îi lipsește.
  const openDisputeOrSkip = async (request) => {
    const d = await (await request.get('/api/query/disputes?limit=200')).json();
    const undecided = d.items.find((x) => !x.verdict);
    test.skip(
      !undecided,
      `No undecided dispute on chain (${d.total} total, all decided), so there is nothing to ` +
        'resolve or expire. Open one with remaining-flows-chain.spec.js first.'
    );
    return undecided.id;
  };

  test('resolve-dispute builds, and the summary says a signature we do not have is needed', async ({
    page,
    request,
    wallet,
  }) => {
    const disputeId = await openDisputeOrSkip(request);

    await withCip142(page);
    await page.goto('/write?flow=resolve-dispute');
    await page.getByRole('button', { name: `Connect ${WALLET}` }).click();
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    await set(page, 'Dispute', disputeId);
    await set(page, 'Verdict', 'upheld');
    await page.getByRole('button', { name: /Build the transaction/ }).click();

    // Tranzacția se construiește: ruta merge, iar sumarul se decodează. Atât se poate dovedi.
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 180_000 });
    await expect(page.getByText(/Pays a network fee of/)).toBeVisible();

    // ȘI spune că e nevoie de o semnătură în plus. Linia aceea e singurul loc din interfață care
    // explică de ce fluxul ăsta nu se poate încheia dintr-un browser obișnuit — validatorul
    // oracolului cere adminul, iar sumarul o anunță înainte de orice semnătură.
    await expect(page.getByText(/signature.? required beyond the inputs/)).toBeVisible();

    // Și nu semnăm. Nu din precauție: n-avem cheia, iar o semnătură parțială ar fi respinsă de nod.
    expect(await wallet.calls('signTx')).toHaveLength(0);
  });

  test('expire-dispute is refused while the deadline stands, and says so', async ({ page, request }) => {
    const disputeId = await openDisputeOrSkip(request);

    await withCip142(page);
    await page.goto('/write?flow=expire-dispute');
    await page.getByRole('button', { name: `Connect ${WALLET}` }).click();
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    await set(page, 'Dispute', disputeId);
    await page.getByRole('button', { name: /Build the transaction/ }).click();

    // Refuzul, cu motivul, în cuvinte. Serverul întoarce `DisputeNotStaleYet` cu „its deadline has
    // not passed" — iar un ecran care ar arăta doar „a eșuat" ar ascunde singurul lucru util.
    await expect(page.getByText(/deadline has not passed/)).toBeVisible({ timeout: 180_000 });
    // Și niciun sumar, deci nimic de semnat: refuzul vine înainte de orice tranzacție.
    await expect(page.getByText('What this transaction does')).toHaveCount(0);
  });
});
