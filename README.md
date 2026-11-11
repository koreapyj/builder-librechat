# builder-librechat

Builds a Docker image of [LibreChat](https://github.com/LibreChat-AI/LibreChat) with our
patches applied on top of the newest stable upstream release, and publishes it to
`ghcr.io/koreapyj/librechat`.

The image is upstream's own `Dockerfile` (`--target node`, API + client in one image),
built from the patched checkout -- a drop-in replacement for `librechat/librechat`.

## Two kinds of patches

- [`patches/`](patches/) -- **LibreChat source** patches, a quilt series applied to the
  checkout with `--fuzz=0` before the build. `9001-docker-apply-pkg-patches.patch` hooks the
  second tier into upstream's `Dockerfile`.
- [`pkg-patches/`](pkg-patches/) -- **npm dependency** patches (e.g. the published `dist/` of
  `@librechat/agents`), made with [patch-package](https://github.com/ds300/patch-package).
  Staged into the checkout and applied inside the Docker build right after `npm ci`, with
  `--error-on-fail`.

## Image tags

| Tag | Meaning |
|-----|---------|
| `vX.Y.Z-<rev>` | upstream `vX.Y.Z` + patch set `<rev>` (immutable) |
| `vX.Y.Z-<rev>-amd64` / `-arm64` | per-arch images behind the tag above |
| `vX.Y.Z` | newest patch set for upstream `vX.Y.Z` |
| `latest` | newest stable upstream + newest patch set |

`<rev>` is the first 12 hex digits of a sha256 over `patches/series`, the `*.patch` files in
`patches/` and `pkg-patches/`, and `support/apply-patches.sh`, so it changes only when the
built content changes.

## CI: daily latest-stable tracking

[`.github/workflows/build.yaml`](.github/workflows/build.yaml) runs daily (and on push / PR /
manual dispatch):

1. **resolve** -- picks the newest `vX.Y.Z` tag of LibreChat (pre-releases ignored), computes
   `<rev>`, and skips everything if `vX.Y.Z-<rev>` is already published.
2. **build** -- clones the tag, applies `patches/series` with `quilt push -a --fuzz=0`,
   stages `pkg-patches/` (applied by patch-package during the image build), builds the image natively on amd64 and arm64 runners, smoke-tests it (boots with MongoDB,
   checks `/health` and `/`), and pushes the per-arch image.
3. **manifest** -- publishes the multi-arch `vX.Y.Z-<rev>`, `vX.Y.Z` and `latest` tags.

Only the default branch publishes; PRs and other branches build and smoke-test amd64 only.
`workflow_dispatch` accepts `lc_ref` (build a specific upstream ref; never tagged `latest`)
and `force` (rebuild even if already published).

**A failed run means work is needed.** Most often a new upstream release changed code a
patch touches and the series no longer applies with zero fuzz; see below.

## Local workflow

Requirements: `docker` (with compose), `make`, `git`, `quilt`, `openssl`, `curl`.
The [`Makefile`](Makefile) is local-only; CI calls the same `support/` scripts.

### Test the current series

```sh
make prepare      # clone newest stable LibreChat into ./src/ and apply patches/ (fuzz=0)
make build        # docker build --target node ./src -> librechat-patched:local
make smoke        # same smoke test as CI
make run          # boot it with MongoDB at http://localhost:3080 (Ctrl-C to stop)
```

### Author a patch

`patches/` is the quilt patch directory itself, so quilt writes there directly:

```sh
make clean prepare QUILT=1
export QUILTRC="$PWD/.quiltrc" QUILT_PATCHES="$PWD/patches"
cd src
quilt new 0004-my-change.patch         # numbering: see patches/README.md
quilt add api/server/index.js          # before editing
quilt edit api/server/index.js         # ... make changes ...
quilt refresh
```

### Move to a new upstream release (fix a failed CI run)

```sh
make clean prepare-src LC_REF=vX.Y.Z   # clone without applying patches
make refresh                           # push each patch with fuzz allowed, then quilt refresh
```

`make refresh` stops at the first patch that rejects; fix it (`quilt push -f`, resolve the
`.rej` hunks, `quilt refresh`) and re-run it. Then `make build smoke` and commit `patches/`.

If a `pkg-patches/` patch fails instead (the dependency version moved and the patched code
changed), regenerate it as described below.

### Author an npm dependency patch

```sh
make prepare                     # ./src pins the dependency version via package-lock.json
make pkg-prepare                 # install that version into ./.pkgwork, apply pkg-patches/
# edit .pkgwork/node_modules/@librechat/agents/dist/{cjs,esm}/...
make pkg-update APPEND=my-fix    # append a new patch to the sequence (or omit APPEND to
                                 # update the last one)
```

### Run unit tests

```sh
make prepare test-image                      # one-time: npm ci + package builds in an image
make test CMD='cd api && npx jest server/controllers/agents/client.test.js'
make test TREE=path/to/other/tree CMD='...'  # test another LibreChat tree on the same image
```

### Variables

`LC_REF` (default: newest stable tag), `LC_REPO`, `IMAGE` (default `librechat-patched:local`),
`DOCKER_BUILD_ARGS`, `PKG`, `PKGWORK`, `TEST_IMAGE`, `TREE`, `CMD`. Run `make help` for the
full list.
