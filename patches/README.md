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
quilt new 0001-my-change.patch
quilt add api/server/index.js         # before editing!
quilt edit api/server/index.js        # ... make changes ...
quilt refresh
```

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
