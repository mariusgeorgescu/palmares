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

    // Titlul paginii de pornire nu mai e numele produsului, ci ce face el. Numele rămîne în bara de
    // navigare, unde omul îl caută ca să știe unde e; titlul e primul lucru pe care îl citește, iar
    // „Palmares" singur nu-i spunea nimic.
    await expect(
      page.getByRole('heading', { name: /Who vouches for whom/, level: 1 })
    ).toBeVisible();
    // Și eroul trebuie să ducă undeva: butoanele lui sînt singurul drum din pagina de pornire către
    // registru pentru cineva care nu știe încă ce e în bara de navigare.
    // `.first()`: eroul și cardul de caz de utilizare poartă acum același îndemn, deliberat — e
    // același drum, oferit o dată sus și o dată în context.
    await expect(page.getByRole('link', { name: 'See who vouched for whom' }).first())
      .toHaveAttribute('href', '/attestations');
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

    // Căutarea e acum o PALETĂ, ca în bjj: se deschide întîi. Se deschide cu scurtătura, nu cu un
    // clic pe declanșator, fiindcă `⌘K` e drumul pe care îl promite eticheta din bara de sus — iar
    // un test care nu-l apasă n-ar fi observat că paleta trebuie și DESCHISĂ de el, nu doar
    // focalizată.
    await page.keyboard.press('ControlOrMeta+k');
    const dialog = page.getByRole('dialog', { name: 'Search' });
    await expect(dialog).toBeVisible();
    await dialog.getByRole('searchbox').fill('logical');
    // Trei credențiale distincte, un singur nume: de aceea ID-ul merge lângă nume.
    await expect(page.getByRole('link', { name: /Logical Mechanism dRep/ })).toHaveCount(3);
    await expect(page.getByText('763ef75661f0cd8c8fa159a79d79bfe8f9a76878bdaaff700598ee0e')).toBeVisible();

    // Și se închide cu Escape, din panou, nu doar din cîmp.
    await page.keyboard.press('Escape');
    await expect(dialog).toBeHidden();

    expect(problems).toEqual([]);
  });

  test('clicking through the navigation changes the screen without reloading', async ({ page }) => {
    const problems = watchConsole(page);
    await page.goto('/');

    // „Attestations" e in linie, fiindca registrul e produsul; explorerul de guvernanta e in
    // meniul „Governance".
    //
    // Scopat la bara de sus: de cînd exista si sina laterala, acelasi nume apare de doua ori — o
    // data sus si o data in sina, deliberat. Un `getByRole` nescopat ar cadea pe strict mode, iar
    // raspunsul corect e sa spui PE CARE il apesi, nu sa renunti la unul dintre ele.
    const mainNav = page.getByRole('navigation', { name: 'Main' });
    await mainNav.getByRole('link', { name: 'Attestations', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Attestations', level: 1 })).toBeVisible();
    await expect(page).toHaveURL('/attestations');

    await page.getByRole('link', { name: 'Methodology', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Methodology', level: 1 })).toBeVisible();

    // Înapoi în istoric readuce ecranul anterior: rutele sunt stare de navigare, nu de componentă.
    await page.goBack();
    await expect(page.getByRole('heading', { name: 'Attestations', level: 1 })).toBeVisible();

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
  // Pe o pagina de detaliu de atestare nu exista ruta separata, deci se verifica pe lista — si pe
  // un ecran de guvernanta, unde marcajul trebuie sa cada pe meniul „Governance", nu pe nimic.
  await page.goto('/attestations');
  // Bara de sus ȘI șina marchează aceeași secțiune — două locuri, același adevăr. Se verifică
  // amîndouă, fiindcă un marcaj care cade doar într-unul lasă celălalt mincinos.
  const topNav = page.getByRole('navigation', { name: 'Main' });
  const rail = page.getByRole('navigation', { name: 'Sections' }).first();
  await expect(topNav.getByRole('link', { name: 'Attestations', exact: true }))
    .toHaveAttribute('aria-current', 'page');
  await expect(rail.locator('a[aria-current="page"]')).toHaveAttribute('href', '/attestations');
  await expect(topNav.getByRole('link', { name: 'Profiles', exact: true }))
    .toHaveAttribute('aria-current', 'false');

  await page.goto('/dreps/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z');
  // Pe un ecran din explorer, marcajul e pe rezumatul meniului „Governance" — altfel bara n-ar
  // spune nimic despre unde te afli pe jumatate din site. Linkul dinauntru poarta `aria-current`,
  // dar e intr-un `details` inchis, deci se deschide intii.
  await expect(page.locator('nav summary', { hasText: 'Governance' })).toHaveClass(/text-primary/);
  await page.locator('nav summary', { hasText: 'Governance' }).click();
  await expect(page.getByRole('link', { name: 'Representatives', exact: true })).toHaveAttribute('aria-current', 'page');
});

// Un `Maybe` randat direct scrie „Just 323" sau „Nothing" in pagina, si compilatorul nu are ce sa
// spuna: `Show (Maybe a)` exista, deci `show a.lastVotableEpoch` e cod valid. Asta s-a si intimplat,
// in doua locuri, in minutul in care douasprezece cimpuri au devenit optionale — vazut intr-o
// captura, nu intr-un test. Acum e un test.
// Tiparul e strîns pe FORMA pe care o are un `Maybe` randat, nu pe cuvinte: `show (Just 323)`
// pune mereu o valoare după „Just", iar un `Nothing` scăpat apare după un cuvînt („as of epoch
// Nothing"), niciodată la început de propoziție. Varianta largă dinainte pica pe textul paginii de
// pornire, care începe o propoziție cu „Nothing is deleted" — un test care cere să nu scrii un
// cuvînt englezesc obișnuit e un test care se dezactivează.
const SHOW_LEAK = /\bJust\s+[-\d"(]|[a-z0-9,:] Nothing\b/;

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

// R1: markdown doar GFM, FARA cale pentru HTML brut.
//
// Documentele de ancora — CIP-100/CIP-119 — sint input neincrezut: le scrie oricine si noi doar le
// citim de pe lant. Regula nu e „sa curatam HTML-ul", e „sa nu existe calea": fara cale, fara clasa
// de XSS.
//
// Testul e pe SURSA, nu pe ecran, fiindca asta e forma afirmatiei. Un test care ar randa un
// document si ar cauta un `<script>` ar trece si daca un singur ecran randeaza HTML pe o ramura pe
// care fixtura n-o atinge.
test('there is no raw-HTML render path anywhere in the app', async () => {
  const { readFileSync, readdirSync, statSync } = await import('node:fs');
  const { join } = await import('node:path');

  const walk = (dir) =>
    readdirSync(dir).flatMap((entry) => {
      const full = join(dir, entry);
      return statSync(full).isDirectory() ? walk(full) : [full];
    });

  // Caile prin care Halogen sau DOM-ul pot primi markup in loc de text.
  const forbidden = [/innerHTML/, /outerHTML/, /insertAdjacentHTML/, /dangerously/i, /document\.write/];

  const offenders = [];
  for (const file of walk('src')) {
    if (!/\.(purs|js)$/.test(file)) continue;
    const text = readFileSync(file, 'utf8');
    for (const pattern of forbidden) {
      // Comentariile se scot inainte de cautare: un comentariu care EXPLICA de ce nu folosim
      // `innerHTML` n-are voie sa pice testul care verifica tocmai asta.
      const code = text
        .split('\n')
        .filter((l) => !/^\s*(--|\/\/)/.test(l))
        .join('\n');
      if (pattern.test(code)) offenders.push(`${file}: ${pattern}`);
    }
  }
  expect(offenders).toEqual([]);
});

// R2 pe ecran, nu doar in `clampText`: un document de ancora poate avea un cimp de 2 MB, iar
// limitele din CIP nu sint invarianti on-chain. Nicio linie randata nu trebuie sa fie absurda.
test('no rendered line runs away, whatever the document says', async ({ page }) => {
  await page.goto('/dreps/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z');
  const longest = await page.evaluate(() => {
    const seen = [];
    document.querySelectorAll('p, dd, span, td, li').forEach((el) => {
      if (el.children.length === 0) seen.push(el.innerText.length);
    });
    return Math.max(0, ...seen);
  });
  // Pragul e generos: ce se vaneaza e un cimp netaiat de zeci de mii de caractere, nu un paragraf
  // lung scris de noi.
  expect(longest).toBeLessThan(4000);
});

// CHECK 16: deployul reproductibil trebuie sa includa interfata, nu doar backendul.
//
// `compose.yaml` avea cele patru servicii de backend si se oprea acolo, deci „o comanda, de la
// zero" producea un stack fara nicio interfata. Testul e pe fisiere, fiindca asta e forma
// afirmatiei: un test care ar porni stack-ul ar cere Docker si un sfert de ora.
test('the reproducible stack includes the frontend and its build', async () => {
  const { readFileSync } = await import('node:fs');

  const compose = readFileSync('../compose.yaml', 'utf8');
  // Serviciul exista, in amindoua profilurile, si proxiaza catre numele de serviciu — nu catre
  // `localhost`, care in containerul lui ar fi el insusi.
  expect(compose).toMatch(/^ {2}frontend:/m);
  expect(compose).toMatch(/PALMARES_QUERY_API_URL: "http:\/\/query-api:8083"/);
  expect(compose).toMatch(/PALMARES_INTERACTION_API_URL: "http:\/\/interaction-api:8082"/);
  // Credentialele de scriere nu au default: un default intr-un fisier commis e o credentiala care
  // se publica, iar restul fisierului respecta deja regula asta.
  expect(compose).toMatch(/PALMARES_INTERACTION_API_USER: "\$\{BASIC_USER:\?/);
  expect(compose).toMatch(/PALMARES_INTERACTION_API_PASS: "\$\{BASIC_PASS:\?/);

  // Si imaginea se construieste de scriptul care construieste restul — altfel `up` trage o imagine
  // care nu exista local pe un host amd64.
  const build = readFileSync('../scripts/build-images.sh', 'utf8');
  expect(build).toMatch(/palmares-frontend/);
  expect(build).toMatch(/-f frontend\/Dockerfile/);

  // Si comanda unica e documentata.
  const readme = readFileSync('../README.md', 'utf8');
  expect(readme).toMatch(/--profile app --profile write up -d/);
});

test('an on-chain identifier is readable, linkable and copyable', async ({ page }) => {
  // Defectul pe care îl fixează, măsurat pe deploy: identificatorii apărau trunchiați cu elipsă,
  // iar valoarea întreagă nu era accesibilă nicăieri. Unele locuri puneau un `HP.title`, cu un
  // comentariu care spunea „cel întreg e pentru copiat" — dar textul unui tooltip nativ nu e
  // selectabil, deci promisiunea nu se livra.
  //
  // Iar id-ul unei ATESTĂRI nu era randat deloc: exista doar în `href`-urile de acțiune, în timp ce
  // `/write` cere omului să-l „lipească". Calea de scriere documentată nu se putea parcurge din
  // interfață — și exact asta m-a costat o rulare pe lanț, în care testul a încercat să citească
  // id-ul de pe ecran și a primit un șir tăiat.
  await page.goto('/attestations');
  await expect(page.getByRole('table')).toBeVisible();

  const chips = page.locator('.dropdown [data-copy]');
  expect(await chips.count(), 'no identifier carries a copy affordance').toBeGreaterThan(0);

  // Valoarea din `data-copy` e ÎNTREAGĂ: fără elipsă și de lungimea unui id real.
  const value = await chips.first().getAttribute('data-copy');
  expect(value).not.toContain('…');
  expect(value).toMatch(/^[0-9a-f]{56}\.[0-9a-f]+$/);

  // Și linkul către explorer păstrează punctul. MĂSURAT pe preprod.cexplorer.io: fără punct,
  // `/asset/` cade pe pagina de pornire fără nicio eroare — ceea ce arată ca „nu există".
  const link = page.locator('.dropdown-content a[href*="/asset/"]').first();
  const href = await link.getAttribute('href');
  expect(href).toContain('/asset/');
  expect(href).toContain('.');
  // Link extern deschis în tab nou, cu `rel` — altfel e reverse tabnabbing.
  expect(await link.getAttribute('rel')).toContain('noopener');

  // Textul linkului e id-ul COMPLET, nu unul scurtat: panoul există ca să arate ce lista nu poate.
  expect((await link.innerText()).trim()).toBe(value);
});

test('the four wallet icons are not empty strings any more', async ({ page }) => {
  // `NavBar.purs` trimitea patru string-uri goale în componenta de wallet, adică patru sloturi
  // goale pe deploy. Fișierele existau în bjj-frontend de mult; lipsea copierea lor.
  await page.goto('/');
  for (const name of ['walletsymbol', 'disconnectsymbol', 'onramp', 'copy-icon']) {
    const res = await page.request.get(`/images/${name}.svg`);
    expect(res.status(), `/images/${name}.svg must be served`).toBe(200);
    expect((await res.text()).slice(0, 400)).toContain('svg');
  }
});

test('the sidebar rail is on desktop and the dock on phones, with the section marked', async ({ page }) => {
  // Elementul care dă STRUCTURA aspectului din bjj: conținutul stă între o șină la stânga și bara
  // de sus, iar pe telefon navigarea coboară într-un doc. Fără el, oricâte clase de stil ar fi
  // împrumutate, aplicația arată ca alta.
  await page.setViewportSize({ width: 1280, height: 860 });
  await page.goto('/profiles');

  const rail = page.getByRole('navigation', { name: 'Sections' }).first();
  await expect(rail).toBeVisible();
  // Secțiunea curentă e marcată, iar `aria-current` o spune și pentru cineva care nu vede culoarea.
  await expect(rail.locator('a[aria-current="page"]')).toHaveAttribute('href', '/profiles');

  // MĂȘTILE TREBUIE SĂ FIE GENERATE. Prima variantă compunea clasa Tailwind prin concatenare, iar
  // scanerul citește textul sursei: regulile nu existau, iar șina a ieșit un rând de pătrate pline.
  // Testul cere regula în foaia de stil servită, nu doar clasa pe element.
  const css = await (await page.request.get('/output.css')).text();
  for (const icon of ['home', 'practitioners', 'achievements', 'bell', 'dashboard', 'activity', 'lineage', 'about']) {
    expect(css, `the mask rule for ${icon}.svg was not generated`)
      .toContain(`url(/images/sidebar/${icon}.svg)`);
  }

  // Pe telefon: docul, nu șina.
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/profiles');
  // UN SINGUR `nav` „Sections" la lățimea asta, nu al doilea din DOM: șina e `hidden`, iar
  // `getByRole` exclude din arborele de accesibilitate ce are `display: none`. Prima variantă cerea
  // `nth(1)` presupunând ordinea din DOM și pica — iar comportamentul e corect, nu testul.
  const navs = page.getByRole('navigation', { name: 'Sections' });
  await expect(navs).toHaveCount(1);
  await expect(navs.first()).toBeVisible();
  // Cinci intrări, ca în bjj: mai multe și fiecare ar fi sub pragul de atingere.
  await expect(navs.first().locator('a')).toHaveCount(5);
});

test('the activity drawer opens over any screen and closes with Escape', async ({ page }) => {
  // Ultima piesa de aspect din bjj, si una pe care o respinsesem pe o premisa gresita: credeam ca
  // butonul flotant de la `bottom-24` s-ar bate cu docul de pe telefon. Codul lui bjj stivuieste
  // butoanele la `bottom-24` si `bottom-40` TOCMAI fiindca are si el un doc jos — tiparul rezolvase
  // deja coliziunea pe care o invocam.
  await page.goto('/profiles');

  const fab = page.getByRole('button', { name: 'Show recent activity' });
  await expect(fab).toBeVisible();
  await fab.click();

  const drawer = page.getByRole('dialog', { name: 'Recent activity' });
  await expect(drawer).toBeVisible();
  // Indicatorul „LIVE" si cel putin un eveniment: un sertar gol ar fi un buton care minte.
  await expect(drawer.getByText('Live')).toBeVisible();
  await expect(drawer.locator('li')).not.toHaveCount(0);
  // Si drumul spre fluxul intreg, fiindca sertarul arata doar zece.
  await expect(drawer.getByRole('link', { name: 'See the whole feed' }))
    .toHaveAttribute('href', '/activity');

  // Escape inchide din PANOU, nu doar din buton.
  await page.keyboard.press('Escape');
  await expect(drawer).toBeHidden();
  await expect(fab).toBeVisible();
});

test('a list is not a card you lift, and the pager says what it can do', async ({ page }) => {
  // DOUA defecte raportate de owner pe aceleasi ecrane, amandoua reparate aici.
  //
  // 1. RIDICAREA LA HOVER ERA A LISTEI INTREGI. `explorer-card` s-a pus pe toate cele 59 de carduri,
  //    iar pe /attestations si /disputes cardul acela e UNUL SINGUR si inveleste tabelul — deci
  //    hover-ul oriunde ridica si scala toata lista. Ridicarea e un gest despre UN obiect; un tabel
  //    de douazeci de randuri nu e un obiect.
  // 2. PAGINATORUL arata doua butoane moarte permanent cand totul incape pe o pagina, ceea ce e
  //    indistinguibil de un control rupt.
  for (const route of ['/attestations', '/disputes']) {
    await page.goto(route);
    await expect(page.getByRole('table')).toBeVisible();

    // Cardul care inveleste tabelul nu mai are tranzitia de ridicare.
    const wrapper = page.locator('.explorer-card:has(table)').first();
    await expect(wrapper).toBeVisible();
    const lifts = await wrapper.evaluate((el) => {
      const before = el.getBoundingClientRect().top;
      el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
      return getComputedStyle(el).transitionProperty;
    });
    expect(lifts, `${route}: a card wrapping a table must not animate a lift`).toBe('none');
  }

  // Si paginatorul: ori butoane care duc undeva, ori niciunul — niciodata doua moarte.
  await page.goto('/attestations');
  const dead = page.locator('span.btn-disabled');
  const live = page.getByRole('link', { name: /Previous|Next/ });
  const deadCount = await dead.count();
  const liveCount = await live.count();
  expect(
    deadCount === 0 || liveCount > 0,
    'two permanently disabled pager buttons read as a broken control'
  ).toBe(true);
});
