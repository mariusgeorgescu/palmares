---
name: effect-capability-refactor
description: >-
  Use when narrowing broad MonadAff/MonadEffect usage in components via
  intent-specific capabilities, adding new effect capabilities, or
  migrating existing components to the effect-capability pattern.
---

# Effect-Capability Refactor

## When to use

- Replacing `MonadAff` or `MonadEffect` in a component with intent-level capabilities.
- Adding a new effect capability (under `Capabilities.*`) for a recurring UI/DOM/FFI pattern.
- Auditing a component or slice of the codebase for over-broad effect constraints.
- Migrating direct `H.liftAff` / `H.liftEffect` usage to capability calls.

## Rule

- `.cursor/rules/project-specific/effect-capability-narrowing.mdc` — default policy, constraint ladder, exceptions, migration checklist.

## Audit checklist

Before or during a refactor, verify:

1. **Component signature** — Does the component (and its `handleAction` / `render`) require `MonadAff` or `MonadEffect`? If yes, list the call sites that use them.
2. **Call-site mapping** — For each `H.liftAff` / `H.liftEffect` (or `delay`, `preventDefault`, `focus`, etc.):
   - Map to an intent (delay, focus, preventDefault, time, "other").
   - If an existing capability fits (e.g. `MonadDelay`, `MonadDomEvent`), plan to add that constraint and replace the call.
   - If no capability exists and the pattern recurs, consider adding a new capability.
3. **Parent chain** — Any parent that slots this component must provide the same (or broader) constraints; note which parents need constraint updates.
4. **Docs** — After changes, update your project's capability documentation so the constraint map stays accurate.

## Capability extraction workflow

When introducing a **new** intent capability:

1. **Define the type class** in `src/Capabilities/<Name>.purs` (e.g. `MonadDomFocus`, `focusElement`). Use `src/Capabilities/Delay.purs` as the smallest template — three sections: imports, class declaration, HalogenM instance.
2. **Implement in AppM and DemoM** in `src/AppM.purs` and `src/DemoM.purs` (typically `liftAff`/`liftEffect` or delegation to existing FFI). Mirror the existing `MonadDelay`/`MonadDomEvent` instances.
3. **Add a HalogenM instance** in the same capability module so `HalogenM state action slots output m` has the instance when `m` does — this is the lift you don't write again in components.
4. **Use in components** by adding the constraint and replacing direct lifts with the capability method.
5. **Update docs**: the capability table in `CLAUDE.md` + the rule `.cursor/rules/project-specific/effect-capability-narrowing.mdc` (the shipped table) + this skill's own table below.

## Incremental migration slices

Migrate in small, buildable slices:

1. **High-fanout first** — e.g. a shared helper used by many components: introduce the capability, change the helper, then add the constraint to all callers.
2. **By intent** — e.g. all "preventDefault" call sites in one pass using `MonadDomEvent`.
3. **By component** — one component at a time: replace lifts with capability calls, tighten the signature, then fix parents that slot it.
4. **Remove over-broad constraints last** — after the new intent capabilities are in place, remove `MonadAff`/`MonadEffect` from components that no longer need them.

## Verification gates

After each slice:

1. **Build** — `npm run build:spago` (or full `npm run build`) succeeds.
2. **No unintended broad constraints** — Migrated components do not reintroduce `H.liftAff`/`H.liftEffect` for operations now covered by a capability, unless the rule's exception applies.
3. **Slot compatibility** — Parents that host migrated components have the required capability constraints.
4. **Docs** — Project capability docs reflect new capabilities and updated component constraints.

## Shipped intent capabilities

| Capability | Module | Method(s) | Use for |
| ---------- | ------ | --------- | ------- |
| MonadDelay | Capabilities.Delay | `delayMs` | Debounce, delays, timeouts |
| MonadDomEvent | Capabilities.DomEvent | `preventDefaultEvent` | Link/button default prevention |

**Debounce note**: wrap `delayMs` in `H.fork` so the delay doesn't block subsequent input events. See `src/Components/Explorer/Items.purs` `SetSearch` → `LoadPage` — the `searchToken` field is a generation counter that drops stale forks. This is the canonical pattern; don't `delayMs` directly inside the handler.

## Reference

- **capability-layer** — For data-fetching capabilities (`MonadQueryApi`); keep effect capabilities separate from query capabilities.
- **implementation-workflow** — Stub-first and coherent mocks; when adding a new capability, ensure DemoM (and AppM) have implementations so the app builds.
