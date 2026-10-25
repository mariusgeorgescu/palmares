// Configurație separată de `playwright.config.js`, și nu un al doilea proiect în ea, dintr-un
// motiv practic: cea principală pornește un `vite preview` prin `webServer`, iar o suită care
// vizează un deploy n-are ce face cu un server local. Două fișiere sunt mai ieftine decât un
// `webServer` condiționat pe care cineva îl citește greșit la 3 dimineața.
//
// Nu rulează în CI: ținta e un deploy care poate fi oprit, redeployat sau în curs de sincronizare,
// iar o poartă care depinde de asta ar fi roșie din motive care n-au legătură cu commitul.
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e-live',
  workers: 1,
  fullyParallel: false,
  retries: 1,
  reporter: 'list',
  use: {
    baseURL: process.env.PALMARES_LIVE_URL ?? 'https://gov.cardano.vip',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
