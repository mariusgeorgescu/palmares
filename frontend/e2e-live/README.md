# Suita „live"

Rulează împotriva unui DEPLOY, nu a fixturilor: `npm run e2e:live`, sau cu
`PALMARES_LIVE_URL=…` către altă țintă.

Ce verifică sunt **invariantele integrării** — lucrurile adevărate indiferent câte date are lanțul:
rutele se servesc și SPA-ul pornește pe ruta cerută direct, o cale inexistentă dă „Not found",
`/api/query` răspunde în același origin prin BFF, cele opt headere de prospețime ajung la browser,
nimic nu derulează lateral la 390px, iar metodologia se umple din API-ul viu.

## De ce nu așteaptă `networkidle`

| Rută | Deploy, indexuri lipsă | Deploy, indexuri aplicate | Bază locală sincronizată |
| --- | --- | --- | --- |
| `/api/query/activity?limit=100` | **332 s** | **2,0 s** | 0,8 s |
| `/api/query/pages/dashboard` | 0,76 s | 0,30 s | 0,26 s |

**ERA un index lipsă, și nu doar unul: 22 din 24.** Prima variantă a tabelului ăsta spunea „nu e un
index lipsă: aceeași interogare, pe o bază cu MAI MULTE date, răspunde sub o secundă" și punea cele
332 de secunde pe presiunea de scriere a db-sync-ului. Greșit, în direcția cea mai ușoară: baza
locală AVEA indexurile, deployul nu — `sql/indexes/001_gov_indexes.sql` se aplică printr-un Job pe
care nimeni nu-l scrisese în apps-k8s-configs, deci nu rulase niciodată. `/api/query/status`
raporta câmpul `missing_indexes` plin tot timpul, iar nimeni nu se uitase la el.

Cu Job-ul aplicat: 332 s → 2,0 s, pe aceeași bază, cu db-sync scriind în continuare. Lecția e
despre comparație, nu despre Postgres: două baze care diferă prin mai mult decât ipoteza nu pot
respinge ipoteza.

Latența rămasă (2,0 s față de 0,8) e plauzibil presiunea de scriere. **De re-măsurat când
sincronizarea se termină** — dar nu mai e un ecran blocat, ci o interogare lentă.

Testele de derulare laterală așteaptă `domcontentloaded` plus bara de navigare, nu `networkidle`:
altfel expiră pe latența serverului în loc să măsoare derularea, iar ce măsoară ele — cadrul
paginii — e desenat înainte de date. Tabelul plin e acoperit de suita pe fixturi.
