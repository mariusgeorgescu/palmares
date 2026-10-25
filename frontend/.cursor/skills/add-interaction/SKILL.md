---
name: add-interaction
description: >-
  Use when implementing write-side actions (submit, vote, award, transfer)
  for the dApp. Covers MonadInteractionApi, input/result types, mock
  implementation, wallet signing, and contextual action buttons.
---

# Add Write-Side Interaction

## When to use

- Adding a new write action (e.g. submit proposal, vote, transfer, mint).
- Defining or extending a `MonadInteractionApi`-style capability with new methods.
- Wiring a wallet-signing flow for a new action type.
- Adding contextual action buttons to detail pages.

## Step-by-step

### 1. Define the capability method

Add an interaction capability if you don't have one yet (e.g. `MonadInteractionApi` in `Capabilities.Interaction.Api.MonadInteractionApi`):

```purescript
class Monad m <= MonadInteractionApi m where
  submitItem :: SubmitInput -> m (Either String TxResult)
```

### 2. Define input and result types

Add types in `Capabilities.Interaction.Api.Types`:

```purescript
type SubmitInput =
  { actor :: EntityId
  , payload :: ItemPayload
  }

type TxResult =
  { txHash :: String
  , status :: TxStatus
  }

data TxStatus = Built | Signed | Submitted | Confirmed | Failed String
```

### 3. Add mock implementation

Create `Capabilities.Interaction.Api.Mock` returning simulated `TxResult` values consistent with mock query data. Keep the mock coherent: if a mock submission is created, the mock query layer should be able to find it (or simulate that it would appear).

### 4. Wire instances

- Default implementation in `Capabilities.Interaction.Api.Default` (HTTP / tx pipeline).
- `AppM` instance delegates to Default.
- `DemoM` instance delegates to Mock.
- `HalogenM` instance via `lift`.

### 5. Build the action UI

Typical write-action wizard:

1. **Select Action** — surface the action only when the wallet state allows it.
2. **Fill Details** — form (DaisyUI inputs; add `halogen-formless` if you want typed forms with validation).
3. **Review & Preview** — human-readable summary + payload preview.
4. **Sign in Wallet** — loading → wallet signing prompt → error handling via `MonadCIP30`.
5. **Track Submission** — `steps` component tracking `TxStatus`. On confirmation: success toast.

### 6. Add contextual action buttons

Render an action button (e.g. `renderActionButton`) on relevant detail pages. **Actions that cannot be performed by the current wallet are hidden, not disabled** — this avoids dead UI affordances.

Typical wallet state → action visibility logic:

| Wallet state | Actions to show |
|---|---|
| Not connected | "Connect Wallet" CTA |
| Connected, no profile | "Create Profile" CTA |
| Wallet owns the entity in view | Owner actions (edit, transfer) |
| Wallet has the required role/credential | Privileged actions (award, approve) |

### 7. Update project docs

If your project has a spec/architecture doc, update the capability table and any page that gains a new contextual action. Add a CHANGELOG entry when the action is user-facing.

## Starting point in the template

The template ships no `MonadInteractionApi` — it's CIP-30 read-only. The pieces you'll build on are already wired, though:

- `src/Components/Layout/NavBar.purs` is the canonical "wallet state → action" example: on `WC.WalletConnectedEvent` it pulls the API out of the child component (`H.request WC._walletConnect unit WC.GetWalletApi`) and stashes it via `updateStore (Store.Connect api)`. Disconnect mirrors that. Your interaction methods will read `walletApi` back out of the store and pass it to your `Capabilities.Interaction.Api.Default` functions.
- `src/Store.purs` has the `Connect Api` / `Disconnect` actions and the `walletApi :: Maybe Api` field. Add fields like `activeProfile`, `pendingTxs`, etc. as your write actions need them.
- `src/AppM.purs` already declares `instance MonadCIP30 AppM` and `instance MonadInteraction AppM` — the empty marker instances that unlock the `cardano-capabilities` standalone functions (`enableWallet`, `signTx`, etc.). You don't need to redeclare these.

Mirror the structure of `src/Capabilities/Query/Api/` (`MonadQueryApi.purs`, `Types.purs`, `Default.purs`, `Mock.purs`, `Env.purs`) when you create `src/Capabilities/Interaction/Api/`.
