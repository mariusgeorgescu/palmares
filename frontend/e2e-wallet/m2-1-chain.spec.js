// M2-1: o atestare emisă ȘI contrasemnată din browser, pe preprod, apărută pe `/attestations`.
//
// Testul ăsta TRIMITE TRANZACȚII REALE. Nu rulează fără `PALMARES_M2_MNEMONIC`, și asta nu e o
// precauție generică: repo-ul nu livrează un semnatar prin decizie — `scripts/smoke_attest_flow.sh`
// o spune pe linia 34, „a signer guessed here would be a credential" — iar trimiterea rămâne
// manuală prin decizia ownerului. Cu variabila pusă, criteriul se închide singur; fără ea, suita
// trece peste.
//
// Vezi `docs/deployment/m2-1-browser-attestation.md` pentru ce e deja dovedit fără cheie.
import { expect, test } from 'cip30-test-wallet/playwright';

const MNEMONIC = process.env.PALMARES_M2_MNEMONIC;
const WALLET = 'palmaresM2';

// Trei tranzacții plus proiecțiile lor. Nu încape în timeout-ul implicit.
test.describe.configure({ mode: 'serial', timeout: 15 * 60 * 1000 });

test.use({
  walletOptions: {
    name: WALLET,
    networkId: 0,
    mnemonic: MNEMONIC,
    // Modul chain: UTxO-urile vin de pe preprod prin Koios, iar `submitTx` trimite cu adevărat.
    ledger: { chain: { provider: 'koios', network: 'preprod' } },
  },
});

test.describe('M2-1: the write path, end to end on preprod', () => {
  test.skip(
    !MNEMONIC,
    'Needs PALMARES_M2_MNEMONIC — a funded preprod wallet. This test submits real transactions; ' +
      'see docs/deployment/m2-1-browser-attestation.md.'
  );

  // CIP-142 nu există în niciun wallet, nici în unealta asta — „Path to Active" din CIP îl listează
  // ca pas viitor. Fără namespace-ul lui, poarta refuză pe bună dreptate, deci testul îl adaugă
  // peste providerul real, exact cum îl specifică CIP-ul. Substitut pentru un wallet care nu există
  // încă, scris aici ca atare.
  const addCip142 = async (page) => {
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

  const connect = async (page, flow, subject) => {
    await addCip142(page);
    const qs = subject ? `?flow=${flow}&subject=${encodeURIComponent(subject)}` : `?flow=${flow}`;
    await page.goto(`/write${qs}`);
    await page.getByRole('button', { name: `Connect ${WALLET}` }).click();
    await expect(page.getByText('ready')).toBeVisible();
  };

  // Cîmpurile nu sînt toate `<input>`: „Kind" e un `<select>`, iar `fill` pe el aruncă. Helperul
  // se uită la tag și alege operația, ca testul să nu codifice forma fiecărui cîmp.
  const fill = async (page, label, value) => {
    const f = page.getByLabel(label, { exact: false }).first();
    const tag = await f.evaluate((el) => el.tagName.toLowerCase());
    if (tag === 'select') await f.selectOption(value);
    else await f.fill(value);
  };

  // Construiește, citește sumarul, semnează, trimite. Fiecare pas e o afirmație separată, pentru că
  // fiecare înseamnă altceva: până la „submit" nu s-a întâmplat nimic pe lanț.
  const buildSignSubmit = async (page, wallet) => {
    await page.getByRole('button', { name: /Build the transaction/ }).click();

    // R8: sumarul decodat trebuie să fie acolo ÎNAINTE de semnătură. Dacă nu e, nu se semnează —
    // ăsta e tot rostul regulii.
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText(/Pays a network fee of/)).toBeVisible();

    const before = (await wallet.calls('submitTx')).length;
    await page.getByRole('button', { name: /Sign and submit/ }).click();

    await expect
      .poll(async () => (await wallet.calls('submitTx')).length, { timeout: 120_000 })
      .toBeGreaterThan(before);

    const submitted = await wallet.lastSubmittedTx();
    expect(submitted).toBeTruthy();
    return submitted;
  };

  const marker = `m2-1-${Date.now()}`;

  test('mints a profile, attests to it, accepts it, and the register shows accepted', async ({ page, wallet }) => {
    // 1. Un profil, ca să existe un subiect și un emitent.
    await connect(page, 'claim-profile');
    await fill(page, 'Kind', 'person_d_rep');
    await fill(page, 'Name', `${marker}-profile`);
    await fill(page, 'Description', 'M2-1 end-to-end run');
    await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
    await buildSignSubmit(page, wallet);

    // Proiecția trebuie să prindă tranzacția. Pe un db-sync sincronizat e un minut; pe unul care
    // încă reface istoria, nu se întâmplă deloc — de aceea suita asta se rulează împotriva
    // stack-ului LOCAL sincronizat, nu împotriva deployului care e în urmă cu sute de epoci.
    await page.goto('/profiles');
    const profileRow = page.getByText(`${marker}-profile`);
    await expect(profileRow).toBeVisible({ timeout: 10 * 60 * 1000 });

    // Identificatorul profilului, citit de pe ecran: e singura cale prin care un om îl află, deci e
    // calea pe care o testăm.
    const profileId = await page
      .locator('div', { has: profileRow })
      .locator('.font-mono')
      .first()
      .innerText();
    expect(profileId).toMatch(/^[0-9a-f]{56}\./);

    // 2. O atestare despre el, emisă de el — un singur portofel deține un singur profil, iar
    // „subiect == emitent" e o formă care există deja pe preprod (revendicările de credențială).
    await connect(page, 'issue-attestation', profileId);
    await fill(page, 'Issuer', profileId);
    await fill(page, 'Kind', 'endorsement');
    await fill(page, 'Name', `${marker}-attestation`);
    await fill(page, 'Description', 'issued and countersigned from the browser');
    await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
    await buildSignSubmit(page, wallet);

    await page.goto('/attestations');
    const attRow = page.getByRole('row', { name: new RegExp(`${marker}-attestation`) });
    await expect(attRow).toBeVisible({ timeout: 10 * 60 * 1000 });
    // Înainte de contrasemnătură: afirmată, nerecunoscută.
    await expect(attRow.getByText('not yet')).toBeVisible();

    const attestationId = await attRow.locator('.font-mono').first().innerText();

    // 3. Contrasemnătura, cu portofelul SUBIECTULUI — aici același, fiindcă subiectul e profilul lui.
    await connect(page, 'accept-attestation', attestationId);
    await buildSignSubmit(page, wallet);

    // 4. Criteriul însuși: rândul arată „accepted".
    await page.goto('/attestations');
    const accepted = page.getByRole('row', { name: new RegExp(`${marker}-attestation`) });
    await expect(accepted.getByText('accepted')).toBeVisible({ timeout: 10 * 60 * 1000 });
  });
});
