// M2-1: o atestare emisă ȘI contrasemnată din browser, pe preprod, apărută pe `/attestations`.
//
// **Testul ăsta TRIMITE TRANZACȚII REALE pe preprod.** De aceea cere `PALMARES_M2_SUBMIT=1` — un
// nume care nu poate fi pus din greșeală și care nu înseamnă altceva decât „ai voie să trimiți".
// Trimiterea rămâne manuală prin decizia ownerului; variabila ESTE decizia aceea, scrisă o dată.
//
// **Ce nu mai e un blocaj: cheia.** Portofelul uneltei derivă determinist, iar adresa lui de pe
// preprod ținea 53.115 tADA în 56 de UTxO-uri la 2026-10-25 (măsurat prin Kupo-ul clusterului).
// Deci nu e nevoie de nicio cheie nouă și de niciun mnemonic în mediu — deși `PALMARES_M2_MNEMONIC`
// rămâne acceptat, pentru cazul în care vrei alt portofel. Cost: trei tranzacții, taxă măsurată
// 0,61 tADA pe una, plus min-UTxO blocat în tokenurile create. Sub 10 tADA în total.
//
// Ce e deja dovedit FĂRĂ a trimite nimic, și de aceea testul ăsta e singurul pas rămas:
//
//   * `build-and-summarise.spec.js` — serverul construiește o tranzacție Conway adevărată, iar
//     browserul o decodează și arată ce face (R8), pe deploy;
//   * `sign-not-submit.spec.js` — wallet-ul SEMNEAZĂ cu adevărat, cu cheia lui, iar aplicația
//     trimite martorul la `/submit-tx` cu exact tranzacția pe care a arătat-o — doar că ruta aceea
//     e interceptată. Singura diferență față de testul de aici e că acolo octeții nu pleacă.
//
// Vezi `docs/deployment/m2-1-browser-attestation.md`.
import { expect, test } from 'cip30-test-wallet/playwright';

const SUBMIT = process.env.PALMARES_M2_SUBMIT === '1';
const WALLET = 'palmaresM2';

// Trei tranzacții plus proiecțiile lor. Nu încape în timeout-ul implicit.
test.describe.configure({ mode: 'serial', timeout: 20 * 60 * 1000 });

test.use({
  walletOptions: {
    name: WALLET,
    networkId: 0,
    // Modul chain, și e necesar: serverul alege intrările din UTxO-urile REALE de pe preprod, iar
    // registrul sintetic al uneltei nu le cunoaște — wallet-ul refuză să semneze cu
    // `CHW_UNRESOLVED_INPUT`. Măsurat, nu presupus.
    ledger: { chain: { provider: 'koios', network: 'preprod' } },
    ...(process.env.PALMARES_M2_MNEMONIC ? { mnemonic: process.env.PALMARES_M2_MNEMONIC } : {}),
  },
});

test.describe('M2-1: the write path, end to end on preprod', () => {
  test.skip(
    !SUBMIT,
    'This test SUBMITS REAL TRANSACTIONS to preprod. One command runs it:\n' +
      '  PALMARES_WALLET_URL=https://gov.cardano.vip PALMARES_M2_SUBMIT=1 \\\n' +
      '    npx playwright test --config playwright.wallet.config.js e2e-wallet/m2-1-chain.spec.js\n' +
      'No key is needed — the tool wallet derives deterministically and its preprod address is ' +
      'funded. Everything up to the signature is already proven by build-and-summarise.spec.js ' +
      'and sign-not-submit.spec.js; see docs/deployment/m2-1-browser-attestation.md.'
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
    await expect(page.getByText('ready', { exact: true })).toBeVisible();
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
  const buildSignSubmit = async (page, label) => {
    await page.getByRole('button', { name: /Build the transaction/ }).click();

    // R8: sumarul decodat trebuie să fie acolo ÎNAINTE de semnătură. Dacă nu e, nu se semnează —
    // ăsta e tot rostul regulii.
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 180_000 });
    await expect(page.getByText(/Pays a network fee of/)).toBeVisible();

    await page.getByRole('button', { name: /Sign and submit/ }).click();

    // „Trimis" e o stare proprie, distinctă de „confirmat", iar testul o citește DE PE ECRAN și nu
    // dintr-un apel de rețea: ce vede omul e criteriul.
    //
    // Nu se aștepta pe `wallet.calls('submitTx')`, cum făcea prima variantă, și asta era o eroare
    // de model: aplicația nu cheamă niciodată `submitTx`-ul portofelului — trimite martorul la
    // `/submit-tx`, iar serverul asamblează și trimite. Așteptarea aceea n-ar fi venit niciodată.
    await expect(page.getByText(/submitted/i).first()).toBeVisible({ timeout: 180_000 });
    console.log(`[m2-1] ${label}: submitted`);
  };

  const marker = `m2-1-${Date.now()}`;

  test('mints a profile, attests to it, accepts it, and the register shows accepted', async ({ page }) => {
    // 1. Un profil, ca să existe un subiect și un emitent.
    await connect(page, 'claim-profile');
    await fill(page, 'Kind', 'person_d_rep');
    await fill(page, 'Name', `${marker}-profile`);
    await fill(page, 'Description', 'M2-1 end-to-end run');
    await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
    await buildSignSubmit(page, 'profile');

    // Proiecția trebuie să prindă tranzacția. attest-sync citește Kupo și e la ZERO decalaj pe
    // deploy, deci e o chestiune de un bloc sau două. Guvernanța e în urmă cu sute de epoci, dar
    // n-are nicio legătură cu registrul: sunt două lanțuri de proiecții separate.
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
    await buildSignSubmit(page, 'attestation');

    await page.goto('/attestations');
    const attRow = page.getByRole('row', { name: new RegExp(`${marker}-attestation`) });
    await expect(attRow).toBeVisible({ timeout: 10 * 60 * 1000 });
    // Înainte de contrasemnătură: afirmată, nerecunoscută.
    await expect(attRow.getByText('not yet')).toBeVisible();

    const attestationId = await attRow.locator('.font-mono').first().innerText();

    // 3. Contrasemnătura, cu portofelul SUBIECTULUI — aici același, fiindcă subiectul e profilul lui.
    await connect(page, 'accept-attestation', attestationId);
    await buildSignSubmit(page, 'acceptance');

    // 4. Criteriul însuși: rândul arată „accepted".
    await page.goto('/attestations');
    const accepted = page.getByRole('row', { name: new RegExp(`${marker}-attestation`) });
    await expect(accepted.getByText('accepted')).toBeVisible({ timeout: 10 * 60 * 1000 });
  });
});
