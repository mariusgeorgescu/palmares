# Multi-perspective review — judged at `7aaa144` (2026-10-29)

Twenty-nine agents over fourteen perspectives, each perspective's findings handed to an independent
skeptic whose reward was catching the false ones. **45 confirmed, 24 partly, zero refuted, five
unverifiable.** Zero refuted is itself a caution rather than a result; the eight findings the
coordinator re-derived personally all held, which is the only reason the rest are treated as
load-bearing.

**Read this first: eleven of the findings were fixed in `7749d16`.** This report is the frozen
record of what the review found. The rows below are what it found and **did not** fix, which is the
backlog. Everything marked FIXED here is recorded so the next reader does not re-find it.

The one structural limit, stated before anything else: **no screen was ever observed.** The local
stack was down and the deployed frontend was mid-rollout, so every claim about the interface is
derived from PureScript source plus live read-only API measurement, never from a rendered page.

## The theme that explained half the list

> **The repositioning changed the words and not the wiring.**

`a5fdc71` and `7aaa144` rewrote the title, hero, blurbs, nav labels and brand, and added one filter
constant. Nothing underneath moved: no query, no table column, no decoder field, no link target, no
README sentence. So the new first promise — proof of credential control — was stated in six places
and implemented in none of the screens it named. Six of the seven highest findings were in code or
copy written the day before.

The second theme is the inverse of the usual triage: **the backend is a generation ahead, and the
gap is one record field per case.** Every expensive-looking finding turned out to be a route that
already exists, is documented, measures correct, and has zero call sites. A missing screen over a
working route is an afternoon; only three things in the whole set were genuinely unbuilt.

## Fixed in `7749d16`

| What | Where it stood |
|---|---|
| Five strings said the challenger forfeits the deposit | `D4` pays it back in the SHARED closing definition, so it returns on all three verdicts. One of the five was the alert above the Sign button, with the real amount in it. The specification instructs the UI to say the opposite |
| The Verdict dropdown offered `dismissed` | The wire enum is `upheld \| rejected \| expired`. Half of the product's only decision form could not be submitted |
| `verdictClass` had dead branches for `dismissed` and `stale` | So a live `expired` fell through to the undecided colour — the exact confusion the protocol docs forbid |
| "proved the same way a key is" | ADR 0003: a script credential's proof is a spend from the script's address, which one member of a 1-of-N multisig satisfies. Qualified in all four places |
| The served swagger denied the lead promise | Two descriptions said `credential` is "a claim and not a proof". `Mc3` has checked it since ADR 0003 — the sentence was written one day before the ADR that falsified it. Swagger 1.12.1 |
| "Verified credentials" contradicted its own heading on every row | A credential claim is self-issued (`Mc1`), so `accepted` is structurally always false. Column is now the credential; the impossible Accept link is gone on that view |
| The wallet gate refused every wallet on mainnet | `impliedMagic` had no arm for `networkId == 1`. Mainnet is one network, so nothing is guessed; `R6` forbids guessing, not deduction |
| Two refusal messages understated what they block | "Reading works; claiming a credential does not" — the gate blocks all nine flows |
| A trailing slash broke three registry screens | `segment` succeeds on an empty segment. Guarded in two layers, because `nonEmptySegment` alone turned the address into `NotFound` |
| Cross-links missing in both directions | Track-record rows pointed at a filtered list, not the vouch; a challenge name was not a link. Five perspectives hit this independently |
| The BFF made the write API public | The operator credential was appended to anything on the prefix. Measured: `GET /tx-status/0000…` answered 200 unauthenticated. Now a method+path allowlist derived from what the SPA calls. Two debug routes publishing the cluster's internal DNS deleted |

## Open — the backlog

Ranked by what would hurt a real user first, remembering the register has **zero real users** and
every row in it was written by this project's own smoke scripts.

