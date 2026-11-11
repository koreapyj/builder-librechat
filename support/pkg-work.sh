#!/usr/bin/env bash
#
# patch-package authoring workspace for npm dependencies of LibreChat.
#
#   support/pkg-work.sh prepare <librechat-src-dir> <workdir> [pkg]
#       Install the exact version of <pkg> (default @librechat/agents) that the
#       checkout's package-lock.json pins into <workdir>, then apply the existing
#       pkg-patches/ to it.
#   support/pkg-work.sh update <workdir> [pkg] [append-name]
#       Diff <workdir>/node_modules/<pkg> against the pristine package and write
#       the result into pkg-patches/ (with --append when append-name is given).
#
# npm/npx run on the host when available (fast, native filesystem). Without a
# host Node.js they run in a node container instead (set PKG_WORK_DOCKER=1 to
# force that). Creating a patch needs git, which patch-package calls itself.
# Local-only.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
NODE_IMAGE="${NODE_IMAGE:-node:24.16.0-alpine}"
PATCH_PACKAGE="${PATCH_PACKAGE:-patch-package@8.0.1}"

use_docker=0
if [ "${PKG_WORK_DOCKER:-0}" = 1 ] || ! command -v npm >/dev/null 2>&1; then
    use_docker=1
fi

# run_in <workdir> <script>: run a POSIX sh script with cwd=<workdir>, where
# $PKG_PATCHES points at the repo's pkg-patches/ directory.
run_in() {
    local dir="$1" script="$2"
    if [ "${use_docker}" = 1 ]; then
        # Run as root so git can be installed; hand files back to the host user.
        docker run --rm -e HOME=/tmp -e PKG_PATCHES=/pkg-patches \
            -v "${dir}:/work" -v "${root}/pkg-patches:/pkg-patches" -w /work \
            "${NODE_IMAGE}" sh -euc "
            command -v git >/dev/null || apk add --no-cache git >/dev/null
            ${script}
            chown -R $(id -u):$(id -g) /work /pkg-patches
        "
    else
        (cd "${dir}" && PKG_PATCHES="${root}/pkg-patches" sh -euc "${script}")
    fi
}

lock_version() {
    # $1 = package-lock.json, $2 = package name
    if command -v node >/dev/null 2>&1; then
        node -e 'const l=require(require("path").resolve(process.argv[1]));console.log(l.packages["node_modules/"+process.argv[2]].version)' "$1" "$2"
    else
        python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"]["node_modules/"+sys.argv[2]]["version"])' "$1" "$2"
    fi
}

cmd="${1:-}"
case "${cmd}" in
prepare)
    [ "$#" -ge 3 ] || { echo "usage: $0 prepare <src-dir> <workdir> [pkg]" >&2; exit 2; }
    src="$(cd "$2" && pwd)"
    work="$3"
    pkg="${4:-@librechat/agents}"
    version="$(lock_version "${src}/package-lock.json" "${pkg}")"
    echo "Preparing ${pkg}@${version} in ${work}/"
    rm -rf "${work}"
    mkdir -p "${work}"
    work="$(cd "${work}" && pwd)"
    printf '{\n  "name": "pkgwork",\n  "private": true,\n  "dependencies": { "%s": "%s" }\n}\n' \
        "${pkg}" "${version}" > "${work}/package.json"
    # patch-package resolves --patch-dir relative to the project, so the repo's
    # pkg-patches/ is copied into the workdir first.
    run_in "${work}" "
        npm install --ignore-scripts --no-audit --no-fund --loglevel=error
        rm -rf patches-in && mkdir patches-in
        for p in \"\$PKG_PATCHES\"/*.patch; do [ -e \"\$p\" ] && cp \"\$p\" patches-in/; done
        npx --yes ${PATCH_PACKAGE} --error-on-fail --patch-dir patches-in
        rm -rf patches-in
    "
    echo "Ready: edit ${work}/node_modules/${pkg}/ then run 'make pkg-update'."
    ;;
update)
    [ "$#" -ge 2 ] || { echo "usage: $0 update <workdir> [pkg] [append-name]" >&2; exit 2; }
    work="$(cd "$2" && pwd)"
    pkg="${3:-@librechat/agents}"
    append="${4:-}"
    args="${pkg} --patch-dir patches-out"
    [ -n "${append}" ] && args="${args} --append '${append}'"
    run_in "${work}" "
        rm -rf patches-out && mkdir patches-out
        for p in \"\$PKG_PATCHES\"/*.patch; do [ -e \"\$p\" ] && cp \"\$p\" patches-out/; done
        npx --yes ${PATCH_PACKAGE} ${args}
        # Drop permission-bit changes: on some host filesystems (e.g. WSL /mnt/c)
        # every file looks executable, which would add a mode change for every
        # file. Keep only blocks that carry content changes.
        for p in patches-out/*.patch; do
            awk '
                function flush() { if (blk != \"\" && keep) printf \"%s\", blk }
                /^diff --git / { flush(); blk = \$0 \"\\n\"; keep = 0; next }
                /^(old|new) mode / { next }
                /^index / { sub(/ [0-7]+\$/, \"\") }
                { blk = blk \$0 \"\\n\"; if (\$0 ~ /^(--- |@@|Binary |new file |deleted file |rename )/) keep = 1 }
                END { flush() }
            ' \"\$p\" > \"\$p.tmp\" && mv \"\$p.tmp\" \"\$p\"
        done
        rm -f \"\$PKG_PATCHES\"/*.patch
        cp patches-out/*.patch \"\$PKG_PATCHES\"/
        rm -rf patches-out
    "
    ls -1 "${root}/pkg-patches"
    ;;
*)
    echo "usage: $0 {prepare|update} ..." >&2
    exit 2
    ;;
esac
