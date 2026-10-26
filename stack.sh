#!/usr/bin/env bash
#
# Stack control for an install directory.
#
#   ./stack.sh up | down | restart | reset | destroy | pull | ps | logs
#
# install.sh writes one folder per stack into the install directory — platform/,
# flomorphic/, surfstat/, venapce/, inspector/ — each with its own
# docker-compose.yml and .env. Managing them by hand means cd-ing into every one
# of them, in the right order, for every start and stop. This does that for you.
#
# Run it from the install directory (or point INSTALL_DIR at it). Every command
# takes an optional list of stacks and defaults to all the ones it finds, in
# dependency order: the platform comes up first and goes down last.
#
#   ./stack.sh                      what is installed and what is running
#   ./stack.sh down                 stop everything, keep the data
#   ./stack.sh up                   start everything again
#   ./stack.sh restart flomorphic   just that one
#   ./stack.sh reset surfstat       throw surfstat's data away, start it fresh
#   ./stack.sh reset                a clean instance of everything
#   ./stack.sh logs flomorphic      follow one stack's logs
#
# Commands:
#   ps | status     one `docker compose ps` table per stack          (the default)
#   up              create inflow_net if missing, then `up -d`
#   down            `down` — containers go, data stays
#   restart         down, then up
#   pull            `pull` the images, then `up -d` whatever is running
#   reset           destroy, then up: a new instance with no old data
#   destroy         `down -v` AND delete the state directories, stay down
#   logs            `logs -f` for one stack
#
# reset and destroy are irreversible. They take the named volumes with them
# (`down -v`) and delete the bind-mounted state directories — platform/store,
# flomorphic/data, inspector/backend-data — which is where a `down -v` alone
# leaves old data behind. Those directories were written by root inside the
# container, so deleting them may ask for sudo.
#
# Env vars:
#   INSTALL_DIR   directory holding the stack folders (default: current directory)
#   ASSUME_YES    1 — don't ask before destroying data (default: 0)
#   DRY_RUN       1 — print every command instead of running it (default: 0)
#
# Flags:  -y | --yes   same as ASSUME_YES=1
#         -n | --dry-run   same as DRY_RUN=1
#
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$PWD}"
ASSUME_YES="${ASSUME_YES:-0}"
DRY_RUN="${DRY_RUN:-0}"

# Dependency order: the platform serves the products, and the products talk to
# FloMorphic's API, so this is also the order they have to start in. Stacks are
# stopped in reverse. Any other stack folder found in the install directory is
# appended to the end, alphabetically.
STACK_ORDER="platform inspector flomorphic venapce surfstat"

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

usage() {
  if [ -f "${BASH_SOURCE[0]:-}" ]; then sed -n '3,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  else printf 'see https://github.com/FloMorphic/getting-started#manage-the-stacks\n'; fi
}

# ── args ──────────────────────────────────────────────────────────────────────
CMD=""
STACKS=()
for arg in "$@"; do
  case "$arg" in
    -y|--yes)     ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           die "unknown option: $arg" ;;
    *)            if [ -z "$CMD" ]; then CMD="$arg"; else STACKS+=("$arg"); fi ;;
  esac
done
CMD="${CMD:-ps}"

# ── docker ────────────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || die "docker is not installed (or not on PATH)."
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  die "the Docker Compose v2 plugin is required (\`docker compose version\`)."
fi

[ -d "$INSTALL_DIR" ] || die "no such directory: $INSTALL_DIR"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"

# ── discovery ─────────────────────────────────────────────────────────────────
# A stack is any immediate subdirectory with a compose file in it, so this keeps
# working for a stack folder that does not exist yet (or one installed by hand).
is_stack() {
  [ -f "$INSTALL_DIR/$1/docker-compose.yml" ] || [ -f "$INSTALL_DIR/$1/compose.yaml" ]
}

all_stacks() {
  local name d
  for name in $STACK_ORDER; do
    is_stack "$name" && printf '%s\n' "$name"
  done
  shopt -s nullglob
  for d in "$INSTALL_DIR"/*/; do
    name="${d%/}"; name="${name##*/}"
    case " $STACK_ORDER " in *" $name "*) continue ;; esac
    is_stack "$name" && printf '%s\n' "$name"
  done
  shopt -u nullglob
}

