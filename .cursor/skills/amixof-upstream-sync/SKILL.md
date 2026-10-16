---
name: amixof-upstream-sync
description: Bring a new Stoat for Web upstream release into the AMIXOF fork without losing AMIXOF branding or licence notices — merge, resolve conflicts, re-brand new strings, verify, ship. Use when asked to update from upstream, pull Stoat changes, or upgrade the client version.
---

# Merge upstream Stoat for Web into AMIXOF

Upstream: `https://github.com/stoatchat/for-web` (fork base: `4017c18`, release 0.15.3).

## 1. Prepare

```bash
git remote get-url upstream 2>/dev/null || git remote add upstream https://github.com/stoatchat/for-web.git
git fetch upstream --tags
git fetch amixof && git merge --ff-only amixof/main
git log --oneline amixof/main..upstream/main | wc -l      # how far behind
git switch -c sync/upstream-<version>
```

Pick a **release tag**, not an arbitrary `main` commit, unless the user asks otherwise.

## 2. Merge

```bash
git merge --no-ff <upstream-tag>
```

Conflict rules:
- AMIXOF user-facing text, links, wordmark (`AmixofWordmark`), `index.html` title, manifest,
  `MODIFICATIONS.md`, `README.md` header, `AGENTS.md`, `.cursor/` → keep ours.
- Logic, bug fixes, new features, dependency bumps → take theirs, then re-apply our branding on top.
- `pnpm-lock.yaml` → take theirs, then `pnpm install` to regenerate, never hand-edit.
- `catalogs/*/messages.po` → take theirs, then `lingui extract` + `lingui compile`.
- Submodule pointers → take theirs, then `git submodule update --init packages/stoat.js packages/solid-livekit-components`.

## 3. Re-brand anything new

```bash
node .cursor/skills/amixof-audit/scripts/brand-scan.mjs
```
New upstream strings mentioning Stoat must be re-worded for AMIXOF (or allow-listed with a reason
if they only render on stoat.chat). Check new links to stoat.chat / revolt.chat domains:
`rg -n "stoat\.chat|revolt\.chat|stoatinternal" packages/client --glob '!**/catalogs/**'`.

## 4. Update the notice

In `MODIFICATIONS.md` and `README.md`: new upstream commit hash and release, date of
modification. Keep the upstream copyright line.

## 5. Verify, ship

`amixof-audit` → `verify.sh --full` → fast-forward `main` to the sync branch → push → `amixof-deploy` →
`amixof-prod-check --signed-in` if credentials exist. Upstream merges are higher risk: check every
route listed in `README.md`, not only the ones you touched.
