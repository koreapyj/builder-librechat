#!/usr/bin/env bash
#
# Apply both patch tiers to a LibreChat checkout.
#
#   support/apply-patches.sh <librechat-src-dir>
#
# 1. patches/      quilt series against LibreChat source, pushed with --fuzz=0:
#                  a patch that needs fuzz or rejects fails the run, so drift
#                  against a new upstream tag surfaces as a CI failure instead
#                  of a silently mis-applied patch. An empty series is a no-op.
# 2. pkg-patches/  patch-package patches for npm dependencies. Staged into
#                  <src>/pkg-patches/ (always created, possibly empty) and
#                  applied inside the Docker build right after `npm ci`
#                  (see patches/9001-docker-apply-pkg-patches.patch).
#
# Used by CI and by the Makefile's `prepare` target.

set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "usage: $0 <librechat-src-dir>" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$(cd "$1" && pwd)"

export QUILTRC="${root}/.quiltrc"
export QUILT_PATCHES="${root}/patches"

if grep -qvE '^[[:space:]]*(#|$)' "${QUILT_PATCHES}/series" 2>/dev/null; then
    rc=0
    (cd "${src}" && quilt push -a --fuzz=0) || rc=$?
    # quilt exits 2 when there is nothing left to push (all patches already applied).
    if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 2 ]; then
        echo "error: patch series failed to apply cleanly (fuzz=0) -- run 'make refresh'." >&2
        exit "${rc}"
    fi
    (cd "${src}" && quilt applied)
else
    echo "patches/series is empty -- no LibreChat source patches."
fi

rm -rf "${src}/pkg-patches"
mkdir -p "${src}/pkg-patches"
count=0
for p in "${root}"/pkg-patches/*.patch; do
    [ -e "${p}" ] || continue
    cp "${p}" "${src}/pkg-patches/"
    count=$((count + 1))
done
echo "Staged ${count} patch-package patch(es) into ${src}/pkg-patches/."
