// „Ce profiluri sunt ale MELE" — singura întrebare pe care un portofel conectat o poate pune de
// unul singur, și care până acum n-avea niciun apelant.
//
// Ruta `/profiles/by-user-token/{asset-class}` exista, documentele proiectului o numeau „the entry
// point to the entire wallet-side product", și ZERO ecrane o chemau. Consecința se vedea în
// formulare: trei câmpuri care înseamnă „profilul tău" se completau lipind de mână un identificator
// de șaizeci de caractere, găsit pe altă pagină.
//
// Lanțul are patru verigi, și fiecare poate să cadă separat: politica din `/status`, balanța din
// portofel, decodarea CBOR→JSON cu CSL, și filtrul pe eticheta CIP-67 `000de140` — jumătatea de
// UTILIZATOR, cea care ajunge în portofel, nu referința blocată la validator.
import { expect, test } from 'cip30-test-wallet/playwright';
import { connectFromNavbar } from './connect.js';

const WALLET = 'ownProfileProbe';

// Politica registrului pe preprod, măsurată în `/status.attestation.policy_id`. E hardcodată aici
// fiindcă `walletOptions` se fixează înainte de orice cerere — iar testul o verifică mai jos contra
// serverului, deci o schimbare de politică nu trece neobservată, cade cu un mesaj clar.
const POLICY = '648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3';

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
      const t = setInterval(() => install() && clearInterval(t), 25);
    }
  }, WALLET);
};

test.describe('a wallet that holds no profile', () => {
  test.use({ walletOptions: { name: WALLET, networkId: 0 } });

  test('is told so, and told what to do about it', async ({ page }) => {
    await withCip142(page);

    const asked = [];
    page.on('request', (r) => {
      if (r.url().includes('/by-user-token/')) asked.push(r.url());
    });

    await page.goto('/write?flow=issue-attestation');
    await connectFromNavbar(page, WALLET);
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    await expect(page.getByText('This wallet holds no profile of this registry')).toBeVisible({
      timeout: 30_000,
    });
    // Zero tokenuri de profil înseamnă zero cereri: filtrul se aplică în browser, înaintea rețelei.
    expect(asked).toEqual([]);
  });
});

test.describe('a wallet that holds one', () => {
  // Tokenul de utilizator al unui profil, fabricat în portofel. Profilul nu există pe lanț, deci
  // răspunsul rutei e singurul lucru oprit aici — restul lanțului e real.
  test.use({
    walletOptions: {
      name: WALLET,
      networkId: 0,
      utxos: [{ lovelace: 10_000_000, assets: { [POLICY + '000de140aaaa']: 1 } }],
    },
  });

  test('lists it, and fills the form with one click', async ({ page, request, baseURL }) => {
    // Politica din test trebuie să fie cea a serverului, altfel filtrul ar arunca tokenul fabricat
    // și testul ar „trece" verificând nimic.
    const status = await (await request.get(`${baseURL}/api/query/status`)).json();
    expect(
      status.attestation?.policy_id,
      'the registry policy changed; update POLICY in this spec'
    ).toBe(POLICY);

    await withCip142(page);

    const profileId = POLICY + '.000643b0aaaa';
    const asked = [];
    await page.route('**/api/query/profiles/by-user-token/**', (route) => {
      asked.push(route.request().url());
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id: profileId,
          name: 'My own profile',
          description: 'held by this wallet',
          image_uri: 'ipfs://own-profile-probe',
          kind: 'person_d_rep',
          credential: null,
          credential_is_script: null,
          claimant_count: null,
        }),
      });
    });

    await page.goto('/write?flow=issue-attestation');
    await connectFromNavbar(page, WALLET);
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    // Clasa de activ pleacă AȘA CUM VINE din portofel: derivarea user→referință e a serverului,
    // „protocol knowledge no frontend should carry", scrie în documentația rutei.
    await expect.poll(() => asked.length, { timeout: 30_000 }).toBe(1);
    expect(asked[0]).toContain(POLICY + '.000de140aaaa');

    await expect(page.getByText('My own profile')).toBeVisible();

    // Și asta e tot rostul: gol înainte de clic, plin după.
    const issuer = page.getByLabel('Issuer', { exact: false }).first();
    await expect(issuer).toHaveValue('');
    await page.getByRole('button', { name: 'Use this one' }).click();
    await expect(issuer).toHaveValue(profileId);
  });
});

