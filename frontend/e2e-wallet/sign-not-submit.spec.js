// Semnătura, cu totul — și exact un pas oprit: octeții care pleacă spre lanț.
//
// `POST /submit-tx` e singurul pas ireversibil din tot produsul, și e marcat ca atare în cod
// (`MonadInteract.purs`: „ĂSTA e pasul ireversibil"). Trimiterea rămâne manuală prin decizia
// ownerului, deci testul ăsta o oprește la ULTIMA margine posibilă: wallet-ul semnează cu adevărat,
// aplicația trimite cererea cu adevărat, iar răspunsul vine de la o rută interceptată în loc de
// server. Tot ce e deasupra acelei margini se execută.
//
// De ce există: până acum `signTx` nu era apelat NICIODATĂ în nicio suită. `SignAndSubmit` din
// `Runner.purs` — patru stări, un apel de semnare, un POST și o verificare de status — era cod
// nerulat. `build-and-summarise.spec.js` se oprește înainte de buton, intenționat.
//
//   PALMARES_WALLET_URL=https://gov.cardano.vip PALMARES_WALLET_FUNDED=1 \
//   npx playwright test --config playwright.wallet.config.js e2e-wallet/sign-not-submit.spec.js
import { expect, test } from 'cip30-test-wallet/playwright';
import { connectFromNavbar } from './connect.js';

const FUNDED = process.env.PALMARES_WALLET_FUNDED === '1';
const WALLET = 'palmaresFunded';

// MODUL CHAIN, și e necesar, nu o alegere de comoditate: serverul alege intrările din UTxO-urile
// REALE de pe preprod, iar registrul sintetic al uneltei nu le cunoaște — wallet-ul refuza să
// semneze cu `CHW_UNRESOLVED_INPUT: input 0dea48…#0 is unknown to the mock ledger`. Pe un wallet
// adevărat nu există acel refuz, deci fără modul chain testul ar măsura unealta.
//
// Modul chain face `submitTx`-ul PORTOFELULUI să trimită cu adevărat. Nu e o problemă aici, și
// merită spus de ce: aplicația nu cheamă niciodată `submitTx` — trimite martorul la server, care
// asamblează și trimite. Acea rută e interceptată mai jos, iar punctul 4 al testului afirmă că
// `submitTx` al portofelului a rămas neatins.
test.use({
  walletOptions: {
    name: WALLET,
    networkId: 0,
    ledger: { chain: { provider: 'koios', network: 'preprod' } },
    ...(process.env.PALMARES_WALLET_MNEMONIC
      ? { mnemonic: process.env.PALMARES_WALLET_MNEMONIC }
      : {}),
  },
});

// Aceeași măsurătoare ca la `build-and-summarise`: construirea trece prin nodul și Kupo-ul din
// spatele serverului, iar pe deploy drumul ăla merge prin rețeaua clusterului.
test.describe.configure({ timeout: 4 * 60 * 1000 });

