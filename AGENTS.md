# AGENTS.md — AMIXOF for Web

This repository is the web client that **https://www.amixof.com** serves. It is a modified
fork of Stoat for Web (SolidJS + TypeScript + Vite + Panda CSS + Lingui, pnpm workspace with
git submodules), licensed AGPL-3.0. Changes here go to production, so every agent working in this
repo acts as a complete development team, not a single autocomplete.

## The team you play

Each task moves through these roles, in this order. Do not skip one because the change "looks small".

| Role | Job | Done when |
|------|-----|-----------|
| **Lead** | Restate the goal, find the files involved, write a short plan, name the risk (UI only / auth / data / build / deploy). | The plan lists files and how the change will be verified. |
| **Engineer** | Make the change, following `.cursor/rules/`. Smallest diff that solves the problem. | Code compiles in your head and matches the plan. |
| **Reviewer** | Run the `amixof-audit` skill against your own diff as if someone else wrote it. Fix every finding, then audit again. | Audit comes back clean, or remaining items are written down with reasons. |
| **QA** | Run the `amixof-verify` skill. Reproduce the original bug first if it was a bug. | Typecheck, lint, format, brand scan and production build all pass. |
| **Release** | Commit, push, then run the `amixof-deploy` skill. | Deploy script exits 0 and its live checks pass. |
| **SRE** | Run the `amixof-prod-check` skill against the live site. Roll back with `amixof-rollback` if anything regressed. | Live checks pass, or the site is rolled back and the failure is reported. |

The `amixof-ship` skill runs this whole pipeline. Use it for any request that changes code.

## Hard rules (read `.cursor/rules/10-production-safety.mdc` for the full list)

1. Production touches **only** the `web` service in `/opt/stoat/compose.yml`. Never stop, recreate,
   or reconfigure the API, database, mail, storage or any other container. Never run
   `docker compose down`, `docker system prune`, `docker volume rm`, or anything that deletes data.
2. Every deploy goes through `.cursor/skills/amixof-deploy/scripts/deploy.sh`, which backs up the
   compose file, builds a tagged image from a pushed commit, swaps only `web`, checks the live
   site, and rolls back automatically on failure. Do not hand-type deploy commands.
3. Never deploy uncommitted or unpushed code. The image tag is always the 7-character commit SHA.
4. Never claim something works without evidence. Your final report says what you **measured**
   (command + result) and what you **did not verify**, separately.
5. Keep the AGPL obligations: source stays public, `MODIFICATIONS.md` is updated for user-visible
   changes, upstream copyright notices stay.
6. Users see **AMIXOF**, never "Stoat". Protocol and code names (`stoat.js`, `isStoat`,
   `/.well-known/stoat`, `Revolt.toml`) stay unchanged.

## Commands

```bash
pnpm install --frozen-lockfile                      # install
pnpm --filter stoat.js build && pnpm --filter solid-livekit-components build   # deps
pnpm --filter client exec lingui compile --typescript
pnpm --filter client exec node scripts/copyAssets.mjs
pnpm --filter client exec panda codegen
pnpm --filter client exec tsc --noEmit               # typecheck
pnpm exec eslint packages/client                     # lint
pnpm exec prettier --check 'packages/client/**/*.{ts,tsx,json}'
pnpm --filter client exec vite build                 # production build
```

`bash .cursor/skills/amixof-verify/scripts/verify.sh` runs all of the above in the right order.

## Where things are

- App routes: `packages/client/src/index.tsx`
- Auth screens: `packages/client/components/auth/src/flows/`
- Design system: `packages/client/components/ui/` (exported as `@revolt/ui`)
- Strings: Lingui macros in source; English catalog in `packages/client/components/i18n/catalogs/en/messages.po`
- Fallback brand assets: `packages/client/scripts/assets_fallback/`
- Runtime env injection: `docker/inject.js`
- Fork notice: `MODIFICATIONS.md`
- Local deploy config (not committed): `.cursor/amixof.env` — copy from `.cursor/amixof.env.example`
