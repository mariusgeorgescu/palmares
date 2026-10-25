// Configurația e2e. Rulează pe bundle-ul __demo__ (`MainDemo`), adică pe fixturi: fără backend,
// fără lanț, fără wallet. De aceea testele pot asserta cifre exacte — sunt payload-uri măsurate,
// înregistrate, nu date vii care se schimbă între rulări.
//
// `vite preview` servește `dist`, iar `dist` e construit de `npm run build` (nu `build:prod`, care
// împachetează `Main` cu HTTP real).
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  // Un singur worker: suita e scurtă, iar un server de preview partajat n-are nevoie de
  // paralelism ca să termine în câteva secunde.
  workers: 1,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: {
    // `--host 127.0.0.1` nu e decor: fără el, `vite preview` ascultă pe `localhost`, care aici
    // rezolvă la ::1, iar verificarea pe 127.0.0.1 nu primește niciodată răspuns.
    command: 'npx vite preview --port 4173 --strictPort --host 127.0.0.1',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
