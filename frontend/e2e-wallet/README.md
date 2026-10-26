# Suita cu wallet

Ce testează: **poarta de wallet** (CIP-95 / CIP-142, rețeaua, refuzurile) împotriva unui provider
CIP-30 adevărat, injectat de [`cip30-test-wallet`](https://www.npmjs.com/package/cip30-test-wallet)
(Apache-2.0). Wallet-ul ține chei reale, întoarce CBOR real și semnează cu Ed25519 real.

## De ce nu rulează pe bundle-ul demo

`DemoM` înlocuiește `connectGovernance` cu un mock care refuză mereu. O suită de wallet pe
bundle-ul demo testează mock-ul, nu codul — prima versiune a suitei ăsteia a făcut exact asta și a
„trecut" fără să atingă nimic real. De aceea rulează pe bundle-ul de **producție**, prin BFF.

## Cum se rulează

```bash
# 1. query-api si interaction-api locale (vezi memoria „preprod sincronizat local")
# 2. bundle-ul de productie + BFF
npm run build:prod
PALMARES_QUERY_API_URL=http://127.0.0.1:8083 \
PALMARES_INTERACTION_API_URL=http://127.0.0.1:8082 \
PALMARES_INTERACTION_API_USER=smoke PALMARES_INTERACTION_API_PASS=smoke-devonly \
PORT=4176 node bff/server.js &

# 3. suita
npm run e2e:wallet
```

`PALMARES_WALLET_URL` schimbă ținta.

## Cele două porți, și de ce există

Suita are 22 de teste în trei straturi. Rulată fără niciun flag, **zece se sar** — iar reporterul
`line`/`list` nu afișează motivul sărituri, deci rularea arată „10 skipped" fără să spună de ce.
S-a citit deja o dată ca „cod netestat" când de fapt era „flag nepus", de-aia e scris aici:

| Strat                       | Poartă                     | Ce face                                                |
| --------------------------- | -------------------------- | ------------------------------------------------------ |
| poarta, formularele, DOM-ul | niciuna                    | 12 teste; nu ating lanțul                               |
| construire + semnare        | `PALMARES_WALLET_FUNDED=1`  | încă 7; cer UTxO-uri, fiindcă selecția de intrări e a serverului. **Nu trimit nimic.** |
| trimitere pe lanț           | `PALMARES_FLOWS_SUBMIT=1`   | ultimele 3; tranzacții **ireversibile** pe preprod      |

`npm run e2e:wallet` pune deja `PALMARES_WALLET_FUNDED=1` — adică rulează tot ce se poate rula fără
să trimită nimic: **19 trecute, 3 sărite**. A doua poartă se pune mereu de mână, prin decizia
ownerului că trimiterea rămîne manuală.

`expire-dispute-chain.spec.js` mai cere, peste a doua poartă, o dispută al cărei **termen a trecut**;
altfel se sare cu un mesaj care numără disputele nedecise și citează refuzul serverului textual.

## Ce NU acoperă

**CIP-142 nu există în niciun wallet.** „Path to Active" din CIP-142 listează implementarea în Lace
ca pas *viitor*, iar `cip30-test-wallet` anunță doar CIP-95. Calea în care poarta se DESCHIDE e
testată peste un provider real căruia testul îi adaugă exact namespace-ul pe care CIP-142 îl
specifică — un substitut pentru un wallet care nu există încă, scris ca atare în test.

**Trimiterea nu se face singură.** Cele trei fișiere din stratul al treilea stau sărite pînă cînd
cineva pune `PALMARES_FLOWS_SUBMIT=1` cu mîna. Asta nu e o lipsă de acoperire: e decizia ownerului
că trimiterea rămîne manuală, iar o tranzacție ireversibilă nu se declanșează dintr-o rulare de
rutină.

Istoric: M2-1 a fost multă vreme în secțiunea asta ca „nu e aici". Acum **este** —
`m2-1-chain.spec.js` a emis o atestare, a contrasemnat-o și a văzut registrul arătînd `accepted`,
pe preprod. Toate cele nouă fluxuri de scriere au trecut pe lanț.
