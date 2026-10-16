#!/usr/bin/env bash
# Deploy the current commit of amixof-for-web to production (web service only).
#
#   bash .cursor/skills/amixof-deploy/scripts/deploy.sh --dry-run  # preflight only, changes nothing
#   bash .cursor/skills/amixof-deploy/scripts/deploy.sh            # verify, deploy, check live
#   SKIP_VERIFY=1 bash …/deploy.sh   # only when verify.sh already passed on this exact commit
#
# Exit codes: 0 deployed · 1 preflight refused · 2 stopped before changing production
#   · 3 another deploy running · 4 live checks failed and the server restored the previous image
#   · 5 restore also failed (site may be down — tell the user now) · 6 deployed, but the check
#   from this machine did not see the new bundle · 7 outcome unknown (run status.sh)
set -Eeuo pipefail

case "${1:-}" in
  "") DRY=0 ;;
  --dry-run) DRY=1 ;;
  *) echo "unknown argument '$1' (only --dry-run is accepted)" >&2; exit 1 ;;
esac
[ $# -le 1 ] || { echo "too many arguments" >&2; exit 1; }

. "$(dirname "$0")/lib.sh"

# ---------- preflight ----------
say "preflight"
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = main ] || die "on branch '$branch'; deploy only from main"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "tracked files have uncommitted changes; commit first"
git fetch --quiet "$AMIXOF_GIT_REMOTE" main
FULL=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse "$AMIXOF_GIT_REMOTE/main")
[ "$FULL" = "$REMOTE_SHA" ] || die "HEAD $FULL is not $AMIXOF_GIT_REMOTE/main ($REMOTE_SHA). Push first (git push $AMIXOF_GIT_REMOTE main), or pull if GitHub is ahead."
TAG=${FULL:0:7}
SUBJECT=$(git log -1 --format=%s)
say "commit $TAG ($SUBJECT)"

if [ "${SKIP_VERIFY:-0}" != 1 ]; then
  say "running verify.sh (set SKIP_VERIFY=1 only if it already passed on $TAG)"
  bash "$ROOT/.cursor/skills/amixof-verify/scripts/verify.sh" || die "verify.sh failed; fix it before deploying"
fi

say "checking server access"
STATUS=$(remote_inline status "$AMIXOF_COMPOSE_DIR" "$AMIXOF_SERVICE" "$AMIXOF_URL") || die "could not reach the server or read its compose file" 2
printf '%s\n' "$STATUS" >&2
LIVE=$(printf '%s\n' "$STATUS" | sed -n 's/^RUNNING_IMAGE=//p')
printf '%s\n' "$STATUS" | grep -q '^IMAGE_LINES=1$' || die "compose.yml does not have exactly one amixof-for-web image line; not deploying" 2
printf '%s\n' "$STATUS" | grep -q '^LOCK=free$' || die "another deploy or rollback holds the server lock" 3

if [ "$DRY" = 1 ]; then
  say "dry run: would deploy amixof-for-web:$TAG (live now: ${LIVE:-unknown}). No changes made."
  exit 0
fi

# ---------- deploy ----------
LOG="$ARTIFACTS/deploy-$(stamp)-$TAG.log"
say "deploying amixof-for-web:$TAG (live now: ${LIVE:-unknown}); local log: $LOG"
set +e
remote_detached "$LOG" deploy "$FULL" "$AMIXOF_REPO" "$AMIXOF_COMPOSE_DIR" "$AMIXOF_SERVICE" "$AMIXOF_URL"
FOLLOW=$?
set -e
[ "$FOLLOW" = 0 ] || die "stopped following the server log (code $FOLLOW). The deploy may still be running: watch it with  ssh $AMIXOF_SSH tail -f $REMOTE_LOG  then run status.sh" 7

CODE=$(kv "$LOG" EXIT)
[ "$CODE" = 0 ] && [ "$(kv "$LOG" RESULT)" = deployed ] || explain_exit "$CODE" "$LOG"
BACKUP=$(kv "$LOG" BACKUP); PREVIOUS=$(kv "$LOG" PREVIOUS); BUNDLE=$(kv "$LOG" BUNDLE)

# ---------- confirm from outside the server ----------
say "checking the live site from this machine"
OUTSIDE=ok
html=$(curl -fsS --max-time 20 -H 'Cache-Control: no-cache' "$AMIXOF_URL/login?deploycheck=$(date +%s)" 2>/dev/null) || OUTSIDE="could not fetch /login"
if [ "$OUTSIDE" = ok ] && ! printf '%s' "$html" | grep -qF "$BUNDLE"; then OUTSIDE="/login from here does not reference $BUNDLE"; fi

append_runbook "### $(date -u '+%Y-%m-%d %H:%M UTC') — deployed amixof-for-web:$TAG
- Commit: $FULL ($SUBJECT)
- Previous image: $PREVIOUS
- Backup: ${BACKUP:-none (already live)}/compose.yml
- Bundle: $BUNDLE
- Outside check: $OUTSIDE
- Undo: bash .cursor/skills/amixof-rollback/scripts/rollback.sh last"

say "deployed amixof-for-web:$TAG (was $PREVIOUS). Backup: ${BACKUP:-none}"
if [ "$OUTSIDE" != ok ]; then
  say "WARNING: $OUTSIDE — a CDN or proxy may still serve the old page. Run the amixof-prod-check skill before reporting success."
  exit 6
fi
say "next: node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs"
