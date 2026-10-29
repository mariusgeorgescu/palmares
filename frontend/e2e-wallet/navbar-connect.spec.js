// Widget-ul de wallet din bara de sus: listează extensiile instalate și conectează.
//
// Defectul pe care îl prinde, raportat de owner și reprodus aici: pe `/write` conectarea mergea și
// arăta wallet-urile, dar bara de sus scria „You do not have any wallet installed yet !" cu același
// wallet injectat în aceeași pagină.
//
// Cauza, găsită citind biblioteca: `WalletConnectComponent` nu enumeră extensiile la montare.
// Singurul loc unde își umple `availableWalletExtensions` e `handleQuery (SetWalletApi …)`, deci
// lista rămâne goală până când GAZDA trimite întrebarea aceea. `NavBar` din palmares n-avea deloc
// `initialize`, deci n-o trimitea niciodată. `bjj-frontend` o trimite în propriul `Initialize` — și
// de aceea la el mergea, cu aceeași bibliotecă.
//
// De ce `/write` nu era afectat: ecranul acela nu folosește componenta, ci cheamă
// `getAvailableWallets` direct din `purescript-cip30`. Două căi de detecție, una ruptă — exact
// forma de defect pe care un test pe o singură cale n-o vede.
import { expect, test } from 'cip30-test-wallet/playwright';
import { connectFromNavbar } from './connect.js';

const WALLET = 'palmaresNav';

test.use({ walletOptions: { name: WALLET, networkId: 0 } });

test.describe('the navbar wallet widget', () => {
  test('lists an installed wallet instead of claiming there are none', async ({ page }) => {
    const problems = [];
    page.on('pageerror', (e) => problems.push(String(e)));

    await page.goto('/');

    await page.getByRole('button', { name: /Connect/ }).first().click();

    // Numele wallet-ului injectat, în panou. Asta e afirmația: widget-ul l-a ENUMERAT.
    await expect(page.getByText(WALLET, { exact: false }).first()).toBeVisible({ timeout: 15_000 });

    // Și NU mesajul de gol. Fără afirmația asta, testul ar trece și dacă panoul ar arăta ambele.
    await expect(page.getByText('You do not have any wallet installed yet')).toHaveCount(0);

    expect(problems).toEqual([]);
  });

  // Al doilea defect raportat de owner, și cauza lui: erau DOUĂ stări de wallet. Bara de sus ținea
  // conexiunea în componenta de wallet; ecranul de scriere își conecta una a lui, cu
  // `getAvailableWallets` direct. Niciuna nu o vedea pe cealaltă, deci conectai sus și „Actions"
  // cerea un wallet, sau conectai pe „Actions" și bara arăta neconectat.
  //
  // Acum e una singură, în `Store`: bara raportează ce s-a conectat, învelișul negociază poarta de
  // guvernanță o dată, iar ecranele citesc verdictul. Testul afirmă exact asta — același ecran,
  // fără reîncărcare, află de wallet dintr-o conectare făcută în bară.
  test('the navbar connection is the one the write screen uses', async ({ page }) => {
    await page.goto('/write?flow=claim-profile');

    // Fără conexiune, ecranul trimite la bara de sus. Și nu mai are buton propriu de conectare:
    // asta e ce face ca starea să nu se mai poată desincroniza.
    await expect(page.getByText('Use the wallet button in the top bar')).toBeVisible();

    await connectFromNavbar(page, WALLET);

    // `palmaresNav` e pe networkId 0 fără CIP-142, deci verdictul porții e un REFUZ. Ce se afirmă
    // aici nu e că poate scrie, ci că ecranul ȘTIE de wallet — matricea și motivul sunt acolo,
    // iar îndemnul către bara de sus a dispărut.
    await expect(page.getByText('cannot write')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Use the wallet button in the top bar')).toHaveCount(0);
  });

  // Cealaltă direcție a aceleiași stări. Cu două surse de adevăr, deconectarea din bară lăsa
  // ecranul de scriere convins că mai are un wallet — adică gata să construiască o tranzacție pe o
  // conexiune care nu mai există.
  test('disconnecting in the navbar clears the write screen too', async ({ page }) => {
    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);
    await expect(page.getByText('cannot write')).toBeVisible({ timeout: 15_000 });

    // `force`, și e măsurat: dropdown-ul e `dropdown-hover`, iar conținutul lui deschis acoperă
    // butonul care l-a deschis — un `hover` pe buton primește „intercepts pointer events".
    await page.getByText(/^Disconnect /).click({ force: true });

    await expect(page.getByText('Use the wallet button in the top bar')).toBeVisible();
    await expect(page.getByText('cannot write')).toHaveCount(0);
  });
});

test.describe('the person dismisses the wallet prompt', () => {
  // Al treilea defect găsit pe drum, și e în BIBLIOTECĂ, nu aici: `ConnectWallet` chema `enable`
  // nepăzit. Închiderea prompt-ului e un lucru obișnuit, iar CIP-30 o raportează aruncând — deci
  // handler-ul murea acolo, nu se ridica nimic, și gazda n-avea cum să afle că s-a dat vreun clic.
  // Butonul arăta mort. Reparat în `1d0ed37` cu `WalletConnectFailedEvent`; aici se afirmă efectul.
  test.use({ walletOptions: { name: WALLET, networkId: 0, quirks: { enableRejected: true } } });

  test('is told so, and the notification clears itself', async ({ page }) => {
    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);

    const note = page.getByText(/did not connect/);
    await expect(note).toBeVisible({ timeout: 15_000 });
    // Și ceasul notificărilor se oprește singur: șase secunde, pe urmă nu mai e nimic pe ecran.
    await expect(note).toHaveCount(0, { timeout: 15_000 });
  });
});