# Sort the names given on the command line into the order above, so `up` and
# `down` are correct however they were typed.
selected() {
  local wanted=" $* " name
  if [ "$#" -eq 0 ]; then all_stacks; return; fi
  all_stacks | while read -r name; do
    case "$wanted" in *" $name "*) printf '%s\n' "$name" ;; esac
  done
}

reverse() { # <names...> -> the same names, last first
  local i
  for (( i=$#; i>0; i-- )); do printf '%s\n' "${!i}"; done
}

# ── running things ────────────────────────────────────────────────────────────
dc() { # <stack> <compose args...>
  local s="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    # stderr, so a dry-run never ends up inside a $(dc ...) capture
    printf '    %sdry-run:%s (cd %s && %s %s)\n' "$DIM" "$RST" "$s" "$DC" "$*" >&2
    return 0
  fi
  ( cd "$INSTALL_DIR/$s" && $DC "$@" )
}

# `set -e` would abandon the remaining stacks the moment one compose call fails.
# That is right for `up` (what follows depends on it) and wrong for `down`, `ps`
# and `destroy`, which should do as much as they can and report at the end.
FAILED=""
try_dc() { # <stack> <compose args...>
  local s="$1"
  if dc "$@"; then return 0; fi
  warn "$s: \`$DC ${*:2}\` failed — moving on"
  FAILED="$FAILED $s"
  return 1
}

report_failures() {
  [ -n "$FAILED" ] || return 0
  printf '\n'
  warn "these stacks reported an error:$FAILED"
  warn "a missing .env is the usual cause — check it, then re-run."
  exit 1
}

confirm() { # <question> -> 0 = yes
  local reply
  [ "$ASSUME_YES" = "1" ] && return 0
  # Read from the terminal, not stdin, so this still asks when the script is
  # piped something. /dev/tty can exist and still not be attached (cron, CI).
  ( exec 3<>/dev/tty ) 2>/dev/null \
    || die "no terminal to confirm on — re-run with --yes to destroy without asking."
  exec 3<>/dev/tty
  printf '\n    %s%s%s [y/N] ' "$B" "$1" "$RST" >&3
  read -r reply <&3 || reply=""
  exec 3>&-
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

ensure_net() {
  # Every stack declares inflow_net as external, so it has to exist before the
  # first `up`. The platform stack's installer creates it; this covers a reset
  # that removed it, or a product stack brought up on its own.
  if docker network inspect inflow_net >/dev/null 2>&1; then return 0; fi
  if [ "$DRY_RUN" = "1" ]; then info "${DIM}dry-run:${RST} docker network create inflow_net"; return 0; fi
  docker network create inflow_net >/dev/null
  ok "created the shared network inflow_net"
}

# Host directories a stack bind-mounts for its state — `./store:/data` and the
# like. `down -v` does not touch these, so a reset has to delete them by hand,
# and they are read out of the compose file rather than hardcoded here.
state_dirs() { # <stack>
  local f="$INSTALL_DIR/$1/docker-compose.yml" p
  [ -f "$f" ] || f="$INSTALL_DIR/$1/compose.yaml"
  grep -oE '^[[:space:]]*-[[:space:]]*\./[A-Za-z0-9._-]+:' "$f" 2>/dev/null \
    | sed -E 's#^[[:space:]]*-[[:space:]]*\./##; s#:$##' | sort -u \
    | while read -r p; do
        [ -d "$INSTALL_DIR/$1/$p" ] && printf '%s\n' "$p"
      done
}

purge_state() { # <stack>
  local s="$1" p target
  while read -r p; do
    [ -n "$p" ] || continue
    target="$INSTALL_DIR/$s/$p"
    if [ "$DRY_RUN" = "1" ]; then info "${DIM}dry-run:${RST} rm -rf $s/$p"; continue; fi
    # Written by root inside the container, so an unprivileged rm can fail here.
    if rm -rf "$target" 2>/dev/null; then
      ok "deleted $s/$p"
    elif command -v sudo >/dev/null 2>&1; then
      warn "$s/$p is owned by root (the container wrote it) — deleting it with sudo"
      if sudo rm -rf "$target"; then ok "deleted $s/$p"
      else die "could not delete $target, even with sudo."; fi
    else
      die "could not delete $target — remove it as root, then re-run."
    fi
  done < <(state_dirs "$s")
}

# ── commands ──────────────────────────────────────────────────────────────────
cmd_ps() {
  local s
  info "install directory    $INSTALL_DIR"
  docker network inspect inflow_net >/dev/null 2>&1 \
    && info "shared network       inflow_net" \
    || warn "shared network       inflow_net is missing — \`$0 up\` creates it"
  for s in "$@"; do
    step "$s"
    try_dc "$s" ps || true
  done
  report_failures
}

cmd_up() {
  local s
  ensure_net
  for s in "$@"; do
    step "starting $s"
    dc "$s" up -d
  done
  printf '\n'
  ok "up: $*"
}

cmd_down() {
  local s
  for s in $(reverse "$@"); do
    step "stopping $s"
    try_dc "$s" down || true
  done
  printf '\n'
  report_failures
  ok "down: $* ${DIM}(data kept)${RST}"
}

cmd_pull() {
  local s
  for s in "$@"; do
    step "pulling $s"
    try_dc "$s" pull || continue
    # Only touches what is already running: a pull should not start a stack the
    # user had deliberately stopped.
    if [ -n "$(dc "$s" ps -q 2>/dev/null)" ]; then
      dc "$s" up -d
      ok "$s restarted on the new image"
    else
      info "$s is not running — start it with \`$0 up $s\`"
    fi
  done
  report_failures
}

cmd_destroy() {
  local s p had=0
  step "This destroys data"
  for s in "$@"; do
    info "$s"
    info "  ${DIM}docker compose down -v${RST}  (its named volumes go too)"
    while read -r p; do
      [ -n "$p" ] || continue
      info "  ${YLW}delete${RST} $s/$p"
      had=1
    done < <(state_dirs "$s")
  done
  [ "$had" = "1" ] || info "${DIM}(no bind-mounted state directories — volumes only)${RST}"
  case " $* " in
    *" platform "*)
      # The secret lives in platform/.env, not in the store, so a destroyed
      # platform comes back with the same API Secret Key — unless that line is
      # empty, in which case Infra mints a new one and every other stack's .env
      # is then out of date.
      if ! grep -qE '^API_JWT_SECRET=.+' "$INSTALL_DIR/platform/.env" 2>/dev/null; then
        warn "platform/.env has no API_JWT_SECRET — Infra will mint a new API Secret Key"
        warn "and the other stacks' .env files will have to be updated to match."
      fi ;;
  esac
  confirm "Destroy the data of: $* ?" || die "nothing was changed."
  for s in $(reverse "$@"); do
    step "destroying $s"
    # Only purge once the containers and volumes are actually gone, so a stack
    # compose could not read keeps its data instead of losing half of it.
    try_dc "$s" down -v --remove-orphans && purge_state "$s"
  done
  report_failures
}

cmd_logs() {
  local s="${1:-}"
  [ "$#" -le 1 ] || die "logs follows one stack at a time: $0 logs <stack>"
  if [ -z "$s" ]; then
    s="$(all_stacks)"
    case "$s" in
      *$'\n'*) die "which stack? $0 logs <$(all_stacks | tr '\n' '|' | sed 's/|$//')>" ;;
      '')      die "no stacks found under $INSTALL_DIR" ;;
    esac
  fi
  dc "$s" logs -f --tail 200
}

