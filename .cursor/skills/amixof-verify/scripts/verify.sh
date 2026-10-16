#!/usr/bin/env bash
# Local quality gate for amixof-for-web. Runs every check, then prints a summary.
#
#   bash .cursor/skills/amixof-verify/scripts/verify.sh          # standard gate (used by deploy.sh)
#   bash .cursor/skills/amixof-verify/scripts/verify.sh --full   # + i18n catalog check, e2e, local visual check
#   bash .cursor/skills/amixof-verify/scripts/verify.sh --fast   # typecheck + lint + brand scan only
#
# Exit 0 only when every step passed.
set -Euo pipefail

ROOT=$(git rev-parse --show-toplevel) || exit 1
cd "$ROOT" || exit 1
MODE=${1:-standard}
ART="$ROOT/.cursor/artifacts/verify-$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$ART"

# Build against the AMIXOF instance, not the upstream default (which would flip isStoat on).
AMIXOF_URL=https://www.amixof.com
if [ -f .cursor/amixof.env ]; then
  AMIXOF_URL=$(sed -n 's/^AMIXOF_URL=//p' .cursor/amixof.env | tail -n1 | tr -d "\"'" | tr -d '[:space:]')
  AMIXOF_URL=${AMIXOF_URL:-https://www.amixof.com}
fi
AMIXOF_URL=${AMIXOF_URL%/}
export VITE_API_URL="${VITE_API_URL:-$AMIXOF_URL/api}"
export VITE_HOST="${VITE_HOST:-${AMIXOF_URL#https://}}"

RESULTS=()
FAILED=0
step() {
  local name=$1; shift
  local log
  log="$ART/$(printf '%s' "$name" | tr ' /' '__').log"
  printf '\033[1m▶ %s\033[0m\n' "$name"
  local start=$SECONDS
  if "$@" >"$log" 2>&1; then
    RESULTS+=("PASS  $name ($((SECONDS - start))s)")
  else
    RESULTS+=("FAIL  $name ($((SECONDS - start))s) — $log")
    FAILED=1
    tail -n 30 "$log"
  fi
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing '$1' — $2" >&2; exit 1; }; }
need node "install Node 22+ (mise install, or nvm)"
if ! command -v pnpm >/dev/null 2>&1; then
  corepack enable >/dev/null 2>&1 || true
fi
need pnpm "run: corepack enable && corepack prepare pnpm@11.3.0 --activate"

# ---------- setup (fails fast) ----------
for sm in packages/stoat.js packages/solid-livekit-components; do
  if [ ! -f "$sm/package.json" ]; then
    echo "submodule $sm missing — run: git submodule update --init packages/stoat.js packages/solid-livekit-components" >&2
    exit 1
  fi
done

printf '\033[1m▶ install\033[0m\n'
pnpm install --frozen-lockfile >"$ART/install.log" 2>&1 || { tail -n 40 "$ART/install.log"; echo "pnpm install failed" >&2; exit 1; }

STAMP=node_modules/.amixof-deps-stamp
WANT="$(git -C packages/stoat.js rev-parse HEAD 2>/dev/null)-$(git -C packages/solid-livekit-components rev-parse HEAD 2>/dev/null)"
if [ "$(cat "$STAMP" 2>/dev/null)" != "$WANT" ]; then
  printf '\033[1m▶ build deps (stoat.js, livekit)\033[0m\n'
  { pnpm --filter stoat.js build && pnpm --filter solid-livekit-components build; } >"$ART/deps.log" 2>&1 \
    || { tail -n 40 "$ART/deps.log"; echo "dependency build failed" >&2; exit 1; }
  printf '%s' "$WANT" >"$STAMP"
fi

printf '\033[1m▶ codegen (lingui, assets, panda)\033[0m\n'
{ pnpm --filter client exec lingui compile --typescript \
  && pnpm --filter client exec node scripts/copyAssets.mjs \
  && pnpm --filter client exec panda codegen; } >"$ART/codegen.log" 2>&1 \
  || { tail -n 40 "$ART/codegen.log"; echo "codegen failed" >&2; exit 1; }

# ---------- checks ----------
step "typecheck" pnpm --filter client exec tsc --noEmit
step "lint" pnpm exec eslint packages/client
step "brand scan" node .cursor/skills/amixof-audit/scripts/brand-scan.mjs

if [ "$MODE" != "--fast" ]; then
  step "format" pnpm exec prettier --check 'packages/client/**/*.{ts,tsx,json}'
  step "production build" pnpm --filter client exec vite build
  if [ -d packages/client/dist/assets ]; then
    du -sh packages/client/dist >"$ART/bundle-size.txt" 2>/dev/null || true
    # largest JS chunks, in KB
    du -k packages/client/dist/assets/*.js 2>/dev/null | sort -rn | head -n 5 >>"$ART/bundle-size.txt"
  fi
fi

if [ "$MODE" = "--full" ]; then
  # shellcheck disable=SC2329  # invoked through step
  check_catalogs() {
    pnpm --filter client exec lingui extract >/dev/null
    if git status --porcelain -- packages/client/components/i18n/catalogs | grep -q .; then
      echo "lingui extract changed catalogs — commit them:"; git status --short -- packages/client/components/i18n/catalogs; return 1
    fi
  }
  step "i18n catalogs up to date" check_catalogs

  # shellcheck disable=SC2329  # invoked through step
  preview_checks() {
    (cd packages/client && exec ./node_modules/.bin/vite preview --host localhost --port 4173 --strictPort) >"$ART/preview-server.log" 2>&1 &
    local pid=$!
    for _ in $(seq 1 30); do curl -fsS -o /dev/null http://localhost:4173/ 2>/dev/null && break; sleep 1; done
    local ok=0
    pnpm --filter client exec playwright test --project=chromium --reporter=line || ok=1
    node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs --base http://localhost:4173 --out "$ART/screens" || ok=1
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    return "$ok"
  }
  step "e2e + visual (local preview)" preview_checks
fi

echo
echo "──────── verify summary ($MODE) ────────"
printf '%s\n' "${RESULTS[@]}"
[ -f "$ART/bundle-size.txt" ] && { echo "bundle:"; cat "$ART/bundle-size.txt"; }
echo "logs: $ART"
exit $FAILED