| # | What | Cost | Note |
|---|---|---|---|
| 1 | **`/profiles/by-credential/{cip129}` has no screen.** The route the docs call "the verify direction", measured returning `total: 6`, with **zero** frontend call sites. `DRepDetail` — the screen a delegator actually lands on — never mentions a credential outside a raw hex label | half a day | Deferred by owner decision, to be taken separately. This is the single change that makes the relationship legible from both sides |
| ~~2~~ | ✅ **FIXED.** Nothing resolved the connected wallet to its own profile, so three write fields were hand-pasted 60-character ids | days | `Wallet/Assets` filters the CIP-67 user label out of the wallet's balance; the route does the user→reference derivation. Verified in a browser both ways — no token and one token |
| 3 | **The register is unfindable from the search box on every screen.** `Query/Gov.hs` returns a literal empty array for the `profiles` and `attestations` groups — four CTEs exist for the governance groups, none for the two object types the product is about | days | `?q=` on `/profiles` already returns 12; the client half is cheap, the `/search` CTEs are not |
| ~~4~~ | ✅ **FIXED.** Validator refusals reached the user as a two-letter trace code and a path to a file the service does not serve | afternoon | The off-chain `subject /= issuer` check beside `SubjectProfileNotFound` is the cheapest half |
| 5 | **The script half of the lead promise cannot be done from the UI** at all — the witness field does not exist in `claim-credential` | afternoon to qualify, days to build | The copy is now honest about it; the capability is still missing |
| ~~6~~ | ✅ **FIXED.** `image_uri` was collected six times and rendered nowhere | afternoon | Rendered as an ADDRESS, not an image: there is no IPFS gateway in this stack, and loading from the host someone else wrote into a datum sends the visitor's IP there. Measured: 11 of 12 are not real CIDs and one is `"htt"` |
| ~~7~~ | ✅ **FIXED on the two detail pages.** Four components reimplemented an id→name directory with `limit=200` into component-local state. The challenge page pulls both full registers to print two names, with a silent cap | afternoon | `getProfile`/`getAttestation` are already class members |
| ~~8~~ | ✅ **FIXED.** The registry lists had no filter or sort controls | afternoon | Four on profiles (`q`, `kind`, `claimed`, sort), four on vouches, two on challenges — the missing sort there is the server's own decision. State lives in the URL, so a filtered list is an address |
| ~~9~~ | ✅ **FIXED.** Eighteen byte-identical loading cards and twelve identical retry alerts | days | `Shared/Remote.purs`, −418 lines. The per-screen sentence stays per-screen |
| ~~10~~ | ✅ **FIXED.** `sameSection` existed twice — `NavBar` maps routes to strings, `Sidebar` matches pairwise. Both had to be edited for each of the three new routes | afternoon | One `section :: Route -> String` in `Route.purs` serves both |
| ~~11~~ | ✅ **FIXED.** Test debt sat on the half the detail-page block shipped. The mocks discard their filter arguments, so the fixture suite is structurally unable to catch a filter that does not reach the API — which is exactly the defect that shipped | afternoon | A unit assertion on the built href is the fix; the suite already does this for DRep filters |
| ~~12~~ | ✅ **FIXED.** A sixth order-dependence: `all-flows-sign.spec.js:88` picks the attestation to challenge with `items[0]`, and `/attestations` is ordered by slot descending | afternoon | The guard for exactly this was added two commits earlier, elsewhere |
| ~~13~~ | ✅ **FIXED.** `PALMARES_M2_SUBMIT` was undocumented — the README's submit tier names `PALMARES_FLOWS_SUBMIT`, which only two of the three files read | minutes | |
| ~~14~~ | ✅ **FIXED.** The frontend blocked `expire-dispute` while the oracle is paused, though the chain deliberately leaves that one write unlockable | afternoon | It is the only write that must not depend on anyone |
| ~~15~~ | ✅ **FIXED.** "Anyone can state… anyone can challenge" was false: the chain requires a minted profile and its user token | minutes | Eight words |
| ~~16~~ | ✅ **FIXED.** Empty states asserted the whole register is empty from a filtered page | afternoon | They take no argument |
| ~~17~~ | ✅ **FIXED for the two that were stale.** The frontend's own docs were the untouched scaffold template, titled "Cardano dApp Frontend Template" | afternoon | Deleting the stale sections beats rewriting them |
| ~~18~~ | ✅ **FIXED.** No Prometheus `/metrics` | days | On the BFF, on port 9464, which HTTPRoute does not route. No collision with `/metrics/formulas`: that one is in query-api and is a catalog |
| ~~19~~ | ✅ **FIXED.** No rate limiting | days | Two caps on `/api/*`: per client keyed on `x-forwarded-for` (the pod sees the node's address for every request — measured), and an overall one |

## CIP-119: what a Testatum profile adds to what a DRep already has

Raised by the owner and worth its own section, because it challenges a pillar.

Measured on **mainnet** through Koios, 1048 registered DReps, sample of 300: **49.3% declare a
metadata anchor**; of those, 89.9% parse and carry `givenName`, 81.1% carry `objectives`, 54.7%
carry an `image`, and hash validity on a sub-sample of 80 was 74 valid / 1 invalid / 5 unknown.
Extrapolated: **~44% of registered mainnet DReps already have a working, hash-valid profile with a
name, for free.** The preprod figures (23% valid, half the existing anchors broken) are a
test-registration artefact and must not be used — an earlier draft of this analysis leaned on them
and reached the wrong conclusion.

So, honestly:

- **`name`, `description` and `image_uri` genuinely duplicate the anchor** for that ~44%, and
  Testatum's versions are the weaker ones: CIP-119 prompts three separate 1000-character fields
  where Testatum collapses them into one `description`, and CIP-119's `imageObject` carries a
  `sha256` where `image_uri` is a bare URI with no hash.
- **A registered DRep has already proved control of their own credential** — the registration
  certificate was witnessed by that very credential. `claim-credential` does not add that proof; it
  adds a *binding* from the credential to a token-held profile that third parties can vouch for and
  challenge.
- **What does not duplicate anything**: the countersignature (`Mr`, plus the subject's separate
  acceptance), the deposit-backed challenge with an arbiter and a timeout, and the five profile
  kinds that are not DReps and have no anchor mechanism at all. Every one of those is a property of
  **the attestation, not of the profile**. The profile is the hook they hang on.
- **"Your off-chain document can rot and ours cannot" is not a usable argument** on mainnet, and the
  product does not claim it anywhere. Leaving it unsaid is correct.
- The data to stop asking a DRep to retype their own name is **already in hand**: `/pages/drep/{id}`
  returns `anchor_content` gated on `anchor_status = valid`. The blocker is that
  `Components/Write/Runner.purs` does not carry `MonadQueryGov`, so the write screen has no read
  access at all.

## What is in good shape, and should be protected

- **The write runner is the hardest part of this product and it is finished, not stubbed** — nine
  flows from one pure descriptor table, each carrying what it writes and what it costs.
- **The honesty discipline in the copy is a real trust asset and is rare.** "It does not make claims
  true. Nobody here verifies that the milestone shipped or the audit passed, and no system can."
- **The API is better than the UI in front of it**, and that is an asset rather than waste: 31
  routes, a consistent envelope, stable composite ids, and an error contract that goes as far as
  naming the codes which *cannot* be returned.
- **The Vouch/Challenge rename is clean at the boundary** — no API path, JSON key, flow id or route
  segment leaked.
- **The decoder discipline the project was burned by once is holding**: every nullable field the API
  actually sends `null` for uses `.:?`.

## Status, 2026-10-29 end of day

Eleven of the nineteen open rows are closed, marked above. The deploy caught up too: all four
images now run the same commit, and the swagger served at `/api/query/swagger-api.json` reports
`1.12.1` with the false sentence gone — verified live, not inferred.

What is left is the three that are features rather than defects — the `by-credential` screen
(deferred by the owner, to be taken separately), resolving the connected wallet to its own profile,
and the two `/search` CTEs — plus the cheap tail: the eighteen loading cards, filter controls on the
lists, the `docs/` rename (22 files), rate limiting, and a Prometheus endpoint.

One correction to this report's own framing, recorded because it changes how to read row 4. The
trace-code translation it asks for was **already specified**: `docs/usecases/attestation-protocol.md`
§4.2 holds a thirteen-row table of "On-chain refusals a user can actually reach", each with a "What
the UI should say" column, and line 812 of the same document says in as many words "**never show
this raw.**" So that row was not a reviewer's opinion about polish — it was a written obligation the
interface had never met. The dictionary now in `Capabilities/Interaction/Types.purs` is that table,
not a fresh derivation: a first attempt derived from the validators' own comments got the *cause*
wrong in two places, which the specification had already reasoned out.

## Status, 2026-10-29 seara — a doua trecere

Șaisprezece din nouăsprezece rânduri închise. Ce rămâne sunt exact cele trei care cer o decizie a
ownerului, nu muncă:

| # | Ce rămâne | De ce nu e o chestiune de muncă |
|---|---|---|
| 1 | ecranul `by-credential` | amânat explicit de owner, „to be taken separately" |
| 3 | cele două CTE din `/search` | SQL în `Query/Gov.hs` plus o imagine de backend (68 de minute, dispatch manual). Jumătatea de client e ieftină și n-are rost singură |
| 5 | jumătatea „script" a promisiunii | câmpul de martor nu există în `claim-credential`: schimbare în interaction-api plus redeploy coordonat |

Plus un rând nou, găsit în timpul reparațiilor și care nu era în raport: **titlurile servite de API
sunt singurul loc în care marca veche mai ajunge la un consumator.** `"Palmares Query API"` și
`"Palmares Interaction API"` vin din `RestAPI.hs`; documentele le citează ca fapte măsurate, deci nu
s-au schimbat în text — se schimbă odată cu următoarea imagine de backend, o linie per serviciu.

Și o corectură a propriei numărători a raportului: rândul despre redenumirea documentelor spunea
„243 de apariții". Numărătoarea era peste tot ce conține cuvântul, iar aproape tot sunt
IDENTIFICATORI — scheme SQL, roluri, căi, module, nume de imagini, chei de metadate. Marca propriu-zisă
era în cincisprezece locuri în documentele vii; rapoartele de audit (350 de apariții) rămân neatinse,
fiindcă sunt înregistrări datate, iar rescrierea unui raport ca să folosească marca de azi l-ar face
să afirme despre trecut ceva ce nu era adevărat atunci.
