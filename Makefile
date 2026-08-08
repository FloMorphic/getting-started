# FloMorphic — build and publish the product image.
#
# One image, `mehdishokohi/flomorphic`: the canvas, the API and the builtin
# plugin nodes behind a single nginx. Why they share a container rather than
# three is docker/Dockerfile.flomorphic's header; the short version is that the
# plugin nodes cannot start until the API has minted their NATS credential, so
# the entrypoint discovers and runs them itself. Nothing here publishes a
# separate api/wapp image.
#
# The image is BAKED: morph-api and the canvas are compiled at image-build time,
# so a container starts in seconds and needs no toolchain or network to serve.
# The plugin nodes are the one exception — small pure-Go binaries the entrypoint
# builds at first container start (cached on a volume), so PLUGINS_REF stays
# swappable at run time without a new image. See docker/Dockerfile.flomorphic.
# There is no build-everything-at-container-start image: to build from source,
# clone the repos and `make build`.
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
# arm64 is genuinely per-arch (a cgo sqlite build); on an amd64 host it compiles
# under QEMU — slower, so budget for it or run `release` on an arm64 machine.

# The version every image is tagged with. Set it by hand for each release and
# bump it here. Not derived from git — `make docker` labels the images with
# exactly this string. Override for a one-off without editing the file:
#   make docker VERSION=v0.2.0
VERSION ?= v0.1.6
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

# Go module proxy. Passed as a build arg and carried into the runtime as
# ENV GOPROXY, so this value is both (a) what the image compiles api + canvas
# through and (b) what the entrypoint builds the plugin nodes through at first
# start (and again if PLUGINS_REF changes). Empty leaves the Dockerfile default
# (proxy.golang.org) in place.
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

# The build is a full cgo + pnpm compile, so it keeps its layer cache by default.
# Force a clean rebuild with NO_CACHE=--no-cache.
NO_CACHE ?=

# buildx builder to use. Empty = whatever `docker buildx` currently defaults to.
BUILDER ?=

# Local tag for `make build` / `make run` — never pushed.
LOCAL_IMAGE ?= flomorphic:local

# Host port for `make run`.
PORT ?= 8088

DOCKERFILE := docker/Dockerfile.flomorphic

BUILDX := docker buildx build $(if $(BUILDER),--builder $(BUILDER),)
# The refs the image clones during the build (api + canvas), and the ENV defaults
# the entrypoint clones the plugin nodes at when the container first starts (still
# overridable with `docker run -e` / the compose file).
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
	build run stop \
	docker-amd64 docker-arm64 docker \
	docker-push-amd64 docker-push-arm64 docker-push push-latest release \
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

# Guards every build/push target: an empty VERSION would tag images `:-amd64`
# and clobber `:latest`. VERSION is set by hand at the top of this file.
check-version:
	@test -n "$(VERSION)" || { \
	  printf 'VERSION is empty — set it at the top of the Makefile,\n'; \
	  printf 'or pass one: make docker VERSION=v0.2.0\n'; \
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

build: ## Build the image for this host, as LOCAL_IMAGE
	$(BUILDX) $(NO_CACHE) $(BUILD_ARGS) \
		-f $(DOCKERFILE) \
		-t $(LOCAL_IMAGE) --load .

run: ## Run the local image on PORT, standalone (CRUD-only, no platform)
	@printf 'starting %s on http://localhost:%s — no INFLOW_INFRA_API, so Run is inert\n' \
	  "$(LOCAL_IMAGE)" "$(PORT)"
	docker run --rm -d --name flomorphic-local \
		-p $(PORT):80 -e PLUGINS_ENABLED=0 $(LOCAL_IMAGE)
	@printf 'follow it with: docker logs -f flomorphic-local\n'

stop: ## Stop the container `run` started
	-docker rm -f flomorphic-local

# ── publish ───────────────────────────────────────────────────────────────────
#
# Built per arch and pushed under its own tag, then assembled into one manifest —
# so a failed arch can be retried on its own without redoing the other.

docker-amd64: check-version ## Build+load the amd64 tag for this version
	$(BUILDX) $(NO_CACHE) $(BUILD_ARGS) \
		--platform linux/amd64 -f $(DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-amd64 --load .

docker-arm64: check-version check-arm64 ## Build+load the arm64 tag (slow, emulated on amd64)
	$(BUILDX) $(NO_CACHE) $(BUILD_ARGS) \
		--platform linux/arm64 -f $(DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-arm64 --load .

docker: docker-amd64 docker-arm64 ## Build both arches locally, push nothing

docker-push-amd64: check-version
	$(BUILDX) $(NO_CACHE) $(BUILD_ARGS) \
		--platform linux/amd64 -f $(DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-amd64 --push .

docker-push-arm64: check-version check-arm64
	$(BUILDX) $(NO_CACHE) $(BUILD_ARGS) \
		--platform linux/arm64 -f $(DOCKERFILE) \
		-t $(IMAGE_NAME):$(VERSION)-arm64 --push .

docker-push: docker-push-amd64 docker-push-arm64 ## Push both per-arch tags

# No rebuild — this only assembles the two pushed per-arch tags into the
# multi-platform manifests that users actually pull.
push-latest: docker-push ## Assemble + push :latest and :VERSION (multi-arch)
	docker buildx imagetools create \
		-t $(IMAGE_NAME):latest \
		-t $(IMAGE_NAME):$(VERSION) \
		$(IMAGE_NAME):$(VERSION)-amd64 \
		$(IMAGE_NAME):$(VERSION)-arm64

release: push-latest ## Publish VERSION + latest (multi-arch)
	@printf '\npublished %s:%s and %s:latest\n' \
	  "$(IMAGE_NAME)" "$(VERSION)" "$(IMAGE_NAME)"
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
	-docker rmi $(LOCAL_IMAGE) 2>/dev/null
	-docker rmi $(IMAGE_NAME):$(VERSION)-amd64 $(IMAGE_NAME):$(VERSION)-arm64 2>/dev/null
