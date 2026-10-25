// e2e pe bundle-ul demo: fixturi măsurate, deci cifre exacte.
//
// Ce verifică suita asta și testele unitare nu pot: că ecranele se montează, că rutele se parsează
// din URL (inclusiv un ID cu `#`), că navigarea SPA schimbă ce se vede, și că nimic nu scrie în
// consola browserului. Un decodor corect și un ecran alb trec amândouă testele unitare.
import { test, expect } from '@playwright/test';

// Orice eroare din consolă pică testul în care s-a întâmplat. Un `Uncaught` în Halogen nu oprește
// pagina — lasă un ecran pe jumătate randat, care arată aproape bine.
function watchConsole(page) {
  const problems = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error' || msg.type() === 'warning') problems.push(`${msg.type()}: ${msg.text()}`);
  });
  page.on('pageerror', (err) => problems.push(`pageerror: ${err.message}`));
  return problems;
}

test.describe('palmares, on recorded fixtures', () => {
  test('the dashboard shows the measured figures, with the treasury as two numbers', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/');

    await expect(page.getByRole('heading', { name: 'Palmares', level: 1 })).toBeVisible();
    // 294 înregistrați, dar 204 activi+inactivi: cifra din card și linkul de sub ea.
    await expect(page.getByText('294', { exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: '204 active or inactive' })).toBeVisible();
    await expect(page.getByRole('link', { name: '204 active or inactive' }))
      .toHaveAttribute('href', '/dreps?status=active&status=inactive');

    // Trezoreria: două numere, nu unul.
    await expect(page.getByText('Requested', { exact: true })).toBeVisible();
    // „Enacted" apare și în desfășurarea pe rezultate; aici ne interesează cardul de trezorerie.
    await expect(page.getByText('Enacted', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('656,466,092 ADA')).toBeVisible();
    // „0 ADA", nu „0.00 ADA": zecimalele se păstrează doar sub un ADA, unde rotunjirea ar
    // transforma o sumă reală în zero. Zero adevărat se scrie scurt.
    await expect(page.getByText('0 ADA', { exact: true })).toBeVisible();

    // Seria de participare: 20 de puncte, fiecare cu valoarea exactă în `title`.
    await expect(page.getByTitle(/^epoch 302: 20\.7%/)).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('the status chip names the network and the freshness of each source', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByText('preprod', { exact: true })).toBeVisible();
    await expect(page.getByText('epoch 321', { exact: true }).first()).toBeVisible();
    await expect(page.getByText(/attestations: following/)).toBeVisible();
    // Banda spune ce e NOU. Când metricile și puterea de vot sunt din epoca curentă — cazul
    // fixturii — a le mai scrie o dată înseamnă același număr de trei ori pe fiecare ecran.
    await expect(page.getByText(/metrics as of epoch/)).toBeHidden();
    await expect(page.getByText(/voting power as of epoch 321$/)).toBeHidden();
  });

  test('a deep link into the DRep list arrives filtered, not on the home page', async ({ page }) => {
    const problems = watchConsole(page);
    // Regresia pe care template-ul o avea: ruta curentă nu era citită la pornire, deci orice URL
    // deschis direct randa pagina de pornire.
    await page.goto('/dreps?status=active&status=inactive');

    await expect(page.getByRole('heading', { name: 'DReps', level: 1 })).toBeVisible();
    await expect(page.getByText('294 DReps match, showing 1–4')).toBeVisible();
    // Facetele nu se adună la total, și ecranul o spune.
    await expect(page.getByText(/do not add up to the number of matches/)).toBeVisible();
    await expect(page.getByRole('link', { name: /Retired 526/ })).toBeVisible();
    // Intervalul de jos e „fără putere de vot", nu „0,00 ADA – 0,00 ADA".
    await expect(page.getByRole('link', { name: /No voting power/ })).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('a metric that is null renders n/a, never 0%', async ({ page }) => {
    await page.goto('/dreps');
    // `rationale_rate` e null pe rândurile măsurate; „0%" ar fi o acuzație la adresa autorului.
    await expect(page.getByRole('cell', { name: 'n/a', exact: true }).first()).toBeVisible();
  });

  test('a DRep page shows the name with the id beside it, and the foreign document as text', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/dreps/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z');

    await expect(page.getByText('Logical Mechanism dRep').first()).toBeVisible();
    // R3: ID-ul scurtat apare lângă nume.
    await expect(page.getByText('drep1ydmraa6kv…40sw2z').first()).toBeVisible();
    // R2/R1: documentul CIP-119 ajunge pe ecran ca text.
    await expect(page.getByText('Objectives', { exact: true })).toBeVisible();
    await expect(page.getByText(/expert consulting, comprehensive knowledge/)).toBeVisible();
    // Un delegator fără stake înregistrat: „unknown", nu zero.
    await expect(page.getByRole('cell', { name: 'unknown', exact: true })).toBeVisible();
    // Referințele externe pleacă marcate.
    const ref = page.getByRole('link', { name: 'The Logical Mechanism Website' });
    await expect(ref).toHaveAttribute('rel', 'nofollow noopener noreferrer');
    await expect(ref).toHaveAttribute('target', '_blank');

    expect(problems).toEqual([]);
  });

  test('a governance action id survives the URL with its hash encoded', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/gov-actions/90de87d46e6345118c01dc5ec701b4dce5621ffa3b1f98a3d55eb34e85da7392%230');

    await expect(page.getByRole('heading', { name: /Plomin Hard Fork/ })).toBeVisible();
    // Ciclul de viață are doi pași, în două epoci.
    await expect(page.getByText('expired in epoch 304, then dropped in epoch 305.')).toBeVisible();
    // Verdictul numărătorii arată comparația, nu doar concluzia.
    await expect(page.getByText(/in favour against a 67\.0% threshold/)).toBeVisible();
    // O retragere neplătită.
    await expect(page.getByRole('cell', { name: /not paid/ })).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('the votes explorer marks a superseded vote instead of counting it again', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/votes');

    await expect(page.getByRole('heading', { name: 'Votes', level: 1 })).toBeVisible();
    await expect(page.getByText(/superseded, 3 votes in all/)).toBeVisible();
    await expect(page.getByText(/only the last one counts/)).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('the methodology page publishes the query, not a description of it', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/methodology?focus=participation_rate_v1');

    await expect(page.getByRole('heading', { name: 'Participation rate' })).toBeVisible();
    await expect(page.getByText('|actions_voted| / |actions_eligible|')).toBeVisible();
    // Regula care face diferența între „n/a" și „0%".
    await expect(page.getByText('Returns nothing when').first()).toBeVisible();
    await expect(page.getByText('eligible_actions = 0').first()).toBeVisible();

    // SQL-ul e ascuns până e cerut, dar e întreg.
    const details = page.getByText('Show the query that computes this').first();
    await details.click();
    await expect(page.getByText(/WITH p AS/).first()).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('search finds three different DReps with the same name', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/');

    await page.getByPlaceholder('Search', { exact: true }).fill('logical');
    // Trei credențiale distincte, un singur nume: de aceea ID-ul merge lângă nume.
    await expect(page.getByRole('link', { name: /Logical Mechanism dRep/ })).toHaveCount(3);
    await expect(page.getByText('763ef75661f0cd8c8fa159a79d79bfe8f9a76878bdaaff700598ee0e')).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('clicking through the navigation changes the screen without reloading', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/');

    await page.getByRole('link', { name: 'Actions', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Governance actions', level: 1 })).toBeVisible();
    await expect(page).toHaveURL('/gov-actions');

    await page.getByRole('link', { name: 'Methodology', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Methodology', level: 1 })).toBeVisible();

    // Înapoi în istoric readuce ecranul anterior: rutele sunt stare de navigare, nu de componentă.
    await page.goBack();
    await expect(page.getByRole('heading', { name: 'Governance actions', level: 1 })).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('an unknown path lands on not-found, not on a blank screen', async ({ page }) => {
    await page.goto('/this-does-not-exist');
    await expect(page.getByRole('heading', { name: 'Not found' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Go home' })).toBeVisible();
  });
});

// Regresia pe care suita n-o putea vedea: fiecare ecran derula orizontal pe telefon.
// Masurat inainte de reparare, la 390px: /gov-actions 1117px, /dreps 941px, /votes 921px, restul
// 505px. Un test de continut trece oricum, pentru ca textul E acolo — doar ca utilizatorul trebuie
// sa traga pagina lateral ca sa-l vada.
test.describe('at phone width', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  const routes = [
    '/',
    '/dreps',
    '/dreps/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z',
    '/spos',
    '/committee',
    '/treasury',
    '/delegations',
    '/activity',
    '/profiles',
    '/attestations',
    '/disputes',
    '/graph',
    '/graph?drep=drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z',
    '/write',
    '/write?flow=open-dispute',
    '/embed?drep=drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z',
    '/gov-actions',
    '/gov-actions/90de87d46e6345118c01dc5ec701b4dce5621ffa3b1f98a3d55eb34e85da7392%230',
    '/votes',
    '/methodology',
    '/this-does-not-exist',
  ];

  for (const route of routes) {
    test(`${route} does not scroll sideways`, async ({ page }) => {
      await page.goto(route);
      const { scrollWidth, clientWidth } = await page.evaluate(() => ({
        scrollWidth: document.scrollingElement.scrollWidth,
        clientWidth: document.documentElement.clientWidth,
      }));
      expect(scrollWidth, `${route} overflows by ${scrollWidth - clientWidth}px`).toBeLessThanOrEqual(clientWidth + 1);
    });
  }

  test('the navigation collapses into a menu instead of overflowing', async ({ page }) => {
    await page.goto('/');
    // Linkurile orizontale sint ascunse sub lg; meniul se deschide din buton.
    await expect(page.getByRole('link', { name: 'Methodology', exact: true })).toBeHidden();
    await page.getByRole('button', { name: 'Main menu' }).click();
    await expect(page.getByRole('link', { name: 'Methodology', exact: true })).toBeVisible();
    // Si se inchide la navigare, in loc sa ramina deschis peste ecranul urmator.
    await page.getByRole('link', { name: 'Methodology', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Methodology', level: 1 })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Methodology', exact: true })).toBeHidden();
  });
});

// Titlul documentului e singurul lucru care distinge doua taburi deschise pe acelasi site.
test('the document title names the screen', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/^Palmares/);
  await page.goto('/votes');
  await expect(page).toHaveTitle('Votes — Palmares');
  await page.goto('/gov-actions');
  await expect(page).toHaveTitle('Governance actions — Palmares');
  await page.goto('/spos');
  await expect(page).toHaveTitle('Stake pool operators — Palmares');
  await page.goto('/committee');
  await expect(page).toHaveTitle('Constitutional committee — Palmares');
  await page.goto('/treasury');
  await expect(page).toHaveTitle('Treasury withdrawals — Palmares');
  await page.goto('/delegations');
  await expect(page).toHaveTitle('Delegations — Palmares');
  await page.goto('/activity');
  await expect(page).toHaveTitle('Activity — Palmares');
  await page.goto('/profiles');
  await expect(page).toHaveTitle('Profiles — Palmares');
  await page.goto('/attestations');
  await expect(page).toHaveTitle('Attestations — Palmares');
  await page.goto('/disputes');
  await expect(page).toHaveTitle('Disputes — Palmares');
  await page.goto('/graph');
  await expect(page).toHaveTitle('Delegation graph — Palmares');
  await page.goto('/write');
  await expect(page).toHaveTitle('Act on chain — Palmares');
  await page.goto('/this-does-not-exist');
  await expect(page).toHaveTitle('Not found — Palmares');
});

// Bara de navigare marcheaza sectiunea in care te afli, inclusiv pe o pagina de detaliu.
test('the navigation marks the section you are in', async ({ page }) => {
  await page.goto('/dreps/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z');
  await expect(page.getByRole('link', { name: 'DReps', exact: true })).toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('link', { name: 'Votes', exact: true })).toHaveAttribute('aria-current', 'false');
});

// Un `Maybe` randat direct scrie „Just 323" sau „Nothing" in pagina, si compilatorul nu are ce sa
// spuna: `Show (Maybe a)` exista, deci `show a.lastVotableEpoch` e cod valid. Asta s-a si intimplat,
// in doua locuri, in minutul in care douasprezece cimpuri au devenit optionale — vazut intr-o
// captura, nu intr-un test. Acum e un test.
const SHOW_LEAK = /\bJust\s|\bNothing\b/;

for (const route of [
  '/',
  '/dreps',
  '/dreps/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z',
  '/gov-actions',
  '/gov-actions/90de87d46e6345118c01dc5ec701b4dce5621ffa3b1f98a3d55eb34e85da7392%230',
  '/votes',
  '/spos',
  '/committee',
  '/treasury',
  '/delegations',
  '/activity',
  '/profiles',
  '/attestations',
  '/disputes',
  '/graph',
  '/write?flow=issue-attestation',
]) {
  test(`${route} renders no PureScript constructor`, async ({ page }) => {
    await page.goto(route);
    const text = await page.evaluate(() => document.body.innerText);
    const hit = text.match(SHOW_LEAK);
    expect(hit && text.slice(Math.max(0, hit.index - 40), hit.index + 20), `${route} leaks a constructor`).toBeFalsy();
  });
}

// Check 15: fisa se pune pe site-ul altcuiva ca `iframe`. Testul e exact afirmatia aceea — o
// pagina straina, un `iframe` catre noi, si continutul randat inauntru. Daca cineva adauga vreodata
// `X-Frame-Options` pe BFF, widgetul moare in tacere pe toate site-urile care l-au pus; aici cade
// zgomotos.
test('the embed card renders inside an iframe on a foreign page', async ({ page, baseURL }) => {
  const drep = 'drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z';
  await page.setContent(
    `<!doctype html><html><body><h1>Someone else's site</h1>
     <iframe id="w" src="${baseURL}/embed?drep=${drep}" title="Palmares governance record"
             width="380" height="220" style="border:0"></iframe></body></html>`
  );
  const frame = page.frameLocator('#w');
  await expect(frame.getByText('Voting power')).toBeVisible();
  await expect(frame.getByText(drep.slice(0, 12), { exact: false })).toBeVisible();
  // Linkul inapoi iese din cadru, altfel Palmares s-ar deschide intr-o fereastra de 380px.
  await expect(frame.getByRole('link', { name: /full record/ })).toHaveAttribute('target', '_top');
  // Si NU randeaza produsul nostru in miniatura: fara bara de navigare in cadru.
  await expect(frame.getByRole('navigation', { name: 'Main' })).toHaveCount(0);
});


// M2-3 si M2-4: poarta de wallet se vede INAINTE de formular, nu dupa.
//
// Mock-ul demo raporteaza anume un wallet care ANUNTA CIP-95 si nu are CIP-142 — dezacordul real
// pentru care exista matricea. Testul cere exact ce cere contractul: refuzul se declanseaza, spune
// DE CE, si formularul nici nu se deseneaza.
test('the wallet gate refuses before the form, and says why', async ({ page }) => {
  await page.goto('/write?flow=open-dispute');

  // Fara wallet: niciun cimp de formular pe ecran.
  await expect(page.getByRole('textbox')).toHaveCount(0);

  // Fara niciun wallet in browser nu exista buton de conectare, ci propozitia care spune de ce.
  // Refuzul cu matrice se testeaza in suita `e2e-wallet`, cu un wallet CIP-30 adevarat.
  await expect(page.getByText('No Cardano wallet is installed')).toBeVisible();
  await expect(page.getByText('Connect a wallet that can write here')).toBeVisible();
  // Propozitia, nu celula din matrice: amindoua contin „CIP-142", iar cea care conteaza e cea care
  // explica ce NU se va intimpla.
  // Si tot niciun formular.
  await expect(page.getByRole('textbox')).toHaveCount(0);
});

// Cele noua fluxuri exista si sint accesibile, fiecare cu propriul URL.
test('all nine write flows are listed and deep-linkable', async ({ page }) => {
  const flows = [
    ['claim-profile', 'Claim a profile'],
    ['update-profile', 'Edit a profile'],
    ['issue-attestation', 'Issue an attestation'],
    ['accept-attestation', 'Accept an attestation'],
    ['open-dispute', 'Open a dispute'],
    ['resolve-dispute', 'Resolve a dispute'],
    ['expire-dispute', 'Expire a dispute'],
    ['claim-credential', 'Claim a governance credential'],
    ['withdraw-credential', 'Withdraw a governance credential'],
  ];
  await page.goto('/write');
  for (const [, title] of flows) {
    await expect(page.getByRole('link', { name: title, exact: true })).toBeVisible();
  }
  for (const [id, title] of flows) {
    await page.goto(`/write?flow=${id}`);
    await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible();
  }
});

// Un link din produs aduce identificatorul cu el: altfel omul copiaza de mina saizeci de caractere.
test('a flow deep-linked with a subject arrives without breaking the route', async ({ page }) => {
  await page.goto('/write?flow=open-dispute&subject=pol.assetname');
  // Ca identificatorul ajunge in cimpul potrivit se verifica unitar pe `buildRequest`; aici doar
  // ca ruta cu doi parametri se parseaza si randeaza fluxul cerut.
  await expect(page).toHaveTitle('Act on chain — Palmares');
  await expect(page.getByRole('heading', { name: 'Open a dispute', exact: true })).toBeVisible();
});
