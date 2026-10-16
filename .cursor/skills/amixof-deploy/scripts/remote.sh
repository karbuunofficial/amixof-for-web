#!/usr/bin/env bash
# Runs ON the production server. deploy.sh / rollback.sh / status.sh upload it and start it;
# do not run it by hand.
#
#   remote.sh deploy   <full-sha> <repo-url> <compose-dir> <service> <public-url>
#   remote.sh rollback <target>   <compose-dir> <service> <public-url>
#        target = "last" | a backup name (yyyymmdd-HHMMSS[-n]) | an image tag (7–40 hex chars)
#   remote.sh status   <compose-dir> <service> <public-url>
#
# Deploy and rollback run detached (setsid/nohup) so a dropped SSH connection cannot stop them
# half-way. Once compose.yml has been backed up, ANY failure or signal restores the backup,
# recreates the service and re-checks it (EXIT trap). Only the one named service is touched.
#
# Exit codes: 0 ok · 2 refused, production untouched · 3 lock busy · 4 failed and restored
#             · 5 failed and restore also failed (site may be down)
set -Eeuo pipefail
export GIT_TERMINAL_PROMPT=0

BUILD_ROOT=${AMIXOF_BUILD_ROOT:-/root/amixof-builds}
BACKUP_ROOT=${AMIXOF_BACKUP_ROOT:-/root/amixof-backups}
LOCK=${AMIXOF_LOCK:-/root/amixof-deploy.lock}
TAG_RE='amixof-for-web:[0-9a-f]{7,40}'
# A real image line: optional indent, image:, optional quote, the tag, optional quote, optional trailing comment.
LINE_RE="^[[:space:]]*image:[[:space:]]*['\"]?${TAG_RE}['\"]?[[:space:]]*(#.*)?$"

log() { printf '[server %s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2 || true; }
die() { log "ERROR: $1"; exit "${2:-2}"; }
emit() { printf 'RESULT=%s\nIMAGE=%s\nPREVIOUS=%s\nBACKUP=%s\nBUNDLE=%s\n' "$1" "${2:-}" "${3:-}" "${4:-}" "${5:-}" || true; }

# ---------- state used by the safety trap ----------
SWAPPING=0         # 1 once compose.yml may differ from the backup
FINISHED=0         # 1 once a result has been emitted deliberately
BACKUP_DIR=""
RESTORE_IMAGE=""   # image the backup names (what we go back to)
NEW_IMAGE=""

compose_file() { printf '%s/compose.yml' "$COMPOSE_DIR"; }

# Tag on the (single) real image line of a compose file; empty if none.
image_in() { { grep -E "$LINE_RE" "$1" 2>/dev/null || true; } | grep -oE "$TAG_RE" | head -n1 || true; }
current_image_in_compose() { image_in "$(compose_file)"; }

container_id() { (cd "$COMPOSE_DIR" && docker compose ps -q "$SERVICE" 2>/dev/null | head -n1) || true; }
running_image() {
  local id; id=$(container_id)
  [ -n "$id" ] || return 0
  docker inspect -f '{{.Config.Image}}' "$id" 2>/dev/null || true
}

check_compose_shape() {
  local f; f=$(compose_file)
  [ -f "$f" ] || die "missing $f"
  local n; n=$(grep -cE "$LINE_RE" "$f" || true)
  [ "$n" = 1 ] || die "expected exactly one 'image: amixof-for-web:<sha>' line in $f, found $n; refusing to edit it"
  (cd "$COMPOSE_DIR" && docker compose config -q) || die "$f does not validate as it stands; refusing to touch it"
}

# Copy compose.yml into a new backup dir and record metadata. Prints the dir.
backup_compose() {
  local kind=$1 new=$2 ts dir n=2
  ts=$(date -u +%Y%m%d-%H%M%S)
  dir="$BACKUP_ROOT/$ts"
  while [ -e "$dir" ]; do dir="$BACKUP_ROOT/$ts-$n"; n=$((n + 1)); done
  mkdir -p "$dir"
  cp -p "$(compose_file)" "$dir/compose.yml"
  current_image_in_compose >"$dir/previous-image"
  printf '%s\n' "$new" >"$dir/new-image"
  printf '%s\n' "$kind" >"$dir/kind"
  printf '%s\n' "$dir"
}

set_image() {
  local image=$1 f; f=$(compose_file)
  sed -i -E "/${LINE_RE}/ s#${TAG_RE}#${image}#" "$f"
  [ "$(current_image_in_compose)" = "$image" ] || die "compose edit did not take" 1
  (cd "$COMPOSE_DIR" && docker compose config -q) || die "compose file no longer validates after edit" 1
}

recreate_service() {
  log "recreating only '$SERVICE'"
  (cd "$COMPOSE_DIR" && docker compose up -d --no-deps --force-recreate "$SERVICE") >&2
}

api_ok() { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$PUBLIC_URL/api/" || true)" = 200 ]; }

