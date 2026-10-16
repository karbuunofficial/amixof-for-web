---
name: amixof-verify
description: Run the local quality gate for the AMIXOF web client — install, build deps, codegen, typecheck, lint, format, brand scan and production build (plus i18n catalog, e2e and visual checks with --full). Use before every commit you intend to deploy, and whenever asked to test or check the build.
---

# Verify the AMIXOF web client locally

```bash
bash .cursor/skills/amixof-verify/scripts/verify.sh           # standard gate (deploy.sh runs this)
bash .cursor/skills/amixof-verify/scripts/verify.sh --fast    # typecheck + lint + brand scan
bash .cursor/skills/amixof-verify/scripts/verify.sh --full    # + i18n catalogs, Playwright e2e, local screenshots
```

The script prints a PASS/FAIL summary and keeps every log under `.cursor/artifacts/verify-*/`.
It builds against the AMIXOF API (`VITE_API_URL=<AMIXOF_URL>/api`, `VITE_HOST=<host>`) so the
app behaves as it does in production rather than as upstream Stoat.

## What each step means

| Step | Command | Typical fix |
|------|---------|-------------|
| install | `pnpm install --frozen-lockfile` | Lockfile out of date → run `pnpm install`, commit `pnpm-lock.yaml` |
| deps | `pnpm --filter stoat.js build`, `… solid-livekit-components build` | Submodule missing → `git submodule update --init packages/stoat.js packages/solid-livekit-components` |
| codegen | lingui compile, copyAssets, panda codegen | Usually a syntax error in a `.po` file or panda config |
| typecheck | `tsc --noEmit` in `packages/client` | Fix the types; no `@ts-ignore` |
| lint | `eslint packages/client` | Errors fail; warnings are allowed but do not add new ones |
| brand scan | `brand-scan.mjs` | Replace Stoat/Revolt in user-visible text, or mark a never-rendered line `brand-scan-ignore: <reason>` |
| format | `prettier --check` | `pnpm exec prettier --write <files>` |
| production build | `vite build` | Note bundle size; flag growth over 50 KB |
| i18n catalogs (`--full`) | `lingui extract` leaves no diff | Commit the updated `catalogs/en/messages.po` |
| e2e + visual (`--full`) | Playwright against `vite preview` | Needs the AMIXOF API to accept requests from `http://localhost:4173`; if it does not (CORS), say so and rely on `amixof-prod-check` after deploy |

## Rules

- A red step blocks deploy. Fix it; do not skip it.
- "It was already broken" needs proof: run the same step on `amixof/main` in a separate worktree
  (`git worktree add /tmp/amixof-main amixof/main`) and show it fails there too.
- First run on a fresh machine needs `corepack enable` (pnpm 11.3.0) and, for `--full`,
  `pnpm --filter client exec playwright install chromium`.
- Report the summary block verbatim in your final message under "Measured".
