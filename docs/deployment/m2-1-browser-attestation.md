# M2-1: o atestare emisă **și contrasemnată din browser**, pe preprod

> **ÎNCHIS pe 2026-10-25.** Patru tranzacții, toate semnate în browser de un wallet CIP-30, toate
> construite de `interaction-api` pe deployul `gov.cardano.vip`, toate proiectate în registru.
>
> | pasul | tranzacția | slot |
> | --- | --- | --- |
> | profil subiect (`person_d_rep`) | `773d343a9907613a6d2dc255bb1de9a03139fc01498d12f7967e3434b9c2d21c` | 137275620 |
> | profil emitent (`auditor`) | `80f97ede58c5bcaf89874b9ceeeac83523725a3aace167a62316e4c608c403bb` | 137276653 |
> | atestarea | `e0a360a11f8c9cb6859a3334426938f0c8f92d506fbbca09a3ca3ceca04ccf93` | — |
> | contrasemnătura | `a2ccfdbc6028f449f5067fd068d6632cdfa60d06e3314889c2e16112db877d69` | 137278322 |
>
> Rezultatul: `m2-1-1792961388736-attestation`, `kind: endorsement`, **`accepted: true`**, pe
> `https://gov.cardano.vip/attestations`. Registrul: 12→14 profiluri, 19→20 atestări, **zero**
> intrări în `attest_dead_letter`.
>
> **Latența proiecției, măsurată: 45 de secunde** de la „trimis" până când rândul arată `accepted`.
> Singurul număr care spune ceva despre lanțul de proiecții și nu doar despre tranzacții.
>
> **Patru tranzacții, nu trei**, și motivul e o regulă on-chain: `traceIfFalse "Mr"
> (isCredentialKind || subject /= issuer)` — *o atestare nu poate fi auto-emisă*. Un singur profil
> nu ajunge, deci a trebuit un al doilea ca emitent. Un portofel poate deține oricâte profiluri,
> deci nu a trebuit un al doilea portofel: aceeași cheie a semnat emiterea (tokenul emitentului) și
> acceptarea (tokenul subiectului).
>
> **Testul e reluabil**, și a trebuit să fie: `PALMARES_M2_PROFILE_ID`,
> `PALMARES_M2_ISSUER_PROFILE_ID`, `PALMARES_M2_ATTESTATION_ID`. Fiecare pas costă o tranzacție
> ireversibilă, iar fără reluare fiecare defect de test ar fi cerut re-mintarea a tot ce era deja pe
> lanț.

## Cele două care nu se pot închide de aici

Niciuna nu e muncă neterminată. Fiecare așteaptă ceva ce codul nu poate produce.

### `resolve-dispute` — cheia adminului oracolului

Ruta întoarce deliberat o tranzacție **nesemnată**: validatorul oracolului cere semnătura adminului,
iar *„no admin action is accepted over HTTP"* (`RestAPI.hs`). Un browser obișnuit nu o poate
încheia, și asta e intenția arhitecturii.

Ce e dovedit: ruta construiește o tranzacție adevărată, sumarul ei se decodează, iar sumarul spune
*„1 signature required beyond the inputs"* — singurul loc din interfață care explică de ce fluxul se
oprește acolo. Vezi `e2e-wallet/all-flows-sign.spec.js`.

Pentru a o încheia: semnează tranzacția întoarsă cu cheia al cărei hash e
`5a0ea8b28def0497f0954af950abf61097da9fed0079811605bb70b8` și trimite-o. Disputa deschisă azi e
`648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3.000020e04c424d3b3f36062346a4ca5de6f7f0f27d84e1f9d4ea82e890aed512`.

### `expire-dispute` — **2026-11-24**

Nu cere nicio autoritate — *„that is the point, since an exit the oracle admin can gate is not an
exit"* — dar cere ca termenul să fi trecut. `dispute_timeout_ms` e 2.592.000.000 ms, adică 30 de
zile de la deschidere. Disputa de mai sus a fost deschisă pe 2026-10-25, deci devine expirabilă pe
**24 noiembrie 2026**.

Până atunci serverul refuză cu `DisputeNotStaleYet`, „its deadline has not passed", iar refuzul e
testat ca atare — e singura afirmație posibilă azi.

**Comanda, pentru ziua aceea.** Nu cere nicio cheie și nicio autoritate:

```bash
cd frontend
PALMARES_WALLET_URL=https://gov.cardano.vip PALMARES_FLOWS_SUBMIT=1 \
  PALMARES_FLOWS_SKIP_UPDATE=1 PALMARES_FLOWS_SKIP_CLAIM=1 \
  PALMARES_FLOWS_SKIP_WITHDRAW=1 PALMARES_FLOWS_SKIP_DISPUTE=1 \
  npx playwright test --config playwright.wallet.config.js e2e-wallet/expire-dispute-chain.spec.js
```

**Fișierul există și e sărit până atunci.** Argumentasem întâi că un test care nu poate trece o lună
„se strică în tăcere" — și era inconsecvent: `m2-1-chain.spec.js` trăia deja exact așa. Un test
sărit e vizibil în raport, poate fi citit azi, și rulează într-o comandă în ziua în care are ce face;
unul nescris nu e niciunul din lucrurile astea.

Rulat prea devreme, se sare cu motivul și cu DATA, nu cu un eșec obscur — verificat azi:

> The deadline has not passed yet, so there is nothing to expire. The server says:
> `{"code":"DisputeNotStaleYet",...}` — dispute 82e890aed512 opened 2026-10-25, expirable from
> 2026-11-24.

