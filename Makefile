# FloMorphic — build and publish the product image.
#
# One image, `mehdishokohi/flomorphic`: the canvas, the API and the builtin
# plugin nodes behind a single nginx. Why they share a container rather than
# three is docker/Dockerfile.flomorphic's header; the short version is that the
# plugin nodes cannot start until the API has minted their NATS credential, so
# the entrypoint discovers and runs them itself. Nothing here publishes a
# separate api/wapp image.
#
# The version is the repo's own git tag — this repo is the release marker for
# the product, so `git tag v0.2.0 && make release` is the whole ceremony.
#
# That tag names the IMAGE, and nothing else. FloMorphic is a wrapped product
# built from several repos, and making all of them carry one synchronised version
# would mean tagging four repos in lockstep for every release — cost with no
# reader. So morph-api, morph-wapp and builtin-plugins are tracked at their
# DEFAULT BRANCH, and a ref the remote does not have (main here, master there)
# resolves to its HEAD instead of failing the build. Pin a release to exact
# component refs only when you want to:
#   make release API_REF=v0.3.0 WAPP_REF=v0.3.0 PLUGINS_REF=v0.3.0
#
#   make tag VERSION=v0.2.0     # annotate + push the tag this release is named after
#   make release                # multi-arch :$(VERSION) + :latest, pushed
#   make build                  # host-arch :local, for trying it before publishing
#
# ── two channels, one repository ──────────────────────────────────────────────
#
#   :$(VERSION)  :latest         Dockerfile.flomorphic-src — ships a toolchain and
#                                compiles the sources at CONTAINER start. One
#                                manifest serves every arch because the compile
#                                happens on the target machine, so this is what
#                                install.sh pulls by default. First boot takes a
#                                few minutes; restarts are quick (/src is a volume).
#
#   :$(VERSION)-baked  :baked    Dockerfile.flomorphic — everything compiled at
#                                IMAGE build time, so the container starts in
#                                seconds. Genuinely per-arch: building the arm64
#                                variant on an amd64 host means a cgo sqlite build
#                                under QEMU, which is slow enough that it is not
#                                part of `release`. See `release-baked`.
#
# Both images take the same env and expose the same ports — the only difference
# is when things compile.

VERSION    := $(shell git describe --tags --abbrev=0 2>/dev/null)
IMAGE_NAME := mehdishokohi/flomorphic

# What the image is built from: branches or tags in the component repos, never
# this repo's tag. `main` is a hint, not a constraint — a repo whose default
# branch is `master` (or anything else) is cloned at its HEAD instead, so no
# component repo has to be renamed or tagged to keep a release working.
API_REPO     ?= https://github.com/FloMorphic/morph-api.git
API_REF      ?= main
WAPP_REPO    ?= https://github.com/FloMorphic/morph-wapp.git
WAPP_REF     ?= main
PLUGINS_REPO ?= https://github.com/FloMorphic/builtin-plugins.git
PLUGINS_REF  ?= main

# Go module proxy. Passed as a build arg, and both Dockerfiles carry it into the
# runtime as ENV GOPROXY — so this value is (a) what the baked build compiles
# through and (b) the default every published container compiles through, since
# the self-building image and a changed PLUGINS_REF both fetch modules at run
# time. Empty leaves the Dockerfile default (proxy.golang.org) in place.
#
# It defaults to the mirror because proxy.golang.org redirects module zips to
# storage.googleapis.com and networks that block it answer 403 mid-download —
# including this one. To publish with the upstream CDN as the shipped default:
#   make release IMAGE_GOPROXY=
#
# Deliberately NOT called GOPROXY: make imports the environment, a Go
# development box usually exports GOPROXY, and `?=` loses to it — which would
# quietly bake whatever the shell happened to hold into a published image.
IMAGE_GOPROXY ?= https://goproxy.cn,direct

# The self-building image is a handful of apk/npm layers, so a fresh one on every
# release is worth the minute and rules out a stale base. The baked image is a
# full cgo + pnpm compile, so it keeps its cache. Override either.
SRC_NO_CACHE   ?= --no-cache
BAKED_NO_CACHE ?=

# buildx builder to use. Empty = whatever `docker buildx` currently defaults to.
BUILDER ?=

# Local tag for `make build` / `make run` — never pushed.
LOCAL_IMAGE ?= flomorphic:local

# Host port for `make run`.
PORT ?= 8090

SRC_DOCKERFILE   := docker/Dockerfile.flomorphic-src
BAKED_DOCKERFILE := docker/Dockerfile.flomorphic

BUILDX := docker buildx build $(if $(BUILDER),--builder $(BUILDER),)
# The same set for both Dockerfiles, meaning different things in each: the baked
# one clones at these refs during the build, the self-building one stores them as
# the ENV defaults it will clone at when the container starts (still overridable
# with `docker run -e` / the compose file).
BUILD_ARGS := \
	--build-arg API_REPO=$(API_REPO) \
	--build-arg API_REF=$(API_REF) \
	--build-arg WAPP_REPO=$(WAPP_REPO) \
	--build-arg WAPP_REF=$(WAPP_REF) \
	--build-arg PLUGINS_REPO=$(PLUGINS_REPO) \
	--build-arg PLUGINS_REF=$(PLUGINS_REF) \
	$(if $(IMAGE_GOPROXY),--build-arg GOPROXY=$(IMAGE_GOPROXY),)

