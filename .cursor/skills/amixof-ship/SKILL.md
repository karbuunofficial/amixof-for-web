---
name: amixof-ship
description: Carry any code change to the AMIXOF web client from request to verified-live production — plan, implement, self-audit, fix, verify, commit, push, deploy, confirm live, report. Use for every feature, fix, copy or UI change in this repo.
---

# Ship a change to www.amixof.com

You are the whole team: lead, engineer, reviewer, QA, release manager and SRE. Work through the
stages in order. Do not report success until stage 8 passes.

## 0. Sync (always first)

```bash
git fetch amixof
git status
git merge --ff-only amixof/main   # if behind; stop and ask if it cannot fast-forward
git submodule update --init packages/stoat.js packages/solid-livekit-components
bash .cursor/skills/amixof-rollback/scripts/status.sh             # what is live right now (read-only)
```

If the live image tag is not the short SHA of `amixof/main`, someone deployed or rolled back
outside git. Say so before changing anything.

## 1. Lead: understand and plan

Write 3–6 lines:
- Goal in user terms.
- Files you will touch (read them and their callers first).
- Risk class: `ui` · `copy/i18n` · `auth` · `data` · `build/deps` · `deploy`.
- How you will prove it works (which checks, which screens).

For `auth`, `data`, `build/deps` or `deploy` risk: also write what could break for users and how
you would notice. Ask the user one question only if a wrong guess would be expensive.

## 2. Engineer: implement

Follow `.cursor/rules/20-solidjs-typescript.mdc`, `30-i18n-and-branding.mdc`, `60-ui-quality.mdc`.
Smallest diff. New strings through Lingui. Update `MODIFICATIONS.md` for user-visible changes.

## 3. Reviewer: self-audit, then fix — loop

Run the `amixof-audit` skill on `git diff`. Fix every finding. Re-run. Maximum 3 rounds; then stop
and report what is still open.

## 4. QA: verify

```bash
bash .cursor/skills/amixof-verify/scripts/verify.sh          # must end with every step PASS
```
Use `--full` when you changed strings (catalog check) or routing/auth (e2e). If a check fails,
fix it — including pre-existing failures in files you touched. For failures in files you did not
touch, confirm they also fail on `amixof/main` before calling them pre-existing.

## 5. Release: commit and push

```bash
pnpm exec prettier --write <changed files>
git add <each file you changed>        # never `git add -A` blindly
git status --short                      # confirm nothing unexpected is staged
git commit -m "<type>(<scope>): <what>" -m "<why, user-visible effect, anything not verified>"
git push amixof main
```
Never commit `.cursor/amixof.env` or `.cursor/artifacts/`.

## 6. Release: deploy

Run the `amixof-deploy` skill. It refuses dirty/unpushed trees, backs up, swaps only `web`,
checks the live site, and rolls back by itself on failure.

## 7. SRE: confirm live

Run the `amixof-prod-check` skill (add `--signed-in` if test credentials are configured and the
change touches signed-in screens). Open and look at the screenshots of the screens you changed.
If something your deploy caused regressed: `rollback.sh last`, then fix forward. A failure that
also exists on the previous image is not a reason to roll back. Report it instead.

## 8. Report

Use the report format in `.cursor/rules/00-team-operating-model.mdc`: Done · Shipped (commit,
image, backup path) · Measured · Not verified · Found, not fixed.
