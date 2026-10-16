---
name: amixof-deploy
description: Deploy the current pushed commit of the AMIXOF web client to production (www.amixof.com) — builds amixof-for-web:<sha> on the server, backs up compose.yml, recreates only the web container, checks the live site and auto-rolls back on failure. Use when asked to deploy, release, ship or push live.
---

# Deploy to www.amixof.com

## Before you run it

1. `amixof-audit` and `amixof-verify` passed on this exact commit.
2. Committed and pushed: `git push amixof main`; `git rev-parse HEAD` equals `git rev-parse amixof/main`.
3. `.cursor/amixof.env` exists with `AMIXOF_SSH` set (copy from `.cursor/amixof.env.example`).
   SSH must work without a password prompt.

## Run

```bash
bash .cursor/skills/amixof-deploy/scripts/deploy.sh --dry-run   # preflight + shows what is live; changes nothing
bash .cursor/skills/amixof-deploy/scripts/deploy.sh             # runs verify.sh, then deploys
SKIP_VERIFY=1 bash .cursor/skills/amixof-deploy/scripts/deploy.sh   # only if verify.sh already passed on this commit
```

The build on the server takes several minutes. Do not interrupt it; the site is untouched until
the image is built.

## What the script does

Locally: rejects unknown arguments, non-`main`, dirty or unpushed trees → runs `verify.sh` →
reads server status (refuses if the lock is held or compose looks wrong).

It then uploads `scripts/remote.sh` to `/root/amixof-deploy/` and starts it **detached** on the
server (`setsid nohup`), so a dropped SSH connection or a stopped agent cannot leave a deploy
half-done. The local script follows the server log until it ends; if the connection drops it
keeps retrying.

On the server, under a lock:
1. Refuses (exit 2, nothing changed) if `compose.yml` does not have exactly one
   `image: amixof-for-web:<sha>` line, does not validate, has < 5 GB free, or `/api/` is already
   failing (that is not a web-client problem).
2. Clones the commit into `/root/amixof-builds/amixof-for-web-<sha7>`, initialises only the two
   public submodules, `docker build -t amixof-for-web:<sha7>`. Reuses the image if it exists.
3. Backs up `compose.yml` to `/root/amixof-backups/<UTC ts>/` with `kind`, `previous-image`, `new-image`.
4. Edits only that image line, validates, `docker compose up -d --no-deps --force-recreate web`.
5. Checks: the container runs the new image; the public `/login` (cache-busted) serves the
   bundle that the **new container's** `index.html` names; it contains AMIXOF with no `__VITE_`
   placeholders; the bundle returns 200; `/login/auth`, `/login/create`, `/source` respond.
   `/api/` is reported but not held against the deploy.
6. Any failure **or signal** after step 3 restores the backup, recreates `web`, and re-checks.

Then, from this machine, it fetches `/login` again and confirms the new bundle is served, and
records the deploy in `.cursor/artifacts/deploys.log` (and `AMIXOF_RUNBOOK_FILE` if set).

## Exit codes

| Code | Meaning | Do |
|------|---------|----|
| 0 | Deployed, all checks passed | Run `amixof-prod-check`, then report |
| 1 | Preflight refused | Fix what it says (commit, push, pull, config, verify) |
| 2 | Stopped before changing production (build failed, compose shape, disk, API already down) | Read the log in `.cursor/artifacts/`; production is unchanged |
| 3 | Another deploy/rollback holds the lock | Wait, then `status.sh` |
| 4 | Checks failed; **the server already restored the previous image** | Do not roll back again. Investigate with the log and `docker logs` |
| 5 | Checks failed and the restore failed too | **Tell the user immediately.** Then `rollback.sh <known-good tag>` |
| 6 | Deployed, but this machine still sees the old page (CDN/proxy cache) | Run `amixof-prod-check`; report it |
| 7 | Outcome unknown (lost the server for too long) | `status.sh` first; never redeploy blindly |

## After

- Run the `amixof-prod-check` skill and look at the screenshots.
- If you set `AMIXOF_RUNBOOK_FILE`, commit that runbook change in its own repo.
- Users with the PWA/service worker may see the old bundle until a hard refresh. That is not a
  failed deploy; check with a fresh browser profile.
- Report: commit, image tag, backup path, previous image, prod-check summary.

## Never

Deploy by hand-typing docker commands, touch any service other than `web`, or edit
`remote.sh` to skip a check in order to get a deploy through.
