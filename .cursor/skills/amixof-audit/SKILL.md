---
name: amixof-audit
description: Review your own diff in the AMIXOF web client as a strict senior reviewer, then fix what you find — correctness, Solid reactivity, i18n and branding, accessibility, responsive layout, security, AGPL notice, deploy risk. Use after implementing anything and before verify/commit; also use when asked to audit or review code.
---

# Audit your own work, then fix it

Pretend another engineer wrote this diff and you are accountable if it breaks production.

## 1. Collect the change

```bash
git diff --stat amixof/main...HEAD; git diff amixof/main...HEAD   # committed but unpushed work
git diff --stat; git diff                                         # uncommitted work
node .cursor/skills/amixof-audit/scripts/brand-scan.mjs
```

Read every changed hunk **and** the surrounding function. Open callers of anything whose
signature or behaviour changed (`rg -n "<symbol>" packages/client`).

If your editor supports subagents or a fresh chat, run this review there with only the diff and
this checklist, so the review is not biased by how you wrote the code.

## 2. Checklist

**Correctness**
- Does it do what the user asked, for every path (signed in/out, empty data, slow network, error)?
- Off-by-one, null/undefined, race conditions, stale closures, missing `await`.
- Anything removed that something else still imports or routes to?

**SolidJS**
- No destructured props; `splitProps`/`mergeProps` used where needed.
- Reactive reads happen inside JSX/memos/effects, not once at component setup.
- Lists use `<For>`/`<Index>`; conditionals use `<Show>`/`<Switch>`.
- Effects and listeners cleaned up with `onCleanup`.

**Strings and branding**
- Every visible string wrapped in Lingui; no concatenated fragments.
- No user-visible "Stoat"/"Revolt" (brand-scan clean). Technical names untouched.
- If strings changed: `lingui extract` run and the English catalog committed.

**UI and accessibility**
- 390px: no horizontal scroll, nothing clipped. 1360px: sensible max widths.
- Light and dark: theme tokens only, contrast OK.
- Buttons are `<button>`, icon-only controls have `aria-label`, inputs have labels, focus visible,
  keyboard works.

**Security and privacy**
- No secrets, tokens, server paths or user data in code, logs, or commits.
- No `innerHTML` / `dangerouslySetInnerHTML`-style injection of user content.
- External links use `target="_blank"` with `rel="noopener noreferrer"` where the component does not add it.
- No new third-party script or tracker.

**Build and deploy risk**
- New dependency? Justified, licence AGPL-compatible, lockfile committed.
- Bundle growth? Large imports lazy-loaded.
- Anything that changes env vars, `docker/`, `Dockerfile`, `vite.config.ts`, service worker,
  or routing needs an explicit note in the commit and a prod-check of every route after deploy.

**Licence**
- User-visible change → line added to `MODIFICATIONS.md`.
- Upstream copyright headers intact.

**Housekeeping**
- No debug `console.log`, commented-out code you added, TODOs without an owner, or stray files.
- Doc comment on new components/functions (GUIDELINES.md).

## 3. Fix loop

For each finding: fix it, or write one line on why it is safe to leave. Re-run this audit on the
new diff. Stop after 3 rounds and report anything still open.

## 4. Output

A short list: `severity · file:line · finding · fixed|left (reason)`. Carry the "left" items into
the final report under "Found, not fixed".
