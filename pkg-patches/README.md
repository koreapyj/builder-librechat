# pkg-patches/

[patch-package](https://github.com/ds300/patch-package) patches for npm dependencies of
LibreChat (currently `@librechat/agents`, whose published `dist/` carries the bugs).

`support/apply-patches.sh` stages every `*.patch` here into the LibreChat checkout's
`pkg-patches/`, and the Docker build runs
`npx patch-package@8.0.1 --error-on-fail --patch-dir pkg-patches` right after `npm ci`
(see `patches/9001-docker-apply-pkg-patches.patch`).

Patches use patch-package's sequence naming, one file per fix:

```
@librechat+agents+<version>+001+<name>.patch
@librechat+agents+<version>+002+<name>.patch
```

## Version policy

Only `--error-on-fail` is set: if the locked package version moves but the patched code is
unchanged, the patch still applies (patch-package prints a version-mismatch warning). If a
hunk no longer matches (context must match exactly; position may drift by up to 20 lines),
the build fails -- regenerate the patch against the new version.

## Authoring

Edit the published files of the exact version LibreChat locks, then let patch-package diff:

```sh
make prepare            # LibreChat checkout in ./src (for the locked version)
make pkg-prepare        # install that version into ./.pkgwork and apply existing patches
# edit .pkgwork/node_modules/@librechat/agents/dist/{cjs,esm}/...
make pkg-update APPEND=my-fix       # new patch appended to the sequence
make pkg-update                     # or: update the last patch in the sequence
```

Patch both `dist/cjs` and `dist/esm` so the two builds stay equivalent.
