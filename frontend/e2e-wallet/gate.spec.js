// Poarta de wallet, împotriva unui wallet CIP-30 ADEVĂRAT.
//
// `cip30-test-wallet` injectează un provider care ține chei reale, întoarce CBOR real de UTxO și
// semnează cu o semnătură Ed25519 reală. Față de un mock scris de noi, diferența e că aici se
// testează ce face CODUL NOSTRU cu un obiect pe care nu l-am construit noi — inclusiv ce face cînd
// o extensie e anunțată dar lipsește de pe conexiune.
//
// **Wallet-ul anunță CIP-95 și NU anunță CIP-142**, pentru că niciun wallet din ecosistem nu-l
// implementează încă: „Path to Active" din CIP-142 listează „implementează extensia în Lace" ca pas
// VIITOR. Asta nu e o limitare a uneltei, e starea lumii — și e exact motivul pentru care poarta
// noastră are o matrice în loc de un „da/nu".
import { expect, test } from 'cip30-test-wallet/playwright';
import { connectFromNavbar } from './connect.js';

const WALLET = 'palmaresTestWallet';

test.use({ walletOptions: { name: WALLET, networkId: 0 } });

test.describe('a real CIP-30 wallet without CIP-142', () => {
  test('is refused before the form, with the reason and the matrix', async ({ page }) => {
    await page.goto('/write?flow=claim-profile');

    // Niciun cîmp pînă nu trece poarta.
    await expect(page.getByRole('textbox')).toHaveCount(0);

    await connectFromNavbar(page, WALLET);

    await expect(page.getByText('cannot write')).toBeVisible();
    await expect(page.getByText(/unless the wallet supports the CIP-142/)).toBeVisible();
    await expect(page.getByText(/did not choose, so nothing will be built/)).toBeVisible();

    // Matricea, cu cele trei forme de detecție una lîngă alta. CIP-95 e prezent pe conexiune,
    // CIP-142 nu e nicăieri — și asta se vede pe rînduri, nu într-un mesaj.
    const cip95 = page.getByRole('row', { name: /CIP-95/ });
    const cip142 = page.getByRole('row', { name: /CIP-142/ });
    await expect(cip95.getByText('yes').first()).toBeVisible();
    await expect(cip142.getByText('no').first()).toBeVisible();

    // Și tot niciun formular.
    await expect(page.getByRole('textbox')).toHaveCount(0);
  });

});

test.describe('the user declines the connection', () => {
  // Cel mai frecvent lucru pe care îl prind testele astea: erorile CIP-30 sînt `{code, info}`, nu
  // `Error`, iar un dApp care nu le tratează rămîne pur și simplu agățat. Aici se verifică că
  // ecranul își revine și SPUNE ce s-a întîmplat, în loc să rămînă pe „Connecting…".
  test.use({ walletOptions: { name: WALLET, networkId: 0, quirks: { enableRejected: true } } });

  test('leaves the screen usable, not stuck on Connecting', async ({ page }) => {
    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);

    // Mesajul vine ca notificare, din înveliș. Până la patch-ul din bibliotecă nu venea deloc:
    // `enable` arunca înăuntrul componentei de wallet, handler-ul murea acolo, și apăsarea pe
    // „Connect" n-avea NICIUN efect vizibil — exact forma pe care comentariile din acest proiect o
    // numesc fund de sac.
    await expect(page.getByText(/did not connect/)).toBeVisible();
    // Și butonul rămâne apăsabil: cineva care a apăsat „Decline" din greșeală trebuie să poată
    // încerca din nou fără să reîncarce pagina.
    await expect(page.getByRole('button', { name: /Connect/ }).first()).toBeEnabled();
  });
});

