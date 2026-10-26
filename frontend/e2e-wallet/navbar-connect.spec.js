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

  test('the write screen agrees with the navbar about what is installed', async ({ page }) => {
    // Cele două căi de detecție trebuie să spună același lucru. Cât timp una folosea componenta și
    // cealaltă `purescript-cip30`, au divergeat luni de zile fără ca nimic să observe.
    await page.goto('/write?flow=claim-profile');
    await expect(page.getByRole('button', { name: `Connect ${WALLET}` })).toBeVisible();

    await page.goto('/');
    await page.getByRole('button', { name: /Connect/ }).first().click();
    await expect(page.getByText(WALLET, { exact: false }).first()).toBeVisible({ timeout: 15_000 });
  });
});
