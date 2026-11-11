#!/usr/bin/env bash
#
# Strictly apply the quilt series in patches/ to a LibreChat checkout.
#
#   support/apply-patches.sh <librechat-src-dir>
#
# Patches are pushed with --fuzz=0: a patch that needs fuzz or rejects fails the
# run, so drift against a new upstream tag surfaces as a CI failure instead of a
# silently mis-applied patch. An empty series is a no-op.
# Used by CI; the Makefile's `prepare` target applies the same way.

set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "usage: $0 <librechat-src-dir>" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$(cd "$1" && pwd)"

export QUILTRC="${root}/.quiltrc"
export QUILT_PATCHES="${root}/patches"

if ! grep -qvE '^[[:space:]]*(#|$)' "${QUILT_PATCHES}/series" 2>/dev/null; then
    echo "patches/series is empty -- building stock upstream."
    exit 0
fi

cd "${src}"
rc=0
quilt push -a --fuzz=0 || rc=$?
# quilt exits 2 when there is nothing left to push (all patches already applied).
if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 2 ]; then
    echo "error: patch series failed to apply cleanly (fuzz=0) -- run 'make refresh'." >&2
    exit "${rc}"
fi
quilt applied