test.describe('the same wallet, with the CIP-142 namespace the CIP defines', () => {
  // Decorația e un SUBSTITUT pentru un wallet care nu există încă, și e scrisă aici ca atare:
  // peste providerul real se adaugă exact namespace-ul pe care CIP-142 îl specifică, nimic
  // altceva. Fără ea, calea în care poarta se DESCHIDE n-ar putea fi testată de nimeni pînă cînd
  // un wallet din ecosistem implementează extensia.
  const withCip142 = (magic) => async (page) => {
    await page.addInitScript(
      ([walletName, m]) => {
        const install = () => {
          const w = window.cardano?.[walletName];
          if (!w || w.__cip142Patched) return false;
          w.__cip142Patched = true;
          const original = w.enable.bind(w);
          w.enable = async (opts) => {
            const api = await original(opts);
            api.cip142 = { getNetworkMagic: async () => m };
            return api;
          };
          const exts = w.supportedExtensions ?? [];
          w.supportedExtensions = [...exts, { cip: 142 }];
          return true;
        };
        if (!install()) {
          const timer = setInterval(() => {
            if (install()) clearInterval(timer);
          }, 25);
        }
      },
      [WALLET, magic]
    );
  };

  test('opens the gate on the expected network, and the form appears', async ({ page }) => {
    await withCip142(1)(page); // 1 = preprod, per CIP-142
    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);

    await expect(page.getByText('ready')).toBeVisible();
    // Abia acum apar cîmpurile — asta e tot ce afirmă poarta.
    await expect(page.getByRole('textbox').first()).toBeVisible();
    await expect(page.getByRole('button', { name: /Build the transaction/ })).toBeVisible();
  });

  test('refuses a wallet on another network, naming both', async ({ page }) => {
    await withCip142(764824073)(page); // mainnet
    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);

    await expect(page.getByText('cannot write')).toBeVisible();
    await expect(page.getByText(/764824073/)).toBeVisible();
    await expect(page.getByText(/this deployment is on 1/)).toBeVisible();
    await expect(page.getByRole('textbox')).toHaveCount(0);
  });

  test('will not build while a required field is empty', async ({ page }) => {
    await withCip142(1)(page);
    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);
    await expect(page.getByText('ready')).toBeVisible();

    await expect(page.getByRole('button', { name: /Build the transaction/ })).toBeDisabled();
    await expect(page.getByText(/required field\(s\) still empty/)).toBeVisible();
  });
});

test.describe('what the build request actually carries', () => {
  // Testul ăsta a fost scris pentru un defect pe care nimic altceva nu-l putea prinde: ecranul
  // trimitea `user_addresses: []` și `change_address: ""`, fiindcă pasul „citește adresele din
  // portofel" lipsea pur și simplu. Unitarele treceau — ele verifică serializarea corpului, nu de
  // unde vin valorile — iar suita de fixturi n-are portofel. Se vedea doar aici: un wallet real,
  // apăsat pe butonul real, cu corpul cererii citit de pe sîrmă.
  //
  // Adresele contează: serverul alege intrările și dă restul pe baza lor. Cu ele goale, nicio
  // tranzacție nu se putea construi, pe nicio rețea.
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

  test('sends the wallet own address, not an empty list', async ({ page, wallet }) => {
    await withCip142(page);

    // Corpul se citește de pe sîrmă, nu din starea componentei: ce ajunge la server e singurul
    // lucru care contează.
    const bodies = [];
    // DOAR ruta de construire: un `**` peste tot interaction-api ar prinde și interogarea
    // oracolului, iar poarta de oracol ar bloca pe bună dreptate pe „nu știm dacă e pauzat" —
    // adică testul n-ar mai ajunge niciodată la buton.
    await page.route('**/api/interaction/claim-profile', async (route) => {
      bodies.push(route.request().postDataJSON());
      // Se oprește aici: ce face serverul cu cererea e altă întrebare, iar un răspuns adevărat ar
      // lega testul de starea lanțului.
      await route.fulfill({ status: 503, contentType: 'application/json', body: '{}' });
    });

    await page.goto('/write?flow=claim-profile');
    await connectFromNavbar(page, WALLET);
    await expect(page.getByText('ready', { exact: true })).toBeVisible();

    // „Kind" e un <select>, nu un <input>: `fill` pe el dă „Element is not an <input>". Varianta
    // dinainte a testului a căzut exact aici.
    await page.getByLabel('Kind', { exact: false }).first().selectOption('person_d_rep');
    await page.getByLabel('Name', { exact: false }).first().fill('gate-address-check');
    await page.getByLabel('Description', { exact: false }).first().fill('reads the wallet address');
    await page.getByLabel('Image URI', { exact: false }).first().fill('ipfs://gate-check');

    const build = page.getByRole('button', { name: /Build the transaction/ });
    await expect(build).toBeEnabled();
    await build.click();

    await expect.poll(() => bodies.length, { timeout: 30_000 }).toBeGreaterThan(0);
    const body = bodies[bodies.length - 1];

    // Adresa de rest e cea a portofelului, nu un string gol. `wallet.addresses.payment` e bech32,
    // iar CIP-30 întoarce hex — deci comparația se face pe ce a cerut codul de la portofel și pe ce
    // a ajuns în corp, nu pe forma bech32.
    const asked = await wallet.calls('getChangeAddress');
    expect(asked.length).toBeGreaterThan(0);
    // Cheile: `user_addresses` e snake_case la exterior, dar camelCase în interior — vezi
    // `Capabilities.Interaction.Types`.
    const addrs = body.user_addresses;
    expect(addrs.changeAddress).toBe(asked[asked.length - 1].result);
    expect(addrs.changeAddress).not.toBe('');
    expect(addrs.usedAddresses.length).toBeGreaterThan(0);
    expect(addrs.usedAddresses).toContain(addrs.changeAddress);
  });
});