# ── dispatch ──────────────────────────────────────────────────────────────────
# Checked here rather than inside selected(), which runs in a subshell.
for name in "${STACKS[@]+${STACKS[@]}}"; do
  is_stack "$name" || die "$name: no compose file under $INSTALL_DIR/$name — installed: $(all_stacks | tr '\n' ' ')"
done

mapfile -t TARGETS < <(selected "${STACKS[@]+${STACKS[@]}}")
if [ "${#TARGETS[@]}" -eq 0 ] && [ "$CMD" != "logs" ]; then
  die "no stacks found under $INSTALL_DIR — run install.sh there first, or set INSTALL_DIR."
fi

case "$CMD" in
  ps|status) cmd_ps      "${TARGETS[@]}" ;;
  up|start)  cmd_up      "${TARGETS[@]}" ;;
  down|stop) cmd_down    "${TARGETS[@]}" ;;
  restart)   cmd_down    "${TARGETS[@]}"; cmd_up "${TARGETS[@]}" ;;
  pull)      cmd_pull    "${TARGETS[@]}" ;;
  destroy)   cmd_destroy "${TARGETS[@]}" ;;
  reset)     cmd_destroy "${TARGETS[@]}"; cmd_up "${TARGETS[@]}" ;;
  logs)      cmd_logs    "${STACKS[@]+${STACKS[@]}}" ;;
  help)      usage ;;
  *)         die "unknown command: $CMD (try $0 --help)" ;;
esac
