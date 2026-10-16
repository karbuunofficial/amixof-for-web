#!/usr/bin/env bash
# Put a previous web image back in production. A target is required.
#
#   bash .cursor/skills/amixof-rollback/scripts/rollback.sh last              # undo the deploy that made the live image live
#   bash .cursor/skills/amixof-rollback/scripts/rollback.sh 20261016-063508   # the image in that backup's compose.yml
#   bash .cursor/skills/amixof-rollback/scripts/rollback.sh d1e9785           # an image already on the server
#
# To look without changing anything: bash .cursor/skills/amixof-rollback/scripts/status.sh
# Exit codes as deploy.sh: 0 rolled back · 2 refused, unchanged · 3 lock busy · 4 failed, restored
# · 5 restore failed (site may be down) · 7 unknown.
set -Eeuo pipefail

TARGET=${1:-}
if [ -z "$TARGET" ] || [ $# -ne 1 ]; then
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
fi
printf '%s' "$TARGET" | grep -Eq '^(last|[0-9]{8}-[0-9]{6}(-[0-9]+)?|[0-9a-f]{7,40})$' \
  || { echo "rollback target must be 'last', a backup name like 20261016-063508, or a hex image tag" >&2; exit 1; }

. "$(dirname "$0")/../../amixof-deploy/scripts/lib.sh"

LOG="$ARTIFACTS/rollback-$(stamp).log"
say "rolling back web to '$TARGET'; local log: $LOG"
set +e
remote_detached "$LOG" rollback "$TARGET" "$AMIXOF_COMPOSE_DIR" "$AMIXOF_SERVICE" "$AMIXOF_URL"
FOLLOW=$?
set -e
[ "$FOLLOW" = 0 ] || die "stopped following the server log (code $FOLLOW). It may still be running: ssh $AMIXOF_SSH tail -f $REMOTE_LOG, then run status.sh" 7

CODE=$(kv "$LOG" EXIT)
[ "$CODE" = 0 ] && [ "$(kv "$LOG" RESULT)" = rolled_back ] || explain_exit "$CODE" "$LOG"

append_runbook "### $(date -u '+%Y-%m-%d %H:%M UTC') — rolled back to $(kv "$LOG" IMAGE)
- Was: $(kv "$LOG" PREVIOUS)
- Backup taken before rollback: $(kv "$LOG" BACKUP)/compose.yml"

say "live image is now $(kv "$LOG" IMAGE) (was $(kv "$LOG" PREVIOUS)). Run the amixof-prod-check skill next."
say "GitHub main still has the newer commit. Fix forward or git revert it before the next deploy."
