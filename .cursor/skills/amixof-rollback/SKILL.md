---
name: amixof-rollback
description: Restore a previous AMIXOF web client image in production, or show what is live — use immediately when a deploy broke www.amixof.com, when prod-check fails after a deploy, or when asked to undo, revert or roll back the site.
---

# Roll back www.amixof.com

Roll back first, investigate second. A rollback only changes the `web` image tag; it never
touches the API, database or other services.

```bash
bash .cursor/skills/amixof-rollback/scripts/status.sh                    # read-only: live image, backups, images, lock
bash .cursor/skills/amixof-rollback/scripts/rollback.sh last              # undo the deploy that made the live image live
bash .cursor/skills/amixof-rollback/scripts/rollback.sh 20261016-063508   # the image named in that backup's compose.yml
bash .cursor/skills/amixof-rollback/scripts/rollback.sh d1e9785           # a specific image already on the server
```

A target is required, so running the script by accident with no arguments changes nothing.
`last` finds the deploy that made the current image live and goes to the image before it.
Running it again steps back further. It never flips forward to a newer image, and it refuses
if no deploy record explains the live image (then name a tag from `status.sh`).

Each rollback runs detached on the server like a deploy: it takes its own backup, swaps the
tag, recreates `web`, runs the same live checks, and restores if they fail. Exit codes match
`deploy.sh` (0 done · 2 refused · 3 lock busy · 4 failed and restored · 5 restore failed · 7 unknown).

**If deploy.sh exited 4, do not roll back.** The server already restored the previous image.

Known-good reference: `amixof-for-web:d1e9785` (centred wordmark, deployed 16 Oct 2026).
`amixof-for-web:454c1803` is the first AMIXOF build. Its tag is 8 characters, so pass it in full.

## After a rollback

1. Run the `amixof-prod-check` skill.
2. GitHub `main` is now ahead of production. Either fix forward (new commit, normal ship), or
   `git revert` the bad commit and deploy that. Never force-push to make them match.
3. Tell the user: what broke, what is live now, which commit is reverted or pending.

If the rollback itself fails (exit 5), the site may be down. Say so to the user right away, with
the log path from `.cursor/artifacts/rollback-*.log`. Do not attempt anything beyond rolling back to
another known-good tag without them.