.DEFAULT_GOAL := help

.PHONY: help version check-version check-arm64 login builder binfmt \
	build build-baked run stop \
	docker-amd64 docker-arm64 docker \
	docker-push-amd64 docker-push-arm64 docker-push push-latest release \
	baked-amd64 baked-arm64 baked \
	baked-push-amd64 baked-push-arm64 baked-push push-baked release-baked \
	release-baked-latest \
	tag inspect clean

help: ## Show this help
	@printf 'FloMorphic image targets — %s\n\n' "$(IMAGE_NAME)"
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@printf '\nversion: %s   refs: api=%s wapp=%s plugins=%s\n' \
	  "$(if $(VERSION),$(VERSION),none - see the tag target)" \
	  "$(API_REF)" "$(WAPP_REF)" "$(PLUGINS_REF)"

version: ## Print the version and the tags a release would push
	@printf 'VERSION       %s\n' "$(if $(VERSION),$(VERSION),none)"
	@printf 'IMAGE_NAME    %s\n' "$(IMAGE_NAME)"
	@printf 'GOPROXY       %s\n' "$(if $(IMAGE_GOPROXY),$(IMAGE_GOPROXY),Dockerfile default)"
	@printf 'release       %s:%s  %s:latest\n' \
	  "$(IMAGE_NAME)" "$(VERSION)" "$(IMAGE_NAME)"
	@printf 'release-baked %s:%s-baked  %s:baked\n' \
	  "$(IMAGE_NAME)" "$(VERSION)" "$(IMAGE_NAME)"

