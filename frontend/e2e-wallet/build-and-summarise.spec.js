// Tot drumul până la semnătură, în browser: construiește o tranzakție ADEVĂRATĂ și arată ce face.
//
// Diferența față de `gate.spec.js`: acolo cererea e interceptată și corpul citit de pe sârmă, aici
// **serverul răspunde**. Deci asta afirmă lucrul pe care nimic altceva nu-l afirmă — că CBOR-ul
// întors de `interaction-api` se decodează în browser și devine sumarul pe care R8 îl cere înainte
// de orice semnătură. Nu semnează și nu trimite nimic: `signTx` nici nu e atins.
//
// Cere un portofel cu UTxO-uri pe rețeaua țintă, pentru că selecția de intrări e a serverului și
// fără intrări nu există tranzacție de decodat. De aceea e sărit implicit: `PALMARES_WALLET_FUNDED=1`
// spune „adresa derivată din `PALMARES_WALLET_MNEMONIC` are fonduri pe preprod".
//
//   PALMARES_WALLET_URL=https://gov.cardano.vip \
//   PALMARES_WALLET_FUNDED=1 PALMARES_WALLET_MNEMONIC="..." \
//   npx playwright test --config playwright.wallet.config.js e2e-wallet/build-and-summarise.spec.js
import { expect, test } from 'cip30-test-wallet/playwright';

const FUNDED = process.env.PALMARES_WALLET_FUNDED === '1';
const WALLET = 'palmaresFunded';

test.use({
  walletOptions: {
    name: WALLET,
    networkId: 0,
    ...(process.env.PALMARES_WALLET_MNEMONIC
      ? { mnemonic: process.env.PALMARES_WALLET_MNEMONIC }
      : {}),
  },
});

test.describe('a real transaction, built and read back', () => {
  test.skip(
    !FUNDED,
    'Needs PALMARES_WALLET_FUNDED=1 and a wallet with UTxOs on preprod: input selection is the ' +
      "server's, and without inputs there is no transaction to decode."
  );

  // Același substitut ca în `gate.spec.js`: namespace-ul CIP-142 peste providerul real, fiindcă
  // niciun wallet din ecosistem nu-l implementează încă.
  const withCip142 = async (page) => {
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

  test('builds a profile claim and decodes what it does, without signing', async ({ page, wallet }) => {
    await withCip142(page);
    await page.goto('/write?flow=claim-profile');
    await page.getByRole('button', { name: `Connect ${WALLET}` }).click();
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    await page.getByLabel('Kind', { exact: false }).first().selectOption('person_d_rep');
    await page.getByLabel('Name', { exact: false }).first().fill(`build-probe-${Date.now() % 100000}`);
    await page.getByLabel('Description', { exact: false }).first().fill('built, not signed');
    await page.getByLabel('Image URI', { exact: false }).first().fill('ipfs://build-probe');

    await page.getByRole('button', { name: /Build the transaction/ }).click();

    // R8: sumarul DECODAT, nu ecoul formularului. Ce se afirmă aici e că decodorul a primit CBOR
    // adevărat și a scos din el lucruri care nu erau în formular.
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 120_000 });
    await expect(page.getByText(/Pays a network fee of/)).toBeVisible();
    // Tokenul care se creează: numele politicii nu apare nicăieri în formular, deci nu poate veni
    // decât din tranzacție.
    await expect(page.getByText(/648c6a73/).first()).toBeVisible();

    // Și NIMIC nu s-a semnat: butonul de semnare există, dar n-a fost apăsat.
    expect(await wallet.calls('signTx')).toHaveLength(0);
    expect(await wallet.lastSubmittedTx()).toBeUndefined();
    await expect(page.getByRole('button', { name: /Sign and submit/ })).toBeVisible();
  });
});
