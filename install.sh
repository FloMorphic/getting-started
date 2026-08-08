#!/usr/bin/env bash
#
# FloMorphic one-liner installer.
#
#   curl -fsSL https://raw.githubusercontent.com/FloMorphic/getting-started/main/install.sh | bash
#
# Stands up FloMorphic — the canvas, its API and the builtin plugin nodes — on
# top of the Inflowenger platform (Infra + Fractal), and installs that platform
# too if you don't already have one. Everything lands on the shared `inflow_net`
# Docker network, and the compose stacks are written into an install directory
# so you can manage them by hand afterwards.
#
# What it asks (all of it can be driven by the env vars below instead):
#   1. install directory
#   2. platform: use the one that is already running, or install a new one
#      (delegated to the Inflowenger installer, so there is one source of truth)
#   3. ports (behind an advanced-options prompt)
#
# It pulls the published, baked image (api + canvas compiled in). Building an
# image is a maintainer job, not an install-time one — see `make build` /
# `make release` and docs/development.md.
#
# It works both interactively (prompts read from /dev/tty even when piped through
# curl) and non-interactively (drive it entirely with the env vars below).
#
# Env vars (all optional — prompted for when a TTY is available, else defaulted):
#   FLOMORPHIC_DIR      install directory                    (default: current directory)
#   PLATFORM_MODE       existing | new                       (default: detected, else prompted)
#   INFLOW_INFRA_API    Infra REST API base URL              (default: http://inflow-infra:8022)
#   API_JWT_SECRET      Infra API Secret Key / shared secret (default: generated for a new platform)
#   FRACTAL_TAGS        tags for a new platform's Fractal    (default: default)
#   FRACTAL_NAME        container name for that Fractal      (default: fractal-1)
#   INSTALL_INSPECTOR   1/0 — inspector panel with a new platform (default: 0)
#                       Not prompted for: the inspector is an Inflowenger
#                       developer panel, not part of a FloMorphic install. Set
#                       INSTALL_INSPECTOR=1 to opt in.
#   IMAGE_NS            Docker Hub namespace                 (default: mehdishokohi)
#   IMAGE_TAG           tag for the pulled image             (default: latest)
#   FLOMORPHIC_IMAGE    full image ref, overrides NS/TAG     (default: $IMAGE_NS/flomorphic:$IMAGE_TAG)
#   FLOMORPHIC_PORT     host port for the canvas             (default: 8088)
#   FLOMORPHIC_API_PORT host port for the API                (default: 8026)
#   PLUGINS_ENABLED     1/0 — run the builtin plugin nodes   (default: 1)
#                       Not prompted for: the builtin nodes are part of the
#                       product, not an add-on. 0 is an escape hatch for running
#                       the canvas + API alone (see `make run`).
#   REPO_RAW / REPO_REF raw base URL + ref the compose file is fetched from
#   PLATFORM_INSTALLER  URL of the Inflowenger platform installer
#   ASSUME_YES          1 — accept all defaults, no prompts  (default: 0)
#
# Flags:  --yes  same as ASSUME_YES=1
#
set -euo pipefail

# ── config / defaults ─────────────────────────────────────────────────────────
FLOMORPHIC_DIR="${FLOMORPHIC_DIR:-$PWD}"
PLATFORM_MODE="${PLATFORM_MODE:-}"
INFLOW_INFRA_API="${INFLOW_INFRA_API:-}"
API_JWT_SECRET="${API_JWT_SECRET:-}"
FRACTAL_TAGS="${FRACTAL_TAGS:-default}"
FRACTAL_NAME="${FRACTAL_NAME:-fractal-1}"
INSTALL_INSPECTOR="${INSTALL_INSPECTOR:-0}"
IMAGE_NS="${IMAGE_NS:-mehdishokohi}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FLOMORPHIC_IMAGE="${FLOMORPHIC_IMAGE:-}"
FLOMORPHIC_PORT="${FLOMORPHIC_PORT:-8088}"
FLOMORPHIC_API_PORT="${FLOMORPHIC_API_PORT:-8026}"
PLUGINS_ENABLED="${PLUGINS_ENABLED:-1}"
AUTH_ENABLED="${AUTH_ENABLED:-false}"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/FloMorphic/getting-started}"
REPO_REF="${REPO_REF:-main}"
PLATFORM_INSTALLER="${PLATFORM_INSTALLER:-https://raw.githubusercontent.com/Inflowenger/getting-started/main/install.sh}"
ASSUME_YES="${ASSUME_YES:-0}"

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help)
      # Only possible when running from a file; `curl | bash` has no source to read.
      if [ -f "${BASH_SOURCE[0]:-}" ]; then sed -n '3,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      else printf 'see https://github.com/FloMorphic/getting-started#install\n'; fi
      exit 0 ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# Where this script lives, when it lives anywhere: run from a clone, the repo's