test.describe('the wallet really signs, and the bytes stop at the last edge', () => {
  test.skip(
    !FUNDED,
    'Needs PALMARES_WALLET_FUNDED=1 and a wallet with UTxOs: input selection is the server\'s.'
  );

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

  test('builds, signs with its own key, and posts the witness — submission intercepted', async ({
    page,
    wallet,
  }) => {
    await withCip142(page);

    // Numai ruta ireversibilă e oprită. Construirea merge la serverul adevărat, fiindcă altfel
    // n-ar exista o tranzacție de semnat.
    const submits = [];
    await page.route('**/api/interaction/submit-tx', async (route) => {
      submits.push(route.request().postDataJSON());
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        // Răspunsul formei pe care serverul o dă: id-ul tranzacției. Un hash plauzibil, nu unul
        // care există — tocmai pentru că nimic nu s-a trimis.
        body: JSON.stringify('0'.repeat(64)),
      });
    });
    // Și verificarea de status care urmează: „încă nu s-a confirmat" e adevărul despre o
    // tranzacție care n-a plecat.
    await page.route('**/api/interaction/tx-status/**', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: 'false' })
    );

    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    await page.getByLabel('Kind', { exact: false }).first().selectOption('person_d_rep');
    await page
      .getByLabel('Name', { exact: false })
      .first()
      .fill(`sign-probe-${Date.now() % 100000}`);
    await page.getByLabel('Description', { exact: false }).first().fill('signed, never submitted');
    await page.getByLabel('Image URI', { exact: false }).first().fill('ipfs://sign-probe');

    await page.getByRole('button', { name: /Build the transaction/ }).click();
    await expect(page.getByText('What this transaction does')).toBeVisible({ timeout: 180_000 });

    // Nimic semnat până aici. Afirmația contează: butonul stă SUB sumar, iar ordinea e tot rostul R8.
    expect(await wallet.calls('signTx')).toHaveLength(0);

    await page.getByRole('button', { name: /Sign and submit/ }).click();

    await expect.poll(() => submits.length, { timeout: 180_000 }).toBe(1);

    // 1. Wallet-ul a semnat cu adevărat, o dată, cu `partialSign` — aplicația nu construiește o
    //    tranzacție completă, serverul o asamblează din martor.
    const signs = await wallet.calls('signTx');
    expect(signs).toHaveLength(1);
    const [txArg, partial] = signs[0].args;
    expect(partial).toBe(true);
    expect(txArg).toMatch(/^[0-9a-f]+$/);

    // 2. Ce s-a trimis e EXACT tranzacția construită plus martorul întors de wallet. Un dApp care
    //    trimite altceva decât ce a arătat e cazul pe care R8 există să-l prevină.
    const body = submits[0];
    expect(body.tx_unsigned).toBe(txArg);
    expect(body.tx_wit).toBe(signs[0].result);

    // 3. Martorul e al ACESTUI portofel: setul de martori purtă cheia publică de plată pe 32 de
    //    octeți, iar fără ea semnătura ar fi a altcuiva sau a nimănui.
    expect(body.tx_wit.toLowerCase()).toContain(wallet.paymentPublicKeyHex.toLowerCase());
    expect(body.tx_wit.length).toBeGreaterThan(64 * 2);

    // 4. Și nimic n-a ajuns pe lanț: wallet-ul nu e în modul chain, deci `submitTx` al lui nici nu
    //    e chemat — aplicația trimite prin server, iar ruta aceea e interceptată.
    expect(await wallet.calls('submitTx')).toHaveLength(0);
    expect(await wallet.lastSubmittedTx()).toBeUndefined();

    // 5. Ecranul spune „trimis", nu „confirmat". Două stări distincte, fiindcă sunt două lucruri
    //    diferite, iar un ecran care le confundă minte despre finalitate.
    // Propoziția exactă, nu `/submitted/i`: textul introductiv al ecranului conține „submitted", la
    // fel și starea `Signing` („Nothing has been submitted yet."). Aici afirmația nu era vacuă —
    // dovada e corpul interceptat de mai sus — dar un matcher larg peste copy de interfață e
    // greșit oricum, și în `m2-1-chain.spec.js` a costat o rulare întreagă.
    await expect(
      page.getByText('Submitted. The node has it; it is not in a block yet.')
    ).toBeVisible({ timeout: 60_000 });

    // SELECTORUL cu care celelalte teste citesc id-ul tranzacției, verificat AICI — unde nu pleacă
    // nimic pe lanț.
    //
    // A trebuit: cardul arăta id-ul într-un `<code class="font-mono">` până cînd chipul de
    // identificator l-a înlocuit, iar cele trei teste care TRIMIT au început să pice la citirea
    // id-ului, după ce tranzacția plecase deja. Un test care raportează eșec pentru o operație
    // ireversibilă reușită e felul de defect care face pe cineva s-o repete.
    //
    // Acum selectorul trăiește și într-un test care nu trimite, deci se rupe gratis, nu scump.
    const shownTx = await page.locator('[data-copy]').last().getAttribute('data-copy');
    expect(shownTx, 'the submitted card must expose the transaction id').toMatch(/^[0-9a-f]{64}$/);
    await expect(page.getByText(/Confirmed on chain/)).toHaveCount(0);
  });
});
