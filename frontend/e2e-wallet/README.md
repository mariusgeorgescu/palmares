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

## Ce NU acoperă

**CIP-142 nu există în niciun wallet.** „Path to Active" din CIP-142 listează implementarea în Lace
ca pas *viitor*, iar `cip30-test-wallet` anunță doar CIP-95. Calea în care poarta se DESCHIDE e
testată peste un provider real căruia testul îi adaugă exact namespace-ul pe care CIP-142 îl
specifică — un substitut pentru un wallet care nu există încă, scris ca atare în test.

**M2-1 — o atestare emisă și contrasemnată pe preprod — nu e aici.** Ar cere o cheie finanțată și
trimiterea unei tranzacții reale, iar trimiterea rămîne manuală prin decizia ownerului. Ce se poate
testa fără ea se testează: poarta, formularul, construirea.
