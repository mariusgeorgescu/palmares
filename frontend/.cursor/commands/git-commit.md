# Git Create Commit

## Overview

Create a short, focused commit message and commit staged changes. Conventional-commit style when it fits; descriptive sentence-style is acceptable for broad changes.

## Steps

1. **Review changes**
   - Check the diff: `git diff --cached` (staged) or `git diff` (unstaged)
   - Understand what changed and why
2. **Infer scope from changed paths (optional)**
   - `src/Components/<Name>/*` → scope from the component name (e.g. `home`, `navbar`, `items`)
   - `src/Capabilities/*` → scope `capability`
   - `src/Route*`, `src/App/*`, `src/AppM.purs`, `src/DemoM.purs`, `src/Store.purs`, `src/AppEnv.purs` → scope `app` or omit
   - `bff/*` → scope `bff`
   - `.cursor/*`, `docs/*` → scope `docs` or `cursor`
   - `Dockerfile`, `docker-compose.yml`, `scripts/*` → scope `docker` or `chore`
   - Customize for your domain — add scopes that map to your top-level component folders.
   - Use a scope only when it clarifies; omit for cross-cutting or small changes.
3. **Ask for issue key (optional)**
   - Check the branch name for an issue key (Linear, Jira, GitHub issue, etc.)
   - If not in context, optionally ask if the user wants to include one.
4. **Stage changes (if not already staged)**
   - Prefer explicit `git add <files>` over `git add -A` to avoid pulling in unintended files.
5. **Pre-commit check (PureScript changes)**
   - If the diff includes `.purs` files, remind that `npm run check-formatting` and `npx spago build --json-errors` should pass (or the repo hooks will format/typecheck on save). Do not block the commit; just note it.
6. **Create short commit message**
   - Base it on the actual changes in the diff
   - Prefer conventional form for focused changes; use descriptive sentence-style for multi-area or UX-heavy changes.

## Types (conventional)

- **feat:** New feature or capability (e.g. new page, new capability method, new component).
- **fix:** Bug fix or regression.
- **docs:** Documentation, Cursor rules/skills, CHANGELOG.
- **chore:** Build, Docker, deps, tooling.
- **refactor:** Restructure without changing behavior (e.g. extract Shared component, rename module).

## Template

- Conventional: `git commit -m "<type>(<scope>): <short summary>"`
- With issue key: `git commit -m "<issue-key>: <type>(<scope>): <short summary>"`
- Descriptive (acceptable): `git commit -m "Area: short summary of what and why"`

## Examples

- `feat(items): page-shaped explorer with debounced search`
- `fix(navbar): close drawer on route change`
- `docs: add capability-layer skill and quickstart`
- `chore(docker): split dev/prod image tags`
- `refactor(capability): extract MonadQueryApi default impl`

## Rules

- **Length:** <= 72 characters
- **Imperative mood:** Use "fix", "add", "update" (not "fixed", "added", "updated")
- **Capitalize:** First letter of summary should be capitalized
- **No period:** Don't end the subject line with a period
- **Describe why when useful:** "fix stuff" is meaningless; "fix: load CSS on direct deep links" is better
- **PureScript:** Module names must match file paths (e.g. `Components.Home` → `src/Components/Home.purs`); scope can align with component or capability name

## CHANGELOG

For user-facing or notable changes, add an entry under `CHANGELOG.md` (Keep a Changelog: Added, Changed, Fixed, etc.). The commit message can stand alone; the CHANGELOG entry can be more detailed.