# Bundle the running container serves, read from inside it (not from any cache).
container_bundle() {
  local id; id=$(container_id)
  [ -n "$id" ] || return 0
  { docker exec "$id" sh -c 'cat /app/dist_injected/index.html 2>/dev/null || cat /app/dist/index.html' 2>/dev/null || true; } \
    | grep -oE '/assets/index-[A-Za-z0-9_-]+\.js' | head -n1 || true
}

# Live checks against the public URL. Prints the bundle path on success.
live_checks() {
  local expect_image=$1 html="" bundle="" code path
  for _ in $(seq 1 40); do
    if [ "$(running_image)" = "$expect_image" ]; then
      bundle=$(container_bundle)
      if [ -n "$bundle" ]; then
        html=$(curl -fsS --max-time 15 -H 'Cache-Control: no-cache' "$PUBLIC_URL/login?deploycheck=$(date +%s)" 2>/dev/null || true)
        if printf '%s' "$html" | grep -qF "$bundle"; then break; fi
      fi
    fi
    sleep "${AMIXOF_CHECK_INTERVAL:-3}"
  done
  [ "$(running_image)" = "$expect_image" ] || { log "check: $SERVICE is not running $expect_image (got '$(running_image)')"; return 1; }
  [ -n "$bundle" ] || { log "check: could not read index.html inside the container"; return 1; }
  printf '%s' "$html" | grep -qF "$bundle" || { log "check: public /login does not serve the new container's bundle $bundle (old container or cache answering)"; return 1; }
  printf '%s' "$html" | grep -q 'AMIXOF' || { log "check: /login does not contain AMIXOF"; return 1; }
  if printf '%s' "$html" | grep -q '__VITE_'; then log "check: unreplaced __VITE_ placeholder in HTML"; return 1; fi
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$PUBLIC_URL$bundle" || true)
  [ "$code" = 200 ] || { log "check: $bundle returned $code"; return 1; }
  for path in /login/auth /login/create /source; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$PUBLIC_URL$path" || true)
    case "$code" in 200|301|302|307|308) ;; *) log "check: $path returned $code"; return 1 ;; esac
  done
  api_ok || log "check: warning — /api/ is not returning 200 (API is not managed here; not counted against this deploy)"
  local id; id=$(container_id)
  if docker logs --since 2m "$id" 2>&1 | grep -qiE 'error|exception'; then
    log "check: warning — $SERVICE logged errors in the last 2 minutes:"
    docker logs --since 2m "$id" 2>&1 | grep -iE 'error|exception' | tail -n 5 >&2 || true
  fi
  printf '%s\n' "$bundle"
}

# Put the backup back, recreate, check. Exits 4 (restored) or 5 (restore failed).
restore_and_exit() {
  set +e
  FINISHED=1
  log "restoring $BACKUP_DIR/compose.yml ($RESTORE_IMAGE)"
  cp -p "$BACKUP_DIR/compose.yml" "$(compose_file)"
  local bundle
  if recreate_service && bundle=$(live_checks "$RESTORE_IMAGE"); then
    emit restored "$NEW_IMAGE" "$RESTORE_IMAGE" "$BACKUP_DIR" "$bundle"
    exit 4
  fi
  log "RESTORE FAILED — site may be down"
  emit restore_failed "$NEW_IMAGE" "$RESTORE_IMAGE" "$BACKUP_DIR"
  exit 5
}

