# Local-only patch-authoring and test-build workflow for the patched LibreChat image.
# GitHub Actions does NOT use this Makefile -- see .github/workflows/build.yaml
# (it shares the support/ scripts, so local and CI behave the same).

SHELL := /bin/bash

LC_REPO ?= https://github.com/LibreChat-AI/LibreChat.git
# Empty = newest stable vX.Y.Z tag (resolved at clone time by support/latest-tag.sh).
LC_REF  ?=

SRC     := src
PATCHES := patches
QUILTRC := $(CURDIR)/.quiltrc
IMAGE   ?= librechat-patched:local
# Extra arguments for `docker build`, e.g. DOCKER_BUILD_ARGS='--build-arg NODE_MAX_OLD_SPACE_SIZE=4096'
DOCKER_BUILD_ARGS ?=

# quilt environment used inside $(SRC)/: our patches/ dir is the quilt patch dir.
QUILT_ENV := QUILTRC=$(QUILTRC) QUILT_PATCHES=$(CURDIR)/$(PATCHES)

.DEFAULT_GOAL := help
.PHONY: help prepare-src prepare build smoke run refresh clean clean-image

help:
	@echo 'Local patch-authoring / test-build workflow (not used by CI).'
	@echo
	@echo 'Targets:'
	@echo '  prepare-src        clone LibreChat into $(SRC)/ (no patches applied)'
	@echo '  prepare [QUILT=1]  prepare-src + apply $(PATCHES)/series strictly (fuzz=0, same as CI).'
	@echo '                     QUILT=1 prints patch authoring steps.'
	@echo '  build              docker build --target node $(SRC)/ -> $(IMAGE)'
	@echo '  smoke              boot $(IMAGE) with MongoDB and check /health and / (same as CI)'
	@echo '  run                boot $(IMAGE) with MongoDB in the foreground (http://localhost:3080)'
	@echo '  refresh            re-push every patch with fuzz allowed and quilt-refresh it'
	@echo '                     against the current $(SRC)/ (use after moving to a new LC_REF)'
	@echo '  clean              remove $(SRC)/'
	@echo '  clean-image        remove $(IMAGE)'
	@echo
	@echo 'Variables: LC_REF (default: newest stable tag), LC_REPO, IMAGE (default $(IMAGE)),'
	@echo '           DOCKER_BUILD_ARGS'
	@echo
	@echo 'Patch authoring:  make clean prepare QUILT=1  ->  quilt new/add/edit/refresh (in $(SRC)/)'
	@echo 'New upstream tag: make clean prepare-src LC_REF=vX.Y.Z  ->  make refresh'
	@echo 'Test build:       make prepare build smoke'

$(SRC)/.git:
	@set -e; ref='$(LC_REF)'; \
	if [ -z "$$ref" ]; then ref=$$(LC_REPO='$(LC_REPO)' bash support/latest-tag.sh); fi; \
	echo "Cloning LibreChat $$ref into $(SRC)/"; \
	git clone --depth 1 --branch "$$ref" '$(LC_REPO)' $(SRC)

prepare-src: $(SRC)/.git

prepare: prepare-src
	@bash support/apply-patches.sh $(SRC)
ifeq ($(QUILT),1)
	@echo
	@echo 'Patch authoring (quilt writes straight into $(PATCHES)/):'
	@echo '  export QUILTRC=$(QUILTRC) QUILT_PATCHES=$(CURDIR)/$(PATCHES)'
	@echo '  cd $(SRC)'
	@echo '  quilt new <NNNN-name>.patch ; quilt add <file> ; quilt edit <file> ; quilt refresh'
endif

build:
	@test -d $(SRC) || { echo "No $(SRC)/ -- run 'make prepare' first"; exit 1; }
	docker build --target node -t '$(IMAGE)' $(DOCKER_BUILD_ARGS) $(SRC)

smoke:
	bash support/smoke.sh '$(IMAGE)'

run:
	bash support/smoke.sh --run '$(IMAGE)'

# Rebase the whole series onto the current $(SRC)/: pop everything, then push one
# patch at a time with fuzz allowed and refresh it so it applies with fuzz=0 again.
# Stops at the first rejecting patch; fix it (quilt push -f, resolve .rej, quilt
# refresh) and re-run.
refresh:
	@test -d $(SRC) || { echo "No $(SRC)/ -- run 'make prepare-src' first"; exit 1; }
	@set -e; \
	if ! grep -qvE '^[[:space:]]*(#|$$)' $(PATCHES)/series; then echo "$(PATCHES)/series is empty -- nothing to refresh."; exit 0; fi; \
	cd $(SRC); export $(QUILT_ENV); \
	quilt pop -a >/dev/null 2>&1 || true; \
	while :; do \
		rc=0; quilt push --fuzz=2 || rc=$$?; \
		if [ $$rc -eq 2 ]; then break; fi; \
		if [ $$rc -ne 0 ]; then \
			echo "Patch '$$(quilt next)' rejects: fix it with 'quilt push -f', resolve the .rej hunks, 'quilt refresh', then re-run 'make refresh'."; \
			exit 1; \
		fi; \
		quilt refresh; \
	done; \
	echo "All patches refreshed in $(PATCHES)/ -- review and commit."

clean:
	rm -rf $(SRC)

clean-image:
	-docker image rm '$(IMAGE)'
