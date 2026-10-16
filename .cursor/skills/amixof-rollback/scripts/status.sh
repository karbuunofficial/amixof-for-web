#!/usr/bin/env bash
# Read-only: what production is running, recent backups and images, disk, API, lock.
#   bash .cursor/skills/amixof-rollback/scripts/status.sh
set -Eeuo pipefail
. "$(dirname "$0")/../../amixof-deploy/scripts/lib.sh"
remote_inline status "$AMIXOF_COMPOSE_DIR" "$AMIXOF_SERVICE" "$AMIXOF_URL"
git fetch --quiet "$AMIXOF_GIT_REMOTE" main 2>/dev/null || true
printf 'GITHUB_MAIN=%s\nLOCAL_HEAD=%s\n' "$(git rev-parse --short=7 "$AMIXOF_GIT_REMOTE/main" 2>/dev/null || echo '?')" "$(git rev-parse --short=7 HEAD)"
