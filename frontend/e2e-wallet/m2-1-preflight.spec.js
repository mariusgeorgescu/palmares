// Tot ce presupune M2-1 și care se poate verifica FĂRĂ a trimite nimic.
//
// De ce există: `m2-1-chain.spec.js` trimite trei tranzacții, iar pașii 2 și 3 nu pot rula decât
// DUPĂ ce pasul 1 a mintuit deja pe lanț — atestarea cere un profil pe care portofelul îl deține.
// Deci o greșeală în pasul 2 nu se descoperă decât după un mint ireversibil, iar rularea se
// pierde la jumătate, cu un profil orfan pe preprod.
//
// Testul ăsta a găsit două greșeli exact așa, pe date reale de pe deploy, înainte de orice
// trimitere:
//
//   1. `/profiles` e o listă de CARDURI, nu un tabel. `locator('div', { has: … })` prinde și
//      containerul exterior, deci `.font-mono` .first() întorcea id-ul PRIMULUI profil din pagină.
//      Un profil nou-mintuit nu e primul, deci rularea ar fi atestat despre altcineva.
//   2. Pe `/attestations`, cele două `.font-mono` din rând sînt subiectul și emitentul — id-ul
//      atestării nu e în rând — și sînt trunchiate cu elipsă, deci inutilizabile ca identificator.
//
// Ambele reparate citind id-ul din ADRESA linkului, care e și calea unui om: nimeni nu copiază un
// hex de pe ecran, apasă „Accept". Testul fixează acum acel contract.
//
// Nu cere nicio variabilă și nu atinge niciun portofel: sînt doar citiri.
import { expect, test } from 'cip30-test-wallet/playwright';

// Registrul e proiectat de attest-sync, care e la zero decalaj, dar deployul rămâne o rețea.
test.describe.configure({ timeout: 3 * 60 * 1000 });

const idFrom = (href) => new URL(href, 'https://example.invalid').searchParams.get('subject');