Garda întreabă serverul înainte de orice, cu adrese REALE: cu adrese goale serverul se oprește la
validarea formei și nu ajunge să se uite la termen, iar testul ar fi căzut obscur în loc să spună
data. Criteriul final e că rândul arată `expired` — nu `upheld` și nu `dismissed`, fiindcă o expirare
nu e o constatare împotriva niciuneia dintre părți.

## Cele nouă fluxuri: unde ajunge fiecare

Măsurat pe deploy la 2026-10-25. **Șapte din nouă sînt pe lanț, din browser.** Celelalte două sînt
acoperite cât se poate, iar forma acoperirii lor e tot ce se poate afirma — amândouă prin design.

| fluxul | unde ajunge | tranzacția |
| --- | --- | --- |
| `claim-profile` | **pe lanț** | `773d343a…b9c2d21c` (subiect), `80f97ede…08c403bb` (emitent) |
| `issue-attestation` | **pe lanț** | `e0a360a1…ca04ccf93` |
| `accept-attestation` | **pe lanț** | `a2ccfdbc…db877d69` |
| `update-profile` | **pe lanț** | `e01b7b28…7fed1b9a` · proiectat în 30 s |
| `claim-credential` | **pe lanț** | `871750b8…cb1041a67` · proiectat în 15 s |
| `withdraw-credential` | **pe lanț** | `fe7bf7a1…ad62c2d3` · proiectat în 75 s |
| `open-dispute` | **pe lanț** | `3854e09d…312701fb` · proiectat în 15 s · 5 tADA blocate |
| `resolve-dispute` | se construiește, nu se semnează | semnătura e a adminului oracolului |
| `expire-dispute` | se refuză corect | `DisputeNotStaleYet`: termenul e la 30 de zile |

Latențele de proiecție măsurate: **15–75 de secunde**, iar cea de 45 s de la acceptare e în mijloc.
Nu există lentoare de proiecție — ce părea lentoare era pagina care nu reinterogează.

**`resolve-dispute`** ajunge la o tranzacție adevărată și la sumarul ei decodat, iar sumarul spune
singurul lucru care explică de ce fluxul nu se poate încheia dintr-un browser obișnuit:
*„1 signature required beyond the inputs"*. Ruta întoarce deliberat o tranzacție **nesemnată**,
fiindcă validatorul oracolului cere adminul și *„no admin action is accepted over HTTP"*
(`RestAPI.hs`). Semnarea ar cere `operation.prv`.

**`expire-dispute`** nu cere nicio autoritate — *„that is the point, since an exit the oracle admin
can gate is not an exit"* — dar cere ca termenul să fi trecut. Serverul refuză cu
`DisputeNotStaleYet`, „its deadline has not passed", iar ecranul arată motivul în cuvinte. Refuzul
ăsta e o afirmație la fel de bună ca o reușită, și e singura posibilă azi: disputa deschisă mai sus
devine expirabilă pe 2026-11-24.

Suitele: `all-flows-sign.spec.js` (toate nouă, fără trimitere), `m2-1-chain.spec.js` și
`remaining-flows-chain.spec.js` (trimiterile, fiecare după un flag explicit).

## Cele șase defecte, niciunul prins de un test care trecea

Rularea a cerut șase reparații. **Cinci erau în teste, una în produs** — iar cea din produs e
singura pe care un om ar fi văzut-o imediat și pe care niciun test n-ar fi văzut-o vreodată.

1. **Ecranul trimitea adrese goale.** `usedAddresses: []`, `changeAddress: ""` — serverul alege
   intrările pe baza lor, deci nicio tranzacție nu se putea construi, pe nicio rețea. *În produs.*
   Unitarele verificau serializarea corpului, nu de unde vin valorile; fixturile n-au portofel.
2. **Două selectoare citeau id-ul greșit.** `/profiles` e o listă de carduri: un `div` prea larg
   întorcea id-ul PRIMULUI profil, nu al celui nou. Pe `/attestations`, id-ul atestării nu e în rând
   deloc — cele două valori monospațiate sînt subiectul și emitentul, trunchiate cu elipsă. Ambele
   reparate citind id-ul din adresa linkului „Edit" / „Accept", care e și calea unui om.
3. **O afirmație vacuă a anulat semnarea.** `getByText(/submitted/i)` prinde textul introductiv al
   ecranului — „nothing here is submitted on your behalf" — ÎNAINTE de orice semnătură. Testul
   trecea instantaneu, naviga, iar navigarea anula semnarea în curs: zece minute, zero tranzacții,
   pas „verde".
4. **Ecranele registrului nu reinterogează.** Datele se cer o dată, la montare. Un
   `expect(...).toBeVisible()` pe o pagină încărcată înainte de proiecție așteaptă pe un DOM
   înghețat — a așteptat 25 de minute pe un profil care era deja în API. Reparat prin reîncărcare în
   buclă. **Și e o observație despre produs:** cine mintuiește trebuie să reîncarce ca să vadă.
5. **O atestare auto-emisă, refuzată pe lanț** cu `Mr PT5`. Presupusesem că „subiect == emitent" e
   validă fiindcă revendicările de credențială o folosesc — dar acelea sînt `isCredentialKind`, iar
   scutirea aceea e chiar motivul pentru care restul nu sînt scutite. Ecranul a arătat codul de
   trace corect; greșeala era a testului.
6. **`page` nu era în scope** în helper-ul pe care l-am mutat în scope-ul `describe`. A picat DUPĂ
   ce atestarea plecase deja — de unde a treia variabilă de reluare.

Ce rămâne mai jos e istoria de dinainte de închidere, păstrată pentru ce dovedește FĂRĂ a trimite
nimic: `build-and-summarise.spec.js`, `sign-not-submit.spec.js` și `m2-1-preflight.spec.js` rămân
valoroase exact pentru că nu ating lanțul.

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
