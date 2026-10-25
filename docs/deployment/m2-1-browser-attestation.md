# M2-1: o atestare emisă **și contrasemnată din browser**, pe preprod

Ăsta e singurul criteriu din poarta M2 care nu se poate închide fără decizia ta. **Nu din lipsă de
cheie** — asta s-a schimbat pe 25 octombrie — ci fiindcă trimiterea rămâne manuală prin decizia ta,
iar `POST /submit-tx` e singurul pas ireversibil din tot produsul, marcat ca atare în cod
(`MonadInteract.purs`: „ĂSTA e pasul ireversibil").

**Ce s-a schimbat: cheia nu mai lipsește.** Portofelul din `cip30-test-wallet` derivă determinist,
iar adresa lui de pe preprod ținea **53.115 tADA în 56 de UTxO-uri** la 2026-10-25, măsurat prin
Kupo-ul clusterului. Deci nu e nevoie de o cheie nouă, de un mnemonic în mediu, sau de un fișier
commis cu o credențială în el.

**Și semnătura e dovedită.** `e2e-wallet/sign-not-submit.spec.js` rulează împotriva deployului:
wallet-ul semnează cu adevărat, cu cheia lui, pe o tranzacție Conway construită de
`interaction-api` din UTxO-uri reale, iar aplicația trimite martorul la `/submit-tx` cu exact
tranzacția pe care a arătat-o în sumar. Singura diferență față de o rulare adevărată e că ruta aceea
e **interceptată**: octeții nu pleacă.

Deci ce rămâne e literal un pas: scoaterea interceptării. O variabilă o scoate.

## O comandă

```bash
cd frontend
PALMARES_WALLET_URL=https://gov.cardano.vip PALMARES_M2_SUBMIT=1 \
  npx playwright test --config playwright.wallet.config.js e2e-wallet/m2-1-chain.spec.js
```

`PALMARES_M2_SUBMIT=1` nu înseamnă nimic altceva decât „ai voie să trimiți", și nu se pune din
greșeală. Testul face cele trei tranzacții — profil, atestare, acceptare — și așteaptă ca rândul de
pe `/attestations` să arate `accepted`. Cost: taxă măsurată 0,61 tADA pe una dintre ele, plus
min-UTxO blocat în tokenurile create; sub 10 tADA în total.

Dacă preferi să o faci cu mâna, pașii manuali sunt mai jos și sunt aceiași.

## Ce e deja dovedit, și cu ce

| Pasul | Dovada | Unde |
| --- | --- | --- |
| Poarta de wallet refuză fără rețea stabilită | 5 teste pe un provider CIP-30 real | `e2e-wallet/gate.spec.js` |
| Poarta se DESCHIDE pe rețeaua așteptată | același fișier, cu namespace-ul CIP-142 adăugat peste providerul real | idem |
| Poarta de oracol blochează pe `paused` și pe necunoscut | 3 teste unitare | `WriteSpec`, „the oracle gate" |
| Corpul cererii e corect serializat | 4 teste unitare, inclusiv camelCase-ul din `user_addresses` | `WriteSpec`, „the request bodies" |
| Formularul refuză să construiască incomplet | unitare + e2e | `WriteSpec`, `gate.spec.js` |
| Sumarul de semnare citește din tranzacție | 4 teste unitare pe forma JSON a CSL | `WriteSpec`, „R8" |
| Atestarea apare pe `/attestations` cu `accepted` | **se vede deja pe preprod**: din cele 19 atestări, una e acceptată și are o dispută confirmată | `https://gov.cardano.vip/attestations` |
| Ecranul trimite ADRESELE portofelului, nu o listă goală | 1 test de wallet care citește corpul cererii de pe sârmă | `e2e-wallet/gate.spec.js`, „what the build request actually carries" |
| **Serverul CONSTRUIEȘTE tranzacția, pe deploy** | măsurat 2026-10-25: un POST pe `/api/interaction/claim-profile` prin `https://gov.cardano.vip` întoarce CBOR-ul unei tranzacții nesemnate — selecție de intrări reală, politica de minting `648c6a73…`, token de referință CIP-68, datum-ul oracolului | — |
| **Browserul o DECODEAZĂ și arată ce face, pe deploy** | 1 test cu wallet real împotriva `https://gov.cardano.vip`: construiește, citește sumarul (taxă, token, politică), și NU semnează — `signTx` nici nu e atins | `e2e-wallet/build-and-summarise.spec.js` |

Rândul de dinainte e cel care s-a schimbat cel mai mult: până pe 25 octombrie, calea de scriere
**nu exista în cluster** (`replicas: 0`) și ecranul trimitea oricum adrese goale, deci niciun pas de
aici nu era dovedit pe deploy. Acum tot drumul până la semnătură e parcurs pe deployul real:
provider `node + Kupo`, cele cinci scripturi de referință rezolvate, intrări alese, tranzacție
întoarsă. Ce rămâne e **exact semnătura și trimiterea**, nimic altceva.

Ultimul rând contează: drumul `issue → accept → /attestations cu accepted` **a fost parcurs pe
preprod**, de `smoke_attest_flow.sh`. Ce n-a fost parcurs **din browser** e exact ce cere M2-1.

## Ce trebuie să faci

Ai nevoie de o cheie de preprod cu fonduri (≈15 tADA acoperă min-UTxO plus taxele pentru cele două
tranzacții) și de un wallet de browser care:

- expune **CIP-95** — altfel revendicarea de credențială nu se poate dovedi; și
- fie expune **CIP-142**, fie e unul dintre wallet-urile cu o singură rețea de test din
  `Capabilities.Wallet.Governance.singleTestnetWallets` (acum: Yoroi-extensie).

Dacă wallet-ul tău nu e în niciuna din cele două categorii, poarta îl va refuza **și îți va spune
exact de ce**, cu matricea celor trei forme de detecție — asta e comportamentul cerut de R6, nu un
defect.

### Pașii

1. Pornește stack-ul, sau folosește deployul:

   ```bash
   # local, de la zero — vezi README §„Everything at once"
   docker compose --profile app --profile write up -d
   # sau direct pe deploy:
   open https://gov.cardano.vip/write?flow=issue-attestation
   ```

2. Conectează wallet-ul. Verifică matricea: CIP-95 trebuie să fie „yes" pe coloana **Actually
   present**, nu doar pe „Advertised".

3. **Emite atestarea.** Completează subiectul (identificatorul unui profil existent — ia unul de pe
   `/profiles`), emitentul (profilul tău), felul, numele, descrierea și URI-ul imaginii. Apasă
   „Build the transaction".

4. **Citește sumarul.** Trebuie să vezi ce token se creează, sub ce politică, ce taxă se plătește și
   câte semnături suplimentare sunt cerute. Dacă nu-l vezi, **nu semna** — ecranul refuză singur
   când nu poate decoda, iar dacă ai ajuns aici fără sumar e un defect de raportat.

5. **Semnează și trimite.** Wallet-ul cere semnătura; trimiterea merge prin `/submit-tx`.

6. **Acceptă, cu wallet-ul SUBIECTULUI.** `/write?flow=accept-attestation&subject=<id>`. Doar
   subiectul poate — dacă încerci cu alt wallet, serverul refuză, iar asta e unul dintre refuzurile
   pe care M2-5 le cere documentate.

7. **Verifică pe `/attestations`.** Rândul trebuie să arate „accepted". Dacă db-sync e încă în urmă,
   banda de sus îți spune cu cât — rândul apare când proiecția ajunge la slotul tranzacției.

### Ce se măsoară, ca să fie o dovadă și nu o impresie

Notează, pentru jurnal: cele două `txId`-uri, taxa fiecăreia, și timpul până când rândul a apărut pe
`/attestations`. Al treilea e singurul care spune ceva despre lanțul de proiecții, nu doar despre
tranzacții.

## De ce nu e automatizat

`cip30-test-wallet` are un **mod chain** care citește UTxO-uri reale de la Ogmios sau Koios și
trimite cu adevărat. Cu el, pașii 2–5 s-ar putea rula dintr-un test. Nu e pornit aici din două
motive, amândouă ale tale de decis:

1. **cheia.** Un test care semnează are nevoie de o cheie finanțată, iar punerea ei la îndemâna unui
   test o face parte din mediul de rulare.
2. **trimiterea rămâne manuală**, prin decizia ta din sesiunea asta.

Dacă vrei automatizat: spune ce cheie, iar suita de wallet capătă un al treilea fișier, cu modul
chain pornit și marcat să nu ruleze implicit.