test.describe('what M2-1 assumes, checked without submitting anything', () => {
  test('a profile card hands over its FULL id through the Edit deep link', async ({ page }) => {
    await page.goto('/profiles');

    const cards = page.locator('.card', { has: page.locator('a[href*="flow=update-profile"]') });
    await expect(cards.first()).toBeVisible({ timeout: 60_000 });
    const n = await cards.count();
    expect(n, 'the register has no profiles to read an id from').toBeGreaterThan(0);

    // ANUME nu primul card: greșeala pe care testul ăsta a prins-o se vede doar pe al doilea
    // încolo, fiindcă un selector prea larg întoarce mereu primul și pe primul are dreptate.
    const idx = n > 1 ? 1 : 0;
    const card = cards.nth(idx);
    const href = await card.locator('a[href*="flow=update-profile"]').first().getAttribute('href');
    const id = idFrom(href);

    expect(id).toBeTruthy();
    expect(id, 'a truncated id would fail only later, at build time').not.toContain('…');
    // `policyId.assetName`: 56 de caractere de politică, punct, numele tokenului. Eticheta CIP-68 a
    // tokenului de referință al unui profil e `000643b0`.
    expect(id).toMatch(/^[0-9a-f]{56}\.000643b0[0-9a-f]+$/);

    // Și e id-ul ACESTUI card, nu al primului. Textul cardului nu mai conține prefixul întreg —
    // id-ul se afișează SCURTAT de cînd lista a primit chipul, fiindcă 64 de caractere monospațiate
    // plus un buton rup R2 la 390px. Deci legătura se verifică pe forma scurtată, care e ce vede
    // omul, nu pe o felie din cea întreagă.
    const shown = await card.innerText();
    const tail = id.slice(-6);
    expect(shown, 'the card must show the tail of its own id').toContain(tail);
  });

  test('an attestation row hands over its FULL id through the Accept deep link', async ({ page }) => {
    await page.goto('/attestations');

    const rows = page.locator('tr', { has: page.locator('a[href*="flow=accept-attestation"]') });
    await expect(rows.first()).toBeVisible({ timeout: 60_000 });
    const n = await rows.count();
    expect(n, 'no unaccepted attestation to read an id from').toBeGreaterThan(0);

    const row = rows.nth(n > 1 ? 1 : 0);
    const href = await row.locator('a[href*="flow=accept-attestation"]').first().getAttribute('href');
    const id = idFrom(href);

    expect(id).toBeTruthy();
    expect(id).not.toContain('…');
    expect(id).toMatch(/^[0-9a-f]{56}\.[0-9a-f]+$/);

    // Nu e un id de PROFIL: eticheta CIP-68 diferă, iar exact asta a fost greșeala — rândul arată
    // id-urile subiectului și emitentului, care sînt profiluri.
    expect(id).not.toMatch(/^[0-9a-f]{56}\.000643b0/);

    // Linkul de dispută trebuie să numească aceeași atestare. Dacă cele două diferă, unul dintre
    // ele trimite utilizatorul spre altceva decât rândul pe care a apăsat.
    const disputeHref = await row
      .locator('a[href*="flow=open-dispute"]')
      .first()
      .getAttribute('href');
    expect(idFrom(disputeHref)).toBe(id);
  });

  // Formele corpurilor pentru pașii 2 și 3, verificate pe serverul adevărat.
  //
  // Diferența pe care o prinde: un corp cu un câmp redenumit întoarce `invalid_parameter` (400),
  // iar unul corect ajunge la logica de afacere și e refuzat de ACEEA. Doar prima e un defect.
  //
  // Afirmația e pe INVARIANT, nu pe un cod anume, și asta e o corectare: prima variantă cerea
  // `ProfileNotFound`, adevărat cât timp portofelul nu deținea niciun profil. După ce M2-1 a
  // mintuit două, același corp a început să întoarcă `ScriptRefused` — validatorul refuză o
  // atestare auto-emisă (`Mr`) — și testul a căzut pe o schimbare a lumii, nu a codului. Un test
  // care fixează o stare trecătoare se strică singur.
  //
  // Măsurat cât scriam testul: un prim `POST` fără `other_metadata` a întors chiar
  // `invalid_parameter`. Serverul îl cere în `required` chiar gol, iar clientul îl trimite — deci
  // greșeala era în sondă, nu în aplicație. Exact de asta sonda trăiește aici și nu într-un
  // terminal.
  //
  // Nimic nu se construiește: ambele refuză înainte de a atinge providerul.
  const PROBE_ADDR =
    '009493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e' +
    '32c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dc';

  test('the issue and accept bodies are the shape the server wants', async ({ request, page }) => {
    // Un profil real de pe registru, citit de pe ecran — nu o constantă care expiră.
    await page.goto('/profiles');
    const link = page.locator('a[href*="flow=update-profile"]').first();
    await expect(link).toBeAttached({ timeout: 60_000 });
    const profileId = idFrom(await link.getAttribute('href'));
    expect(profileId).toBeTruthy();

    const addresses = { usedAddresses: [PROBE_ADDR], changeAddress: PROBE_ADDR };

    const issue = await request.post('/api/interaction/issue-attestation', {
      data: {
        subject_profile_id: profileId,
        issuer_profile_id: profileId,
        kind: 'endorsement',
        name: 'preflight-probe',
        description: 'checked without submitting',
        image_uri: 'ipfs://preflight',
        other_metadata: [],
        user_addresses: addresses,
      },
      failOnStatusCode: false,
    });
    // INVARIANTUL, nu un cod anume — a doua oară cînd testul ăsta mă învață aceeași lecție.
    //
    // Prima variantă cerea `ProfileNotFound`; după ce M2-1 a mintuit două profiluri, același corp a
    // început să întoarcă `ScriptRefused`. Am adăugat atunci o listă de refuzuri — și a picat iar,
    // fiindcă acum cererea REUȘEȘTE și întoarce o tranzacție, deci nu mai există niciun cod.
    //
    // Ce voia sonda să afirme n-a fost niciodată „e refuzată", ci „corpul a ajuns la logica de
    // afacere". Un corp cu un cîmp redenumit se oprește mai devreme, cu `invalid_parameter`. Deci
    // aia se afirmă, și atît: orice altceva — un refuz de afacere SAU o tranzacție — înseamnă că a
    // trecut de validarea formei.
    const expectReachedLogic = async (res, what) => {
      const text = await res.text();
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        return; // CBOR brut, deci a construit: forma a fost bună.
      }
      if (typeof body === 'string') return; // tranzacția, ca string JSON.
      expect(body.code, `${what} rejected the body shape: ${text.slice(0, 200)}`)
        .not.toBe('invalid_parameter');
    };

    await expectReachedLogic(issue, 'issue-attestation');

    await page.goto('/attestations');
    const acceptLink = page.locator('a[href*="flow=accept-attestation"]').first();
    await expect(acceptLink).toBeAttached({ timeout: 60_000 });
    const attestationId = idFrom(await acceptLink.getAttribute('href'));

    const accept = await request.post('/api/interaction/accept-attestation', {
      data: { attestation_id: attestationId, user_addresses: addresses },
      failOnStatusCode: false,
    });
    await expectReachedLogic(accept, 'accept-attestation');
  });

  // Etichetele în care M2-1 scrie. Un `getByLabel` care nu găsește nimic eșuează cu „element not
  // found" la 30 de secunde, iar pe pasul 2 asta s-ar întâmpla după un mint deja trimis.
  //
  // Poarta de wallet ascunde formularul, deci etichetele nu se pot citi din DOM fără un portofel.
  // Se citesc din descriptorii de flux — sursa pe care ecranul o randează — ceea ce prinde exact
  // greșeala care contează: un nume de câmp schimbat în cod și nu în test.
  test('every field M2-1 types into exists in the flow it belongs to', async () => {
    const { readFileSync } = await import('node:fs');
    const flows = readFileSync('src/Components/Write/Flows.purs', 'utf8');

    const expected = {
      'claim-profile': ['Kind', 'Name', 'Description', 'Image URI'],
      'issue-attestation': ['Issuer', 'Kind', 'Name', 'Description', 'Image URI'],
      // `accept-attestation` nu are câmpuri: atestarea vine din adresă, iar M2-1 nu scrie nimic.
      'accept-attestation': [],
    };

    for (const [flow, labels] of Object.entries(expected)) {
      const start = flows.indexOf(`id: "${flow}"`);
      expect(start, `flow ${flow} is gone from Flows.purs`).toBeGreaterThan(-1);
      // Până la începutul fluxului următor.
      const next = flows.indexOf('    , { id: "', start);
      const block = flows.slice(start, next === -1 ? flows.length : next);
      for (const label of labels) {
        expect(block, `${flow} no longer has a "${label}" field`).toContain(`"${label}"`);
      }
    }
  });
});