# Every push target goes through this: `git describe` on a repo with no tags is
# empty, and an empty version would silently publish `:-amd64` and clobber
# `:latest` with it.
check-version:
	@test -n "$(VERSION)" || { \
	  printf 'no git tag found — this repo'\''s tag names the release.\n'; \
	  printf '  make tag VERSION=v0.1.0     (annotate + push)\n'; \
	  printf '  make release VERSION=v0.1.0 (or pass one explicitly)\n'; \
	  exit 1; }

# arm64 on an amd64 host is emulated, and the emulators are not registered by
# default — without them buildx fails with "exec format error" several minutes in.
check-arm64:
	@docker buildx inspect $(BUILDER) 2>/dev/null | grep -q 'linux/arm64' || { \
	  printf 'this builder cannot produce linux/arm64.\n'; \
	  printf '  make binfmt    register the QEMU emulators\n'; \
	  printf '  make builder   create a docker-container builder that can use them\n'; \
	  exit 1; }

login: ## docker login (needed once before any push target)
	docker login

builder: ## Create/select a docker-container builder that can do multi-arch
	docker buildx inspect flomorphic >/dev/null 2>&1 \
	  || docker buildx create --name flomorphic --driver docker-container --bootstrap
	docker buildx use flomorphic

binfmt: ## Register QEMU emulators so this host can build arm64
	docker run --privileged --rm tonistiigi/binfmt --install arm64,amd64

# ── local ─────────────────────────────────────────────────────────────────────

build: ## Build the self-building image for this host, as LOCAL_IMAGE
	$(BUILDX) $(SRC_NO_CACHE) $(BUILD_ARGS) \
		-f $(SRC_DOCKERFILE) \
		-t $(LOCAL_IMAGE) --load .

build-baked: ## Build the prebuilt image for this host, as LOCAL_IMAGE-baked
	$(BUILDX) $(BAKED_NO_CACHE) $(BUILD_ARGS) \
		-f $(BAKED_DOCKERFILE) \
		-t $(LOCAL_IMAGE)-baked --load .

run: ## Run the local image on PORT, standalone (CRUD-only, no platform)
	@printf 'starting %s on http://localhost:%s — no INFLOW_INFRA_API, so Run is inert\n' \
	  "$(LOCAL_IMAGE)" "$(PORT)"
	docker run --rm -d --name flomorphic-local \
		-p $(PORT):80 -e PLUGINS_ENABLED=0 $(LOCAL_IMAGE)
	@printf 'follow it with: docker logs -f flomorphic-local\n'

stop: ## Stop the container `run` started
	-docker rm -f flomorphic-local

# ── the self-building image: the published default ────────────────────────────
#
# Built per arch and pushed under its own tag, then assembled into one manifest —
# the same shape as the infra Makefile, so a failed arch can be retried on its
# own without redoing the other.

docker-amd64: check-version ## Build+load the amd64 tag for this version
	$(BUILDX) $(SRC_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/amd64 -f $(SRC_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-amd64 --load .

docker-arm64: check-version check-arm64 ## Build+load the arm64 tag for this version
	$(BUILDX) $(SRC_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/arm64 -f $(SRC_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-arm64 --load .

docker: docker-amd64 docker-arm64 ## Build both arches locally, push nothing

docker-push-amd64: check-version
	$(BUILDX) $(SRC_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/amd64 -f $(SRC_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-amd64 --push .

docker-push-arm64: check-version check-arm64
	$(BUILDX) $(SRC_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/arm64 -f $(SRC_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-arm64 --push .

docker-push: docker-push-amd64 docker-push-arm64 ## Push both per-arch tags

# No rebuild — this only assembles the two pushed per-arch tags into the
# multi-platform manifests that users actually pull.
push-latest: docker-push
	docker buildx imagetools create \
		-t $(IMAGE_NAME):latest \
		-t $(IMAGE_NAME):$(VERSION) \
		$(IMAGE_NAME):$(VERSION)-amd64 \
		$(IMAGE_NAME):$(VERSION)-arm64

release: push-latest ## Publish VERSION + latest (multi-arch)
	@printf '\npublished %s:%s and %s:latest\n' \
	  "$(IMAGE_NAME)" "$(VERSION)" "$(IMAGE_NAME)"
	@$(MAKE) --no-print-directory inspect

# ── the baked image: opt-in ───────────────────────────────────────────────────
#
# `baked-arm64` on an amd64 host compiles the cgo API, the plugin nodes and the
# canvas under emulation. It works; budget half an hour or run it on an arm64
# machine and let `push-baked` merge the manifests.

baked-amd64: check-version ## Build+load the baked amd64 tag
	$(BUILDX) $(BAKED_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/amd64 -f $(BAKED_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-baked-amd64 --load .

baked-arm64: check-version check-arm64 ## Build+load the baked arm64 tag (slow, emulated)
	$(BUILDX) $(BAKED_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/arm64 -f $(BAKED_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-baked-arm64 --load .

baked: baked-amd64 baked-arm64

baked-push-amd64: check-version
	$(BUILDX) $(BAKED_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/amd64 -f $(BAKED_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-baked-amd64 --push .

baked-push-arm64: check-version check-arm64
	$(BUILDX) $(BAKED_NO_CACHE) $(BUILD_ARGS) \
		--platform linux/arm64 -f $(BAKED_DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-baked-arm64 --push .

baked-push: baked-push-amd64 baked-push-arm64

push-baked: baked-push
	docker buildx imagetools create \
		-t $(IMAGE_NAME):baked \
		-t $(IMAGE_NAME):$(VERSION)-baked \
		$(IMAGE_NAME):$(VERSION)-baked-amd64 \
		$(IMAGE_NAME):$(VERSION)-baked-arm64

release-baked: push-baked ## Publish VERSION-baked + baked (multi-arch)
	@printf '\npublished %s:%s-baked and %s:baked\n' \
	  "$(IMAGE_NAME)" "$(VERSION)" "$(IMAGE_NAME)"

# The baked image is the fast-install default for everyone, so `latest` must BE
# the baked image. This publishes it and, in the same run, repoints :latest and
# :VERSION at that exact manifest — no rebuild, just manifest assembly from the
# per-arch tags push-baked already pushed. One command, no separate retag step.
release-baked-latest: push-baked ## Publish baked AND repoint :latest + :VERSION at it
	docker buildx imagetools create \
		-t $(IMAGE_NAME):latest \
		-t $(IMAGE_NAME):$(VERSION) \
		$(IMAGE_NAME):$(VERSION)-baked-amd64 \
		$(IMAGE_NAME):$(VERSION)-baked-arm64
	@printf '\npublished %s: :%s-baked :baked :%s :latest — all the baked hybrid (multi-arch)\n' \
	  "$(IMAGE_NAME)" "$(VERSION)" "$(VERSION)"
	@$(MAKE) --no-print-directory inspect

# ── release plumbing ──────────────────────────────────────────────────────────

# VERSION here is the tag being created, not the one `git describe` just found,
# so it has to come from the command line.
tag: ## Create and push the release tag: make tag VERSION=v0.2.0
	@test "$(origin VERSION)" = "command line" \
	  || { printf 'pass the new tag: make tag VERSION=v0.2.0\n'; exit 1; }
	git tag -a $(VERSION) -m "FloMorphic $(VERSION)"
	git push origin $(VERSION)

inspect: check-version ## Show what is published for this version
	-docker buildx imagetools inspect $(IMAGE_NAME):$(VERSION)
	-docker buildx imagetools inspect $(IMAGE_NAME):latest

clean: ## Drop the local per-arch and :local tags
	-docker rmi $(LOCAL_IMAGE) $(LOCAL_IMAGE)-baked 2>/dev/null
	-docker rmi $(IMAGE_NAME):$(VERSION)-amd64 $(IMAGE_NAME):$(VERSION)-arm64 2>/dev/null
	-docker rmi $(IMAGE_NAME):$(VERSION)-baked-amd64 $(IMAGE_NAME):$(VERSION)-baked-arm64 2>/dev/null
