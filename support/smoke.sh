#!/usr/bin/env bash
#
# Boot a LibreChat image next to MongoDB and check that it serves.
#
#   support/smoke.sh <image>          # smoke test: wait for /health, check /, tear down
#   support/smoke.sh --run <image>    # manual run: foreground `compose up`, Ctrl-C to stop
#
# Used by CI after every build and by `make smoke` / `make run`.

set -euo pipefail

mode=smoke
if [ "${1:-}" = "--run" ]; then
    mode=run
    shift
fi
if [ "$#" -ne 1 ]; then
    echo "usage: $0 [--run] <image>" >&2
    exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
export LIBRECHAT_IMAGE="$1"
export LIBRECHAT_PORT="${LIBRECHAT_PORT:-3080}"
export CREDS_KEY="${CREDS_KEY:-$(openssl rand -hex 32)}"
export CREDS_IV="${CREDS_IV:-$(openssl rand -hex 16)}"
export JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 32)}"
export JWT_REFRESH_SECRET="${JWT_REFRESH_SECRET:-$(openssl rand -hex 32)}"

compose=(docker compose -f "${here}/compose.smoke.yaml")

if [ "${mode}" = run ]; then
    trap '"${compose[@]}" down -v --remove-orphans' EXIT
    "${compose[@]}" up
    exit 0
fi

ok=0
cleanup() {
    if [ "${ok}" -ne 1 ]; then
        echo "---- container logs ----" >&2
        "${compose[@]}" logs --no-color >&2 || true
    fi
    "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${compose[@]}" up -d --wait mongodb
"${compose[@]}" up -d api

base="http://127.0.0.1:${LIBRECHAT_PORT}"
timeout="${SMOKE_TIMEOUT:-180}"
echo "Waiting up to ${timeout}s for ${base}/health ..."
deadline=$(( $(date +%s) + timeout ))
until curl -fsS "${base}/health" >/dev/null 2>&1; do
    if [ -z "$("${compose[@]}" ps -q --status running api)" ]; then
        echo "error: api container exited" >&2
        exit 1
    fi
    if [ "$(date +%s)" -ge "${deadline}" ]; then
        echo "error: /health did not become ready within ${timeout}s" >&2
        exit 1
    fi
    sleep 3
done
echo "/health OK"

body="$(curl -fsS "${base}/")"
if ! printf '%s' "${body}" | grep -qi '<div id="root"'; then
    echo "error: / did not serve the client HTML" >&2
    printf '%s\n' "${body}" | head -n 20 >&2
    exit 1
fi
echo "/ serves client HTML"

ok=1
echo "Smoke test passed for ${LIBRECHAT_IMAGE}"
