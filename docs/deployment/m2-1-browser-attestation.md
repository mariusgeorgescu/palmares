# M2-1: o atestare emisă **și contrasemnată din browser**, pe preprod

Ăsta e singurul criteriu din poarta M2 pe care nu-l poate închide nimeni în afară de deținătorul
unei chei finanțate. Totul până la semnătură e construit și testat; ce lipsește e **semnătura
însăși și trimiterea**, iar `scripts/smoke_attest_flow.sh` spune de ce repo-ul nu livrează un
semnatar: *„this repo ships no signer, and a signer guessed here would be a"* — o cheie scrisă
într-un fișier commis e o credențială care se publică.

Documentul ăsta e pregătirea, ca rularea să coste o comandă.

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
