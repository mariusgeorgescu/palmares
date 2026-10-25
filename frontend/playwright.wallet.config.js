// Suita cu wallet, separată de celelalte două dintr-un motiv practic: `cip30-test-wallet` își
// exportă propriul `test`, cu fixture-ul care injectează providerul, iar amestecarea lui cu
// `test`-ul din `@playwright/test` în același proiect face ca jumătate din teste să ruleze fără
// wallet fără să spună nimeni nimic.
//
// Rulează pe bundle-ul de PRODUCȚIE, nu pe cel demo, și asta e esențial: `DemoM` înlocuiește
// poarta de wallet cu un mock care refuză mereu, deci o suită de wallet pe bundle-ul demo ar testa
// mock-ul, nu codul. Prima versiune a suitei ăsteia a făcut exact asta și a „trecut" fără să
// atingă nimic real.
//
// Deci: `npm run build:prod`, servit prin BFF către query-api și interaction-api locale, și abia
// atunci wallet-ul injectat întîlnește `connectGovernanceDefault` adevărat. Vezi `e2e-wallet/README`.
//
// CELE DOUĂ SUITE ÎMPART `dist`, și asta e o capcană măsurată: după un `build:prod`, suita de
// fixturi cade în bloc, fiindcă serverul ei de preview servește bundle-ul de producție. De aceea
// fiecare suită se rulează prin scriptul ei din `package.json` — `npm run e2e:fixtures` și
// `npm run e2e:wallet` — care CONSTRUIEȘTE bundle-ul potrivit înainte. Un `npx playwright test`
// direct nu o face, și pică.
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e-wallet',
  workers: 1,
  fullyParallel: false,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: process.env.PALMARES_WALLET_URL ?? 'http://127.0.0.1:4176',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  // Fără `webServer`: BFF-ul are nevoie de cele două API-uri în spate, iar pornirea lui dintr-un
  // config de teste ar ascunde exact dependența care contează. Comanda e în `e2e-wallet/README.md`.
});
