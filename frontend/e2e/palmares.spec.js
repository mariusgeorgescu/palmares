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
    await expect(page.getByText('0.00 ADA')).toBeVisible();

    // Seria de participare: 20 de puncte, fiecare cu valoarea exactă în `title`.
    await expect(page.getByTitle(/^epoch 302: 20\.7%/)).toBeVisible();

    expect(problems).toEqual([]);
  });

  test('the status chip names the network and the freshness of each source', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByText('preprod', { exact: true })).toBeVisible();
    await expect(page.getByText('epoch 321', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('stake distribution: epoch 321')).toBeVisible();
    await expect(page.getByText(/attestations: following/)).toBeVisible();
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

    await page.getByPlaceholder('Search  ⌘K').fill('logical');
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