test.describe('a wallet that holds two', () => {
  // Ce lipsea după prima trecere, și ce a cerut owner-ul: nu o listă per formular, ci o identitate a
  // SESIUNII — alegi o dată, sus, și aplicația știe contextul. Exact forma pe care o are `bjj-belts`.
  const A = { token: '000de140aaaa', id: POLICY + '.000643b0aaaa', name: 'Alpha profile' };
  const B = { token: '000de140bbbb', id: POLICY + '.000643b0bbbb', name: 'Beta profile' };

  test.use({
    walletOptions: {
      name: WALLET,
      networkId: 0,
      utxos: [{ lovelace: 10_000_000, assets: { [POLICY + A.token]: 1, [POLICY + B.token]: 1 } }],
    },
  });

  test('switches identity from the top bar, and the whole app follows', async ({ page }) => {
    await withCip142(page);

    // Profilurile fabricate nu există pe lanț, deci ruta lor e singurul lucru oprit aici — un
    // handler pentru ambele forme: clasa de activ (jumătatea de utilizator) și pagina de detaliu
    // (tokenul de referință).
    await page.route('**/api/query/profiles/**', (route) => {
      const url = route.request().url();
      const p = url.includes(A.token) || url.includes('000643b0aaaa') ? A : B;
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id: p.id,
          name: p.name,
          description: 'held by this wallet',
          image_uri: 'ipfs://own-profile-probe',
          kind: 'person_d_rep',
          credential: null,
          credential_is_script: null,
          claimant_count: null,
        }),
      });
    });

    await page.goto('/write?flow=issue-attestation');
    await connectFromNavbar(page, WALLET);
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    // Prima identitate e activă din oficiu: cu un singur profil n-ar fi nicio alegere de făcut, iar
    // a cere una ar fi un clic cerut degeaba.
    await expect(page.locator('.card', { hasText: 'Acting as' })).toContainText(A.name, {
      timeout: 30_000,
    });
    const issuer = page.getByLabel('Issuer', { exact: false }).first();
    await expect(issuer).toHaveValue(A.id);

    // `focus`, nu `click`: dropdown-ul daisyUI se deschide pe focus (`tabindex=0`), iar conținutul
    // lui deschis acoperă declanșatorul — un click primește „intercepts pointer events".
    await page.locator('[role="button"].avatar').first().focus();
    await page.getByRole('listitem').filter({ hasText: B.name }).first().click();

    // Contextul s-a schimbat peste tot: cardul ȘI câmpul care înseamnă „profilul tău". Comutarea e o
    // acțiune deliberată, deci suprascrie — un câmp rămas pe identitatea de dinainte ar face
    // comutatorul o minciună.
    await expect(page.locator('.card', { hasText: 'Acting as' })).toContainText(B.name);
    await expect(issuer).toHaveValue(B.id);

    // Iar pagina profilului știe acum că e a ta. Navigare ÎN APLICAȚIE, prin linkul din card: un
    // `goto` reîncarcă pagina, iar identitatea trăiește în memorie — după o reîncărcare portofelul
    // trebuie reconectat oricum.
    await page
      .locator('.card', { hasText: 'Acting as' })
      .getByRole('link', { name: B.name })
      .click();
    await expect(page.getByText('this is you')).toBeVisible({ timeout: 30_000 });
    // Și butonul care ducea la un refuz GARANTAT a dispărut: regula `Mr` interzice auto-girarea, iar
    // refuzul venea după ce omul completase formularul și semnase.
    await expect(page.getByRole('link', { name: 'Vouch for this profile' })).toHaveCount(0);
    await expect(page.getByText('nobody can vouch for themselves')).toBeVisible();
  });
});
