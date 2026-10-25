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

  // Identificatorul se citește din ADRESA linkului „Edit" / „Accept", nu din textul de pe ecran, și
  // asta e o reparație, nu o preferință. Prima variantă lua `.font-mono` din rândul găsit, și
  // ambele căi erau greșite — verificat împotriva deployului, pe date reale, ÎNAINTE de a trimite
  // ceva:
  //
  //   * pe `/profiles`, care e o listă de carduri și nu un tabel, `locator('div', { has: … })`
  //     prinde și containerul exterior, deci `.font-mono` .first() întorcea id-ul PRIMULUI profil
  //     din pagină, nu al celui căutat. Măsurat: pentru al treilea card întorcea
  //     `…000643b0f4eff1d6…` în loc de `…000643b06e4117ca…`. Un profil nou nu e primul, deci rularea
  //     ar fi atestat despre altcineva — după ce mintuise deja, ireversibil;
  //   * pe `/attestations`, cele două `.font-mono` din rând sînt id-urile de SUBIECT și EMITENT, iar
  //     id-ul atestării nu e în rând deloc. Și sînt trunchiate cu elipsă — `648c6a732aa55e…d1458b` —
  //     deci inutilizabile ca identificator.
  //
  // Linkul le poartă întregi, și e calea pe care o folosește și un om: nimeni nu copiază un hex de
  // pe ecran, apasă „Accept".
  const idFromLink = async (scope, flow) => {
    const href = await scope.locator(`a[href*="flow=${flow}"]`).first().getAttribute('href');
    expect(href, `no ${flow} deep link to read the id from`).toBeTruthy();
    const id = new URL(href, 'https://example.invalid').searchParams.get('subject');
    expect(id, `${flow} link carries no subject`).toBeTruthy();
    // Un id trunchiat ar trece mai departe și ar eșua abia la construire, cu un mesaj despre un
    // token inexistent.
    expect(id).not.toContain('\u2026');
    expect(id).toMatch(/^[0-9a-f]{56}\.[0-9a-f]+$/);
    return id;
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

    // PROPOZIȚIA EXACTĂ a cardului de trimitere, nu `/submitted/i`.
    //
    // Prima rulare a căzut exact aici, și nu pe lanț: `/submitted/i` prinde textul introductiv al
    // ecranului — „nothing here is submitted on your behalf" — și îl prinde ÎNAINTE de orice
    // semnătură. Deci afirmația trecea instantaneu, testul naviga la `/profiles`, iar navigarea
    // anula semnarea care era în curs. Zero tranzacții trimise, zece minute de așteptare, și un
    // test „verde" până la pasul următor. Starea `Signing` scrie și ea „Nothing has been submitted
    // yet.", deci regexul larg ar fi trecut și pe ea.
    //
    // Clasa e aceeași cu cea a gărzii pentru `Show (Maybe a)`, unde „Nothing is deleted" din copy
    // prindea regexul: un matcher larg peste text de interfață prinde copy, nu stare.
    const card = page.getByText('Submitted. The node has it; it is not in a block yet.');
    await expect(card).toBeVisible({ timeout: 180_000 });

    // Id-ul tranzacției, de pe ecran — singurul loc unde un om îl vede.
    const txId = await page.locator('code.font-mono').last().innerText();
    expect(txId, 'the submitted card shows no transaction id').toMatch(/^[0-9a-f]{64}$/);
    console.log(`[m2-1] ${label} submitted: ${txId}`);
    return txId;
  };

  const marker = `m2-1-${Date.now()}`;

  test('mints a profile, attests to it, accepts it, and the register shows accepted', async ({ page }) => {
    // 1. Un profil, ca să existe un subiect și un emitent.
    await connect(page, 'claim-profile');
    await fill(page, 'Kind', 'person_d_rep');
    await fill(page, 'Name', `${marker}-profile`);
    await fill(page, 'Description', 'M2-1 end-to-end run');
    await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
    const txProfile = await buildSignSubmit(page, 'profile');

    // Proiecția trebuie să prindă tranzacția. attest-sync citește Kupo și e la ZERO decalaj pe
    // deploy, deci e o chestiune de un bloc sau două. Guvernanța e în urmă cu sute de epoci, dar
    // n-are nicio legătură cu registrul: sunt două lanțuri de proiecții separate.
    await page.goto('/profiles');
    const profileRow = page.getByText(`${marker}-profile`);
    await expect(profileRow).toBeVisible({ timeout: 10 * 60 * 1000 });

    const profileCard = page.locator('.card', { hasText: `${marker}-profile` }).first();
    const profileId = await idFromLink(profileCard, 'update-profile');

    // 2. O atestare despre el, emisă de el — un singur portofel deține un singur profil, iar
    // „subiect == emitent" e o formă care există deja pe preprod (revendicările de credențială).
    await connect(page, 'issue-attestation', profileId);
    await fill(page, 'Issuer', profileId);
    await fill(page, 'Kind', 'endorsement');
    await fill(page, 'Name', `${marker}-attestation`);
    await fill(page, 'Description', 'issued and countersigned from the browser');
    await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
    const txAttestation = await buildSignSubmit(page, 'attestation');

    await page.goto('/attestations');
    const attRow = page.getByRole('row', { name: new RegExp(`${marker}-attestation`) });
    await expect(attRow).toBeVisible({ timeout: 10 * 60 * 1000 });
    // Înainte de contrasemnătură: afirmată, nerecunoscută.
    await expect(attRow.getByText('not yet')).toBeVisible();

    const attestationId = await idFromLink(attRow, 'accept-attestation');

    // 3. Contrasemnătura, cu portofelul SUBIECTULUI — aici același, fiindcă subiectul e profilul lui.
    await connect(page, 'accept-attestation', attestationId);
    const txAcceptance = await buildSignSubmit(page, 'acceptance');

    // 4. Criteriul însuși: rândul arată „accepted".
    await page.goto('/attestations');
    const accepted = page.getByRole('row', { name: new RegExp(`${marker}-attestation`) });
    await expect(accepted.getByText('accepted')).toBeVisible({ timeout: 10 * 60 * 1000 });

    // Cele trei id-uri, pentru jurnal: fără ele „a trecut" nu e o dovadă pe care cineva o poate
    // verifica pe lanț.
    console.log(`[m2-1] DONE profile=${txProfile} attestation=${txAttestation} acceptance=${txAcceptance}`);
  });
});
