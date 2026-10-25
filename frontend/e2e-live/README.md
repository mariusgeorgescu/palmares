# Suita „live"

Rulează împotriva unui DEPLOY, nu a fixturilor: `npm run e2e:live`, sau cu
`PALMARES_LIVE_URL=…` către altă țintă.

Ce verifică sunt **invariantele integrării** — lucrurile adevărate indiferent câte date are lanțul:
rutele se servesc și SPA-ul pornește pe ruta cerută direct, o cale inexistentă dă „Not found",
`/api/query` răspunde în același origin prin BFF, cele opt headere de prospețime ajung la browser,
nimic nu derulează lateral la 390px, iar metodologia se umple din API-ul viu.

## De ce nu așteaptă `networkidle`

Pe baza vie, `/activity` răspunde în **minute**, nu în secunde — măsurat 2026-10-25, cu db-sync la
epoca 212 din 321:

| Rută | Deploy (mid-sync) | Bază locală sincronizată |
| --- | --- | --- |
| `/api/query/activity?limit=100` | **332 s** | 0,8 s |
| `/api/query/pages/dashboard` | 0,76 s | 0,26 s |

Nu e un index lipsă: aceeași interogare, pe o bază cu MAI MULTE date dar fără scrieri concurente,
răspunde sub o secundă. E presiunea de scriere a lui db-sync care încă reface istoria. **De
re-măsurat când sincronizarea se termină** — dacă rămâne așa, atunci e o problemă de interogare, nu
de sarcină.

Testele de derulare laterală așteaptă `domcontentloaded` plus bara de navigare, nu `networkidle`:
altfel expiră pe latența serverului în loc să măsoare derularea, iar ce măsoară ele — cadrul
paginii — e desenat înainte de date. Tabelul plin e acoperit de suita pe fixturi.
