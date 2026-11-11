#!/usr/bin/env bash
#
# Print the newest stable (vX.Y.Z, no pre-release suffix) LibreChat tag.
# Used by both CI (.github/workflows/build.yaml) and the Makefile.
#
# Uses `gh api` when available (CI: authenticated, no clone needed), otherwise
# falls back to `git ls-remote`.

set -euo pipefail

LC_GH_REPO="${LC_GH_REPO:-LibreChat-AI/LibreChat}"
LC_REPO="${LC_REPO:-https://github.com/${LC_GH_REPO}.git}"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    tags="$(gh api --paginate "repos/${LC_GH_REPO}/git/matching-refs/tags/v" --jq '.[].ref')"
else
    tags="$(git ls-remote --tags --refs "${LC_REPO}" 'v*' | awk '{print $2}')"
fi

latest="$(printf '%s\n' "${tags}" \
    | sed 's#^refs/tags/##' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n1 || true)"

if [ -z "${latest}" ]; then
    echo "error: no stable vX.Y.Z tag found in ${LC_GH_REPO}" >&2
    exit 1
fi

printf '%s\n' "${latest}"