on_exit() {
  local code=$?
  if [ "$SWAPPING" = 1 ] && [ "$FINISHED" = 0 ]; then
    log "stopped unexpectedly (exit $code) after the swap began"
    restore_and_exit
  fi
}
trap on_exit EXIT
trap 'exit 130' INT TERM HUP

take_lock() {
  exec 9>"$LOCK"
  flock -n 9 || die "another deploy or rollback is running (lock $LOCK)" 3
}

# Swap to $NEW_IMAGE with backup + checks; restore on any failure. $1 = backup kind, $2 = result word.
swap_to() {
  RESTORE_IMAGE=$(current_image_in_compose)
  BACKUP_DIR=$(backup_compose "$1" "$NEW_IMAGE")
  log "backup: $BACKUP_DIR (compose names $RESTORE_IMAGE, running $(running_image))"
  SWAPPING=1
  set_image "$NEW_IMAGE"
  local bundle
  if recreate_service && bundle=$(live_checks "$NEW_IMAGE"); then
    FINISHED=1
    log "live checks passed"
    emit "$2" "$NEW_IMAGE" "$RESTORE_IMAGE" "$BACKUP_DIR" "$bundle"
    exit 0
  fi
  log "live checks FAILED for $NEW_IMAGE"
  restore_and_exit
}

# ---------- build ----------

ensure_image() {
  local full=$1 repo=$2 tag=${1:0:7}
  local image="amixof-for-web:$tag" dir="$BUILD_ROOT/amixof-for-web-$tag"
  if docker image inspect "$image" >/dev/null 2>&1; then
    log "$image already exists; reusing it"
    return 0
  fi
  mkdir -p "$BUILD_ROOT"
  if [ -e "$dir" ] && ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    log "moving aside unusable build dir $dir"
    mv "$dir" "$dir.broken.$(date -u +%Y%m%d%H%M%S)"
  fi
  if [ ! -e "$dir" ]; then
    log "cloning $repo"
    git clone --quiet "$repo" "$dir.tmp.$$" || die "git clone failed; production was not touched"
    mv "$dir.tmp.$$" "$dir"
  fi
  git -C "$dir" fetch --quiet origin || die "git fetch failed; production was not touched"
  git -C "$dir" checkout --quiet --force --detach "$full" || die "commit $full not found in $repo; push it first"
  # The brand-assets submodule is private and must stay uninitialised.
  git -C "$dir" submodule update --init --quiet packages/stoat.js packages/solid-livekit-components \
    || die "submodule init failed; production was not touched"
  [ -f "$dir/packages/stoat.js/package.json" ] || die "stoat.js submodule missing after init"
  log "building $image (several minutes)"
  (cd "$dir" && docker build -t "$image" . >&2) || die "docker build failed; production was not touched"
  docker image inspect "$image" >/dev/null || die "image not present after build"
}

# ---------- commands ----------

cmd_deploy() {
  local full=$1 repo=$2
  [[ "$full" =~ ^[0-9a-f]{40}$ ]] || die "deploy needs a full 40-char sha, got '$full'"
  NEW_IMAGE="amixof-for-web:${full:0:7}"
  take_lock
  check_compose_shape
  local free_gb
  free_gb=$(df -BG --output=avail / | tail -n1 | tr -dc 0-9)
  [ "${free_gb:-0}" -ge 5 ] || die "only ${free_gb}G free on /; ask the user before cleaning anything up"
  api_ok || die "/api/ is not returning 200 before the deploy; the problem is not the web client. Refusing to deploy."
  ensure_image "$full" "$repo"
  if [ "$(current_image_in_compose)" = "$NEW_IMAGE" ] && [ "$(running_image)" = "$NEW_IMAGE" ]; then
    log "$NEW_IMAGE is already live; checking only"
    local bundle
    bundle=$(live_checks "$NEW_IMAGE") || die "already live but checks fail; investigate (nothing was changed)"
    FINISHED=1; emit deployed "$NEW_IMAGE" "$NEW_IMAGE" "" "$bundle"; exit 0
  fi
  swap_to deploy deployed
}

