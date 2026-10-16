#!/usr/bin/env bash
# Shared helpers for deploy.sh / rollback.sh / status.sh. Sourced, not executed.
# Written for macOS bash 3.2 + BSD tools as well as Linux.

say() { printf '\033[1m[amixof]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31m[amixof] ERROR:\033[0m %s\n' "$1" >&2; exit "${2:-1}"; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "run from inside the amixof-for-web repo"
cd "$ROOT" || exit 1
DEPLOY_DIR="$ROOT/.cursor/skills/amixof-deploy/scripts"
ARTIFACTS="$ROOT/.cursor/artifacts"
mkdir -p "$ARTIFACTS"

CONF="$ROOT/.cursor/amixof.env"
[ -f "$CONF" ] || die "missing $CONF — copy .cursor/amixof.env.example to .cursor/amixof.env and set AMIXOF_SSH"
set -a
# shellcheck disable=SC1090
. "$CONF"
set +a

: "${AMIXOF_SSH:?set AMIXOF_SSH in .cursor/amixof.env}"
[ "$AMIXOF_SSH" != "root@your-server" ] || die "AMIXOF_SSH in .cursor/amixof.env is still the placeholder"
AMIXOF_URL=${AMIXOF_URL:-https://www.amixof.com}
AMIXOF_URL=${AMIXOF_URL%/}
AMIXOF_COMPOSE_DIR=${AMIXOF_COMPOSE_DIR:-/opt/stoat}
AMIXOF_SERVICE=${AMIXOF_SERVICE:-web}
AMIXOF_REPO=${AMIXOF_REPO:-https://github.com/karbuunofficial/amixof-for-web.git}
AMIXOF_GIT_REMOTE=${AMIXOF_GIT_REMOTE:-amixof}
REMOTE_WORK=${AMIXOF_REMOTE_WORK:-/root/amixof-deploy}

# Everything sent to the server is validated here; nothing else reaches the remote shell.
matches() { printf '%s' "$1" | grep -Eq "$2"; }
[ "$AMIXOF_SERVICE" = web ] || die "AMIXOF_SERVICE must be 'web'; these scripts only manage the web client"
matches "$AMIXOF_URL" '^https?://[A-Za-z0-9.-]+(:[0-9]+)?$' || die "AMIXOF_URL must be scheme://host[:port] with no path, got '$AMIXOF_URL'"
matches "$AMIXOF_COMPOSE_DIR" '^/[A-Za-z0-9._/-]+$' || die "AMIXOF_COMPOSE_DIR looks wrong: '$AMIXOF_COMPOSE_DIR'"
matches "$AMIXOF_REPO" '^https://[A-Za-z0-9./_-]+$' || die "AMIXOF_REPO must be an https git URL"
matches "$REMOTE_WORK" '^/[A-Za-z0-9._/-]+$' || die "AMIXOF_REMOTE_WORK looks wrong"
matches "$AMIXOF_SSH" '^[A-Za-z0-9._@-]+$' || die "AMIXOF_SSH must be user@host or an ssh alias"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=4)

stamp() { date -u +%Y%m%d-%H%M%S; }

# Quote arguments for the remote shell.
qargs() { printf '%q ' "$@"; }

# The production login is debian with passwordless sudo. Root logins run the command directly.
# $1 is a remote shell snippet that must run as root (docker, /root, compose.yml).
ssh_as_root() {
  local snippet=$1 q
  q=$(printf '%q' "$snippet")
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "$AMIXOF_SSH" "if [ \"\$(id -u)\" -eq 0 ]; then bash -c $q; else sudo -n bash -c $q; fi"
}

# Read-only commands (status): stream remote.sh over stdin.
remote_inline() {
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "$AMIXOF_SSH" "if [ \"\$(id -u)\" -eq 0 ]; then bash -s -- $(qargs "$@"); else sudo -n bash -s -- $(qargs "$@"); fi" <"$DEPLOY_DIR/remote.sh"
}

# State-changing commands (deploy/rollback): upload remote.sh, start it detached on the server so
# a dropped connection cannot interrupt it, then follow its log until it prints EXIT=<code>.
# Sets REMOTE_LOG (server path) and writes the full output to the local file in $1.
remote_detached() {
  local local_log=$1; shift
  local runid; runid="$(stamp)-$$"
  REMOTE_LOG="$REMOTE_WORK/run-$runid.log"
  ssh_as_root "umask 077 && mkdir -p $(qargs "$REMOTE_WORK") && cat > $(qargs "$REMOTE_WORK/remote.sh")" \
    <"$DEPLOY_DIR/remote.sh" || die "could not upload remote.sh (ssh failed); nothing was changed" 2
  # shellcheck disable=SC2016
  ssh_as_root "cd / && setsid nohup bash -c 'bash \"\$0\" \"\$@\"; echo EXIT=\$?' $(qargs "$REMOTE_WORK/remote.sh" "$@") >$(qargs "$REMOTE_LOG") 2>&1 </dev/null & echo started" \
    >/dev/null || die "could not start remote.sh (ssh failed); nothing was changed" 2
  say "running on the server as $REMOTE_LOG (it keeps going if this connection drops)"

  : >"$local_log"
  local bytes=0 fails=0 start=$SECONDS chunk="$local_log.chunk"
  while :; do
    # shellcheck disable=SC2029
    if ssh "${SSH_OPTS[@]}" "$AMIXOF_SSH" "if [ \"\$(id -u)\" -eq 0 ]; then tail -c +$((bytes + 1)) $(qargs "$REMOTE_LOG"); else sudo -n tail -c +$((bytes + 1)) $(qargs "$REMOTE_LOG"); fi" >"$chunk" 2>/dev/null; then
      fails=0
      if [ -s "$chunk" ]; then
        cat "$chunk" >&2
        cat "$chunk" >>"$local_log"
        bytes=$((bytes + $(wc -c <"$chunk")))
      fi
      grep -q '^EXIT=' "$local_log" && break
    else
      fails=$((fails + 1))
      [ "$fails" -lt 30 ] || { rm -f "$chunk"; return 98; }
      say "lost the connection while following the log (try $fails); the server carries on"
    fi
    [ $((SECONDS - start)) -lt 3600 ] || { rm -f "$chunk"; return 99; }
    sleep "${AMIXOF_POLL_SECONDS:-5}"
  done
  rm -f "$chunk"
  return 0
}

# KEY=VALUE from a log file (last occurrence).
kv() { sed -n "s/^$2=//p" "$1" | tail -n1; }

append_runbook() {
  local entry=$1
  printf '%s\n\n' "$entry" >>"$ARTIFACTS/deploys.log"
  if [ -n "${AMIXOF_RUNBOOK_FILE:-}" ] && [ -f "$AMIXOF_RUNBOOK_FILE" ]; then
    printf '\n%s\n' "$entry" >>"$AMIXOF_RUNBOOK_FILE"
    say "appended record to $AMIXOF_RUNBOOK_FILE (commit it in that repo)"
  fi
}

# Explain a remote exit code and exit with it. $1 = code, $2 = local log.
explain_exit() {
  local code=$1 log=$2
  case "$code" in
    2) die "stopped before changing production (see log): $log" 2 ;;
    3) die "another deploy or rollback is running on the server; wait and retry. Nothing was changed." 3 ;;
    4) die "live checks failed; the server restored $(kv "$log" PREVIOUS) from $(kv "$log" BACKUP). Production is on the previous image. Log: $log" 4 ;;
    5) die "FAILED AND THE RESTORE ALSO FAILED — the site may be down. Tell the user now. Log: $log" 5 ;;
    *) die "outcome unknown (exit '${code:-none}'). Run status.sh before doing anything else. Log: $log" 7 ;;
  esac
}
