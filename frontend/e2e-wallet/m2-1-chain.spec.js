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
// Reluare. Fiecare pas costă o tranzacție ireversibilă, deci un eșec la pasul 2 nu trebuie să
// ceară re-mintarea profilului de la pasul 1 — prima rulare a lăsat exact așa un profil pe
// preprod. Cu `PALMARES_M2_PROFILE_ID` pus, pasul 1 se sare și se folosește profilul numit, care
// trebuie să fie deținut de ACELAȘI portofel.
const EXISTING_PROFILE = process.env.PALMARES_M2_PROFILE_ID;
const EXISTING_ISSUER = process.env.PALMARES_M2_ISSUER_PROFILE_ID;
// A treia reluare: o atestare deja emisă, de contrasemnat. Numele ei purta un marker bazat pe
// timp, deci o rulare nouă nu o putea regăsi — iar o atestare emisă și neacceptată e exact starea
// pe care pasul 3 are nevoie s-o găsească.
const EXISTING_ATTESTATION = process.env.PALMARES_M2_ATTESTATION_ID;
const WALLET = 'palmaresM2';

// Trei tranzacții plus proiecțiile lor. Nu încape în timeout-ul implicit.
// Trei tranzacții, fiecare urmată de o așteptare a proiecției. Fereastra e largă pentru că
// numărul real nu era cunoscut: prima rulare a dat 10 minute proiecției profilului și n-a ajuns —
// profilul a apărut, dar mai târziu. Testul măsoară acum fiecare așteptare și o tipărește, ca
// următoarea fereastră să fie bazată pe o cifră.
test.describe.configure({ mode: 'serial', timeout: 60 * 60 * 1000 });
const PROJECTION_WAIT = 25 * 60 * 1000;

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
    expect(txId, 'the submitted card shows no transaction id').toMatch(/^[0-9a-f]{64}$/);
    console.log(`[m2-1] ${label} submitted: ${txId}`);
    return txId;
  };

  const marker = `m2-1-${Date.now()}`;

  // Cât durează de la „trimis" până când rândul e pe ecran. E singurul număr care spune ceva despre
  // lanțul de proiecții și nu doar despre tranzacții, iar runbook-ul îl cere.
  // RELOAD, în buclă. Asta e reparația care a costat două rulări: ecranele registrului își cer
  // datele O DATĂ, la montare, și nu interoghează din nou. Deci un `expect(...).toBeVisible()` pe o
  // pagină încărcată înainte ca proiecția să ajungă așteaptă pe un DOM înghețat — a așteptat 25 de
  // minute pe un profil care era deja în API și pe care o simplă reîncărcare l-ar fi arătat.
  //
  // E și o observație despre produs, nu doar despre test: cine a mintuit ceva trebuie să
  // reîncarce ca să-l vadă. Ecranul de scriere ar putea măcar să trimită spre registru după
  // „trimis".
  const awaitProjection = async (page, what, url, locatorOf) => {
    const started = Date.now();
    const deadline = started + PROJECTION_WAIT;
    for (;;) {
      await page.goto(url);
      try {
        await locatorOf().waitFor({ state: 'visible', timeout: 15_000 });
        const secs = Math.round((Date.now() - started) / 1000);
        console.log(`[m2-1] ${what} projected after ${secs}s`);
        return secs;
      } catch (e) {
        if (Date.now() > deadline) {
          throw new Error(
            `${what} never appeared on ${url} within ${Math.round(PROJECTION_WAIT / 60000)} min ` +
              `(reloaded throughout, so this is the projection and not a stale page)`
          );
        }
      }
    }
  };

  test('mints a profile, attests to it, accepts it, and the register shows accepted', async ({ page, request }) => {
    // 1. Un profil, ca să existe un subiect și un emitent — sau cel dat, dacă reluăm.
    let txProfile = EXISTING_PROFILE ? '(reused)' : null;
    let profileName = `${marker}-profile`;

    if (EXISTING_PROFILE) {
      console.log(`[m2-1] reusing profile ${EXISTING_PROFILE}`);
    } else {
      await connect(page, 'claim-profile');
      await fill(page, 'Kind', 'person_d_rep');
      await fill(page, 'Name', profileName);
      await fill(page, 'Description', 'M2-1 end-to-end run');
      await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
      txProfile = await buildSignSubmit(page, 'profile');
    }

    // Proiecția trebuie să prindă tranzacția. attest-sync citește Kupo și e la ZERO decalaj pe
    // deploy, deci e o chestiune de un bloc sau două. Guvernanța e în urmă cu sute de epoci, dar
    // n-are nicio legătură cu registrul: sunt două lanțuri de proiecții separate.
    await page.goto('/profiles');
    let profileId;
    if (EXISTING_PROFILE) {
      // Reluare: profilul trebuie să existe deja pe ecran, altfel nu e al acestui registru.
      const card = page.locator('.card', {
        has: page.locator(`a[href*="${EXISTING_PROFILE}"]`),
      });
      await expect(card.first(), 'the given profile is not in the register').toBeVisible({
        timeout: 60_000,
      });
      profileId = EXISTING_PROFILE;
    } else {
      await awaitProjection(page, 'profile', '/profiles', () => page.getByText(profileName));
      const profileCard = page.locator('.card', { hasText: profileName }).first();
      profileId = await idFromLink(profileCard, 'update-profile');
    }

    // 1b. UN AL DOILEA PROFIL, ca emitent. Prima variantă folosea același profil ca subiect și
    // emitent, iar lanțul a refuzat-o — pe bună dreptate:
    //
    //   traceIfFalse "Mr" (isCredentialKind || subject /= issuer)
    //     -- An attestation may not be self-issued (Mr)
    //
    // Ecranul a arătat exact asta: „A validator refused this transaction: Mr PT5". Presupunerea
    // greșită era că „subiect == emitent" e o formă validă fiindcă revendicările de credențială o
    // folosesc — dar acelea sînt `isCredentialKind`, iar scutirea aceea e chiar motivul pentru care
    // restul nu sînt scutite.
    //
    // Un portofel poate deține oricâte profiluri, deci al doilea profil nu cere un al doilea
    // portofel: aceeași cheie semnează și emiterea (tokenul emitentului) și acceptarea (tokenul
    // subiectului).
    let issuerId = EXISTING_ISSUER;
    if (issuerId) {
      console.log(`[m2-1] reusing issuer profile ${issuerId}`);
    } else {
      const issuerName = `${marker}-issuer`;
      await connect(page, 'claim-profile');
      await fill(page, 'Kind', 'auditor');
      await fill(page, 'Name', issuerName);
      await fill(page, 'Description', 'M2-1 issuer profile');
      await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
      const txIssuer = await buildSignSubmit(page, 'issuer-profile');
      console.log(`[m2-1] issuer profile tx ${txIssuer}`);

      await awaitProjection(page, 'issuer profile', '/profiles', () => page.getByText(issuerName));
      issuerId = await idFromLink(
        page.locator('.card', { hasText: issuerName }).first(),
        'update-profile'
      );
    }
    expect(issuerId, 'the issuer must be a different profile').not.toBe(profileId);

    // 2. O atestare despre subiect, emisă de celălalt profil — sau cea dată, dacă reluăm.
    let txAttestation = EXISTING_ATTESTATION ? '(reused)' : null;
    let attestationId = EXISTING_ATTESTATION;

    // Numele rândului, pentru afirmația finală. La o reluare markerul e altul, deci numele se
    // citește din API după id — altfel pasul 4 ar căuta un rând care nu există și ar rata exact
    // criteriul pe care tocmai l-a îndeplinit.
    let attestationName = `${marker}-attestation`;

    if (attestationId) {
      console.log(`[m2-1] reusing attestation ${attestationId}`);
      const all = await (await request.get('/api/query/attestations?limit=200')).json();
      const found = all.items.find((a) => a.id === attestationId);
      expect(found, `attestation ${attestationId} is not in the register`).toBeTruthy();
      attestationName = found.name;
      console.log(`[m2-1] its name is ${attestationName}, accepted=${found.accepted}`);
    } else {
      await connect(page, 'issue-attestation', profileId);
      await fill(page, 'Subject', profileId);
      await fill(page, 'Issuer', issuerId);
      await fill(page, 'Kind', 'endorsement');
      await fill(page, 'Name', `${marker}-attestation`);
      await fill(page, 'Description', 'issued and countersigned from the browser');
      await fill(page, 'Image URI', 'ipfs://palmares-m2-1');
      txAttestation = await buildSignSubmit(page, 'attestation');

      await awaitProjection(page, 'attestation', '/attestations', () =>
        page.getByRole('row', { name: new RegExp(`${marker}-attestation`) })
      );
      const attRow = page.getByRole('row', { name: new RegExp(`${marker}-attestation`) });
      // Înainte de contrasemnătură: afirmată, nerecunoscută.
      await expect(attRow.getByText('not yet')).toBeVisible();
      attestationId = await idFromLink(attRow, 'accept-attestation');
    }

    // 3. Contrasemnătura, cu portofelul SUBIECTULUI — aici același, fiindcă subiectul e profilul lui.
    await connect(page, 'accept-attestation', attestationId);
    const txAcceptance = await buildSignSubmit(page, 'acceptance');

    // 4. Criteriul însuși: rândul arată „accepted".
    await awaitProjection(page, 'acceptance', '/attestations', () =>
      page.getByRole('row', { name: new RegExp(attestationName) }).getByText('accepted')
    );

    // Cele trei id-uri, pentru jurnal: fără ele „a trecut" nu e o dovadă pe care cineva o poate
    // verifica pe lanț.
    console.log(
      `[m2-1] DONE subject=${profileId} issuer=${issuerId} ` +
        `profileTx=${txProfile} attestationTx=${txAttestation} acceptanceTx=${txAcceptance}`
    );
  });
});