cmd_rollback() {
  local target=$1
  take_lock
  check_compose_shape
  local live; live=$(current_image_in_compose)

  if [ "$target" = last ]; then
    # Undo the deploy that put the live image there: newest *deploy* backup whose new-image is
    # live → the image in its compose.yml. Repeating this keeps stepping back; it never flips forward.
    local d
    NEW_IMAGE=""
    while IFS= read -r d; do
      [ "$(cat "$d/kind" 2>/dev/null)" = deploy ] || continue
      [ "$(cat "$d/new-image" 2>/dev/null)" = "$live" ] || continue
      NEW_IMAGE=$(image_in "$d/compose.yml")
      log "the deploy of $live was backed up in $d; going back to $NEW_IMAGE"
      break
    done < <( { find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' 2>/dev/null || true; } | sort -r)
    [ -n "$NEW_IMAGE" ] || die "no deploy backup records how $live went live; name a tag or backup explicitly (see status)"
  elif [[ "$target" =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]]; then
    [ -f "$BACKUP_ROOT/$target/compose.yml" ] || die "no backup $BACKUP_ROOT/$target"
    NEW_IMAGE=$(image_in "$BACKUP_ROOT/$target/compose.yml")
  elif [[ "$target" =~ ^[0-9a-f]{7,40}$ ]]; then
    # Tags are normally 7 chars; older ones have 8 (e.g. 454c1803). Prefer an exact match.
    if docker image inspect "amixof-for-web:$target" >/dev/null 2>&1; then NEW_IMAGE="amixof-for-web:$target"
    else NEW_IMAGE="amixof-for-web:${target:0:7}"; fi
  else
    die "unknown rollback target '$target'"
  fi
  [ -n "$NEW_IMAGE" ] || die "could not work out which image to roll back to"
  [ "$NEW_IMAGE" != "$live" ] || die "$NEW_IMAGE is already what compose names; nothing to roll back"
  docker image inspect "$NEW_IMAGE" >/dev/null 2>&1 || die "$NEW_IMAGE is not on this server; deploy that commit instead"
  swap_to rollback rolled_back
}

cmd_status() {
  local f; f=$(compose_file)
  printf 'COMPOSE_IMAGE=%s\nRUNNING_IMAGE=%s\nSERVED_BUNDLE=%s\n' "$(image_in "$f")" "$(running_image)" "$(container_bundle)"
  printf 'IMAGE_LINES=%s\n' "$(grep -cE "$LINE_RE" "$f" 2>/dev/null || true)"
  local d
  echo "RECENT_BACKUPS (name kind previous -> new):"
  { find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' 2>/dev/null || true; } | sort -r | head -n 8 | while IFS= read -r d; do
    printf '  %s %s %s -> %s\n' "$(basename "$d")" "$(cat "$d/kind" 2>/dev/null || echo manual)" \
      "$(image_in "$d/compose.yml")" "$(cat "$d/new-image" 2>/dev/null || echo '?')"
  done
  printf 'IMAGES=%s\n' "$( { docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true; } | { grep '^amixof-for-web:' || true; } | head -n 10 | tr '\n' ' ')"
  printf 'DISK_FREE=%s\n' "$(df -h --output=avail / | tail -n1 | tr -d ' ')"
  printf 'API_STATUS=%s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$PUBLIC_URL/api/" || true)"
  printf 'LOCK=%s\n' "$( (exec 8>"$LOCK"; flock -n 8 && echo free) 2>/dev/null || echo held)"
}

cmd=${1:-}; shift || true
case "$cmd" in
  deploy)   [ $# -eq 5 ] || die "usage: deploy <sha> <repo> <compose-dir> <service> <url>"
            COMPOSE_DIR=$3 SERVICE=$4 PUBLIC_URL=${5%/}; cmd_deploy "$1" "$2" ;;
  rollback) [ $# -eq 4 ] || die "usage: rollback <target> <compose-dir> <service> <url>"
            COMPOSE_DIR=$2 SERVICE=$3 PUBLIC_URL=${4%/}; cmd_rollback "$1" ;;
  status)   [ $# -eq 3 ] || die "usage: status <compose-dir> <service> <url>"
            COMPOSE_DIR=$1 SERVICE=$2 PUBLIC_URL=${3%/}; cmd_status ;;
  *) die "unknown command '$cmd'" ;;
esac