# own compose file is used as-is; piped through curl, it is fetched from
# REPO_RAW/REPO_REF instead.
SCRIPT_DIR=""
case "${BASH_SOURCE[0]:-}" in
  ''|bash|-|/dev/fd/*|/proc/self/fd/*) ;;
  *) SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ;;
esac

# ── pretty output ─────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  B=''; DIM=''; GRN=''; YLW=''; RED=''; CYN=''; RST=''
fi
step() { printf '\n%s==>%s %s%s%s\n' "$CYN" "$RST" "$B" "$*" "$RST"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '    %s!%s %s\n' "$YLW" "$RST" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

# ── interactive helpers (read from /dev/tty so `curl | bash` still prompts) ────
have_tty() { [ "$ASSUME_YES" != "1" ] && [ -e /dev/tty ]; }

ask() { # <prompt> <default> -> echoes answer
  local prompt="$1" def="${2:-}" reply
  if ! have_tty; then printf '%s' "$def"; return; fi
  if [ -n "$def" ]; then printf '%s%s%s [%s]: ' "$B" "$prompt" "$RST" "$def" >/dev/tty
  else printf '%s%s%s: ' "$B" "$prompt" "$RST" >/dev/tty; fi
  IFS= read -r reply </dev/tty || reply=""
  printf '%s' "${reply:-$def}"
}

# Echoed rather than hidden: the key is printed in the summary and written to
# flomorphic/.env anyway, and a silent prompt gives no feedback that a pasted
# value actually landed.
ask_secret() { # <prompt> -> echoes answer
  local prompt="$1" reply
  if ! have_tty; then printf ''; return; fi
  printf '%s%s%s: ' "$B" "$prompt" "$RST" >/dev/tty
  IFS= read -r reply </dev/tty || reply=""
  printf '%s' "$reply"
}

confirm() { # <prompt> <default y|n> -> exit status
  local prompt="$1" def="${2:-n}" reply hint="[y/N]"
  [ "$def" = y ] && hint="[Y/n]"
  if ! have_tty; then [ "$def" = y ]; return; fi
  printf '%s%s%s %s ' "$B" "$prompt" "$RST" "$hint" >/dev/tty
  IFS= read -r reply </dev/tty || reply=""
  reply="${reply:-$def}"
  case "$reply" in [Yy]*) return 0;; *) return 1;; esac
}

gen_secret() {
  # 64-char alphanumeric key, used verbatim for every secret that must match:
  # Infra's API_JWT_SECRET and FloMorphic's INFLOW_INFRA_JWT_SECRET.
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c 64
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64
  fi
}

DL=""
fetch() { # <url> <dest>
  case "$DL" in
    curl) curl -fsSL "$1" -o "$2" ;;
    wget) wget -qO "$2" "$1" ;;
  esac || die "failed to download $1"
}

# ── prerequisites ─────────────────────────────────────────────────────────────
step "Checking prerequisites"
command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH."
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  die "the Docker Compose v2 plugin is required (\`docker compose version\`)."
fi
docker info >/dev/null 2>&1 || die "cannot talk to the Docker daemon — is it running / do you have permission?"
if command -v curl >/dev/null 2>&1; then DL=curl
elif command -v wget >/dev/null 2>&1; then DL=wget
else die "need curl or wget to download the compose files."; fi
ok "docker + compose available ($DC); downloader: $DL"

# ── banner ────────────────────────────────────────────────────────────────────
printf '\n%s  FloMorphic installer%s\n' "$B" "$RST"
printf '%s  canvas + API + builtin plugin nodes, on the Inflowenger runtime%s\n' "$DIM" "$RST"

# ── 1. where ──────────────────────────────────────────────────────────────────
step "Configuration"
FLOMORPHIC_DIR="$(ask "Install directory" "$FLOMORPHIC_DIR")"
mkdir -p "$FLOMORPHIC_DIR"
FLOMORPHIC_DIR="$(cd "$FLOMORPHIC_DIR" && pwd)"

# ── 2. the platform ───────────────────────────────────────────────────────────
#
# FloMorphic is a product ON the runtime, not a replacement for it: without Infra
# there is no engine to run a flow and no account to credential a plugin against.
if [ -z "$PLATFORM_MODE" ]; then
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'inflow-infra'; then
    ok "found a running Infra container (inflow-infra)"
    if confirm "Use the Inflowenger platform that is already running?" y; then
      PLATFORM_MODE=existing
    else
      PLATFORM_MODE=new
    fi
  else
    info "No running Infra found. FloMorphic needs the Inflowenger platform (Infra + a Fractal)."
    if confirm "Install a new platform now?" y; then PLATFORM_MODE=new; else PLATFORM_MODE=existing; fi
  fi
fi

# Pre-fill the secret from a platform/.env written by a previous run, so the
# common case (platform installed here) needs no copy-paste.
if [ -z "$API_JWT_SECRET" ] && [ -f "$FLOMORPHIC_DIR/platform/.env" ]; then
  PRIOR_SECRET="$(grep -E '^API_JWT_SECRET=' "$FLOMORPHIC_DIR/platform/.env" | head -n1 | cut -d= -f2- || true)"
  if [ -n "${PRIOR_SECRET:-}" ]; then
    API_JWT_SECRET="$PRIOR_SECRET"
    ok "read the API Secret Key from $FLOMORPHIC_DIR/platform/.env"
  fi
fi

if [ "$PLATFORM_MODE" = new ]; then
  step "Installing the Inflowenger platform (Infra + Fractal)"
  info "Delegated to the Inflowenger installer so the platform stack has one source of truth:"
  info "  $PLATFORM_INSTALLER"

  if [ -z "$API_JWT_SECRET" ] && have_tty; then
    info "Infra needs an API Secret Key. FloMorphic shares it. Leave blank to auto-generate."
    info "${DIM}Paste with Ctrl+Shift+V (or right-click / Cmd+V) — Ctrl+V is not paste in a terminal.${RST}"
    API_JWT_SECRET="$(ask_secret "API Secret Key (blank = generate)")"
  fi
  if [ -z "$API_JWT_SECRET" ]; then
    API_JWT_SECRET="$(gen_secret)"
    ok "Generated an API Secret Key."
  fi

  FRACTAL_TAGS="$(ask "Fractal tags (comma-separated)" "$FRACTAL_TAGS")"
  FRACTAL_NAME="$(ask "Fractal container name" "$FRACTAL_NAME")"
  # The inflow-inspector panel is an Inflowenger developer tool, not part of a
  # FloMorphic install, so it is not prompted for here — off unless the caller
  # sets INSTALL_INSPECTOR=1.

  PLATFORM_SH="$(mktemp)"
  fetch "$PLATFORM_INSTALLER" "$PLATFORM_SH"
  INFLOW_DIR="$FLOMORPHIC_DIR" \
  API_JWT_SECRET="$API_JWT_SECRET" \
  FRACTAL_TAGS="$FRACTAL_TAGS" \
  FRACTAL_NAME="$FRACTAL_NAME" \
  INSTALL_INSPECTOR="$INSTALL_INSPECTOR" \
  ASSUME_YES=1 \
    bash "$PLATFORM_SH" || die "the platform installer failed — fix that first, then re-run this script."
  rm -f "$PLATFORM_SH"

  # Installed here, so FloMorphic reaches it by container name on inflow_net.
  INFLOW_INFRA_API="${INFLOW_INFRA_API:-http://inflow-infra:8022}"
  ok "platform installed under $FLOMORPHIC_DIR/platform"
else
  step "Using an existing Inflowenger platform"
  INFLOW_INFRA_API="$(ask "Infra API base URL (as seen FROM the container)" "${INFLOW_INFRA_API:-http://inflow-infra:8022}")"
  if [ -z "$API_JWT_SECRET" ]; then
    info "FloMorphic authenticates to Infra with its API Secret Key (Infra prints it on"
    info "first boot: \"API Secret Key is : ...\"; it is API_JWT_SECRET in platform/.env)."
    API_JWT_SECRET="$(ask_secret "API Secret Key")"
  fi
  if [ -z "$API_JWT_SECRET" ]; then
    warn "No API Secret Key given — FloMorphic will start in CRUD-only mode:"
    warn "workflows can be designed and saved, but Run and the plugin nodes stay dark."
    warn "Add INFLOW_INFRA_JWT_SECRET to flomorphic/.env later and \`$DC up -d\` again."
  fi
fi

# ── 3. the image ──────────────────────────────────────────────────────────────
# Always the published, baked image. Building is a maintainer job (`make build` /
# `make release`), not an install-time choice — FLOMORPHIC_IMAGE overrides the ref.
FLOMORPHIC_IMAGE="${FLOMORPHIC_IMAGE:-$IMAGE_NS/flomorphic:$IMAGE_TAG}"

if have_tty && confirm "Set advanced options (ports)?" n; then
  FLOMORPHIC_PORT="$(ask "Host port for the canvas" "$FLOMORPHIC_PORT")"
  FLOMORPHIC_API_PORT="$(ask "Host port for the API" "$FLOMORPHIC_API_PORT")"
fi

# The builtin plugin nodes are not asked about. They are what the canvas's stock
# nodes RUN as — the published image bakes them in per-arch and credentials them
# against the API it just started. Turning them off leaves a canvas whose nodes
# cannot execute, which is not an install-time choice anyone can make usefully.
# PLUGINS_ENABLED=0 remains for the one case that wants it — canvas + API with no
# platform, as in `make run`.

# ── write the stack ───────────────────────────────────────────────────────────
step "Writing the FloMorphic stack -> $FLOMORPHIC_DIR/flomorphic"
mkdir -p "$FLOMORPHIC_DIR/flomorphic/data"

# The compose file is a single source of truth — taken from this checkout when
# there is one, fetched from the repo otherwise. Every image ref and port in it
# is overridden by the .env written below.
COMPOSE_DST="$FLOMORPHIC_DIR/flomorphic/docker-compose.yml"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/flomorphic/docker-compose.yml" ]; then
  # Installing into the checkout itself: source and destination are one file.
  [ "$SCRIPT_DIR/flomorphic/docker-compose.yml" = "$COMPOSE_DST" ] || \
    cp "$SCRIPT_DIR/flomorphic/docker-compose.yml" "$COMPOSE_DST"
  info "compose file taken from this checkout"
else
  fetch "$REPO_RAW/$REPO_REF/flomorphic/docker-compose.yml" "$COMPOSE_DST"
fi

# .env is rewritten from the answers above; keep the previous one so a hand-edit
# is recoverable.
if [ -f "$FLOMORPHIC_DIR/flomorphic/.env" ]; then
  cp "$FLOMORPHIC_DIR/flomorphic/.env" "$FLOMORPHIC_DIR/flomorphic/.env.bak"
  warn "existing .env backed up to flomorphic/.env.bak"
fi

{
  printf 'FLOMORPHIC_IMAGE=%s\n'        "$FLOMORPHIC_IMAGE"
  printf 'INFLOW_INFRA_API=%s\n'        "$INFLOW_INFRA_API"
  printf 'INFLOW_INFRA_JWT_SECRET=%s\n' "$API_JWT_SECRET"
  printf 'AUTH_ENABLED=%s\n'            "$AUTH_ENABLED"
  printf 'API_JWT_SECRET=\n'
  printf 'DB_SOURCE=/data/flomorphic.db\n'
  printf 'FLOMORPHIC_PORT=%s\n'         "$FLOMORPHIC_PORT"
  printf 'FLOMORPHIC_API_PORT=%s\n'     "$FLOMORPHIC_API_PORT"
  printf 'PLUGINS_ENABLED=%s\n'         "$PLUGINS_ENABLED"
  printf 'PLUGINS=\n'
} > "$FLOMORPHIC_DIR/flomorphic/.env"
chmod 600 "$FLOMORPHIC_DIR/flomorphic/.env"
ok "flomorphic/docker-compose.yml + .env written"

# The compose stack declares inflow_net as external; the platform installer
# creates it, but a pre-existing platform on another host may not have it here.
step "Ensuring the shared network (inflow_net) exists"
if docker network inspect inflow_net >/dev/null 2>&1; then
  ok "network inflow_net already exists"
else
  docker network create inflow_net >/dev/null
  ok "created network inflow_net"
fi

# ── start ─────────────────────────────────────────────────────────────────────
step "Starting FloMorphic"
( cd "$FLOMORPHIC_DIR/flomorphic" && $DC pull --quiet 2>/dev/null || true )
info "the published image is fully baked (api, canvas AND plugin nodes compiled"
info "in per-arch), so it starts fast — nothing is cloned or built at run time."
if ! ( cd "$FLOMORPHIC_DIR/flomorphic" && $DC up -d ); then
  printf '\n'
  die "\`$DC up -d\` failed — see the error above."
fi

info "Waiting for the canvas to answer on http://localhost:$FLOMORPHIC_PORT ..."
ready=0
for _ in $(seq 1 180); do
  if curl -fsS "http://localhost:$FLOMORPHIC_PORT/healthz" >/dev/null 2>&1; then ready=1; break; fi
  # Fail fast if the container gave up instead of waiting out the whole timeout.
  if ! docker ps --format '{{.Names}}' | grep -qx 'flomorphic'; then
    warn "the flomorphic container is not running — check its logs:"
    info "  (cd $FLOMORPHIC_DIR/flomorphic && $DC logs --tail 50)"
    break
  fi
  sleep 5
done
if [ "$ready" = "1" ]; then
  ok "FloMorphic is up"
else
  warn "not ready yet — give it a moment and follow it with:"
  info "  (cd $FLOMORPHIC_DIR/flomorphic && $DC logs -f)"
fi

# ── summary ───────────────────────────────────────────────────────────────────
step "Done"
printf '\n%s  FloMorphic%s\n' "$B" "$RST"
info "Canvas               http://localhost:$FLOMORPHIC_PORT"
info "API (direct)         http://localhost:$FLOMORPHIC_API_PORT   ${DIM}(the canvas uses /api behind the canvas port)${RST}"
# Deliberately not a list: the image bakes whatever plugin the repo carries (any
# top-level folder with a go.mod), so a name spelled out here goes stale the next
# time one is added.
if [ "$PLUGINS_ENABLED" = "1" ]; then
  info "Plugin nodes         baked into the image per-arch, started inside the container"
else
  info "Plugin nodes         disabled (PLUGINS_ENABLED=0) — the canvas's nodes will not execute"
fi

printf '\n%s  Platform%s\n' "$B" "$RST"
info "Infra API            $INFLOW_INFRA_API"
if [ "$PLATFORM_MODE" = new ]; then
  info "Infra portal         http://localhost:8022"
  info "Fractal              $FRACTAL_NAME  (tags: $FRACTAL_TAGS)"
fi
if [ -n "$API_JWT_SECRET" ]; then
  printf '\n%s  API Secret Key%s  %s(save this — it is your admin credential)%s\n' "$B" "$RST" "$DIM" "$RST"
  printf '    %s%s%s\n' "$YLW" "$API_JWT_SECRET" "$RST"
fi

printf '\n%s  Files & management%s\n' "$B" "$RST"
info "Stacks live in       $FLOMORPHIC_DIR"
info "Database             $FLOMORPHIC_DIR/flomorphic/data/flomorphic.db"
info "Follow the boot      (cd $FLOMORPHIC_DIR/flomorphic && $DC logs -f)"
info "Stop FloMorphic      (cd $FLOMORPHIC_DIR/flomorphic && $DC down)"
info "Update the image     edit FLOMORPHIC_IMAGE in flomorphic/.env, then $DC pull && $DC up -d"
[ "$PLATFORM_MODE" = new ] && info "Stop the platform    (cd $FLOMORPHIC_DIR/platform && $DC down)"
printf '\n'
