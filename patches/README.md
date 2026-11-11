# patches/

Quilt patch series applied on top of upstream
[LibreChat](https://github.com/LibreChat-AI/LibreChat) before the Docker image is built.
`series` lists the patches in application order; an empty `series` builds stock upstream.

This directory **is** the quilt patch directory (`QUILT_PATCHES=../patches` from `src/`),
so `quilt new` / `quilt refresh` write here directly -- no copy-back step.

## Authoring

```sh
make clean prepare QUILT=1
export QUILTRC="$PWD/.quiltrc"
cd src
export QUILT_PATCHES=../patches
quilt push -a                         # apply the existing series
quilt new 0004-my-change.patch        # see "Numbering" below
quilt add api/server/index.js         # before editing!
quilt edit api/server/index.js        # ... make changes ...
quilt refresh
```

## Numbering

The number range says what kind of patch it is (and therefore what to do with it when
upstream changes). Within a range, number sequentially; `series` lists patches in
ascending order.

| Range | Kind |
|---|---|
| `0001`-`0999` | Standalone fixes: self-contained, could go upstream; drop once upstream fixes it. |
| `1000`-`1999` | Other patches that fit none of the ranges below. |
| `6000`-`6999` | Depends on `pkg-patches/` (meaningless or broken without the matching patch-package patches; add/remove them together). |
| `9000`-`9999` | Local-only or local policy (builder infrastructure, behaviour we choose to differ from upstream). |

## Strict application (fuzz = 0)

CI applies the series with `quilt push -a --fuzz=0` (`support/apply-patches.sh`). Any
patch that needs fuzz or rejects fails the build. Because CI follows the newest stable
upstream tag daily, a failed scheduled run usually means a new release moved code our
patches touch. To fix it:

```sh
make clean prepare-src LC_REF=vX.Y.Z   # clone the new tag without applying patches
make refresh                           # push each patch (fuzz allowed) and refresh it
```

`make refresh` stops at the first patch that rejects; resolve it by hand
(`quilt push -f`, fix the `.rej` hunks, `quilt refresh`) and re-run `make refresh`.
