---
name: post-plan-review
description: >-
  Post-task refactoring and deduplication review checklist.
  Run after completing a plan or multi-step task, before marking it done.
  Invoke explicitly with /post-plan-review.
disable-model-invocation: true
---

# Post-Plan Review

Run this review after each completed plan or multi-step task.

## Scope

Review all code touched by the plan, plus related modules (imports, siblings in the same namespace).

## Refactoring opportunities

Check for and propose:

- Extract repeated logic into shared functions or modules.
- Simplify complex conditionals or nested structures.
- Improve type safety (replace primitives with domain types where appropriate).
- Align with project conventions (see `project-conventions` rule, `halogen-functional-core` rule).

## Deduplication

- Identify duplicated patterns (render helpers, capability usage, query handling).
- Consolidate into shared modules (e.g. `Components.Shared.*`, `App.Utils`, capability helpers).
- Check for overlap with `Halogen.DaisyUI.*` or existing project components before adding new ones.
- **Effect constraints**: If the plan touched component constraints or effect usage, check for over-broad `MonadAff`/`MonadEffect` that could be narrowed via intent capabilities; use skill **effect-capability-refactor** and rule `effect-capability-narrowing` for follow-up.

## Output

List identified opportunities with file/line references. Propose concrete refactors when straightforward; otherwise note as follow-up items.
