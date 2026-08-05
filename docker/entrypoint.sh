#!/bin/sh
#
# Entrypoint for the combined FloMorphic container: the canvas (morph-wapp), the
# API (morph-api) and the builtin plugin nodes (builtin-plugins) in one process
# tree, behind one nginx.
#
# morph-api and the canvas are already compiled into the image (see
# docker/Dockerfile.flomorphic); this script does not build them. The builtin
# plugin nodes are the one exception — small pure-Go binaries it clones and builds
# at first container start (cached on the /app/plugins volume), so PLUGINS_REF
# stays swappable without a new image.
#
# Startup order matters, and it is why the plugins are bootstrapped from here
# rather than from their own containers: a plugin needs a NATS credential on the
# builtin-plugins account, and the thing that mints it is flomorphic-api itself
# (POST /extension/plugin/cred). So the sequence is:
#
#   1. nginx up                       2. flomorphic-api up
#   3. wait for its /health           4. mint ONE multi-access credential
#   5. clone/build the plugin repo (once per repo@ref), resolve each PLUGIN_ID, run it
#   6. supervise: if any child dies, tear the rest down and exit non-zero so the
#      container restart policy gives a clean slate.
#
# Each plugin's PLUGIN_ID is *not* invented here: the builtin palette nodes carry
# hard-coded ids from morph-api's seed (repository/sqlite/seed/builtins.json), so
# a saved workflow keeps working across reinstalls. They are read back from the
# API (falling back to the seed file, then to a PLUGIN_ID_<NAME> override).
#
set -eu

# Escape hatch: `docker run … sh` / `… /bin/sh -c '…'` for debugging.
if [ "$#" -gt 0 ]; then exec "$@"; fi

# All three write to stdout on purpose. Docker merges the two streams into one
# log with no ordering guarantee between them, so sending warnings to stderr
# makes them surface out of sequence — a "skipping plugin nodes" warning landing
# after "FloMorphic is up" reads as if it happened later, when it happened first.
log()  { printf '[flomorphic] %s\n' "$*"; }
warn() { printf '[flomorphic] ! %s\n' "$*"; }
die()  { printf '[flomorphic] error: %s\n' "$*"; exit 1; }

# ── defaults ──────────────────────────────────────────────────────────────────
: "${SRC_DIR:=/src}"              # plugin checkout + Go module cache (a volume)
: "${APP_DIR:=/app}"
: "${WEB_ROOT:=/srv/www}"         # baked canvas
: "${PORT:=8025}"                 # flomorphic-api, container-internal
: "${WEB_PORT:=80}"               # nginx (canvas + /api + /ws)

: "${PLUGINS_ENABLED:=1}"
: "${PLUGINS_REPO:=https://github.com/FloMorphic/builtin-plugins.git}"
: "${PLUGINS_REF:=main}"
: "${PLUGINS:=}"                  # explicit folder list; empty = every folder
: "${PLUGIN_SRC_DIR:=${SRC_DIR}/plugins}"
: "${PLUGIN_BIN_DIR:=${APP_DIR}/plugins}"
: "${PLUGIN_CRED_NAME:=flomorphic-builtins}"
: "${PLUGIN_INFRA_URL:=}"         # host:port for NATS; derived when empty
: "${PLUGIN_NATS_PORT:=4222}"

: "${INFLOW_INFRA_API:=}"
: "${DB_SOURCE:=/data/flomorphic.db}"
# Go module proxy fallback for a blocked default CDN — see ensure_goproxy. Only
# used when GOPROXY is empty AND the default proves unreachable from here. The
# plugin nodes are the only thing compiled here (pure Go, CGO off), so the
# sqlite/sqlite-vec cgo flags the API needs live in the Dockerfile, not here.
: "${GOPROXY_MIRROR:=https://goproxy.cn,direct}"
export PORT DB_SOURCE

# ── child process bookkeeping ─────────────────────────────────────────────────
procs=""   # space-separated "<pid>:<name>"

track() { procs="$procs $1:$2"; }

stop_children() {
    for entry in $procs; do
        pid="${entry%%:*}"
        kill -TERM "$pid" 2>/dev/null || true
    done
    # Give them a moment to flush, then make sure nothing lingers.
    sleep 2
    for entry in $procs; do
        pid="${entry%%:*}"
        kill -KILL "$pid" 2>/dev/null || true
    done
}

on_signal() {
    log "shutting down"
    stop_children
    exit 0
}
trap on_signal INT TERM

# ── helpers ───────────────────────────────────────────────────────────────────
is_true() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *)             return 1 ;;
    esac
}

# The remote's default branch — `main` in one repo, `master` in the next.
git_default_ref() { # <repo>
    git ls-remote --symref "$1" HEAD 2>/dev/null \
      | sed -n 's|^ref: refs/heads/||p' | cut -f1 | head -n 1
}

git_sync() { # <repo> <ref> <dir>
    _repo="$1"; _ref="$2"; _dir="$3"
    # FloMorphic is a wrapped product: the version tag belongs to the image, not
    # to morph-api / morph-wapp / builtin-plugins, which are tracked at their
    # default branch and are NOT expected to carry a matching tag. That branch is
    # not spelled the same everywhere, and a ref that is not on the remote would
    # otherwise fail the clone several minutes into a first start — so resolve it
    # against the remote and fall back to whatever HEAD points at.
    if [ -z "$_ref" ] || ! git ls-remote --exit-code "$_repo" "$_ref" >/dev/null 2>&1; then
        _default="$(git_default_ref "$_repo")"
        if [ -n "$_default" ]; then
            [ -n "$_ref" ] && [ "$_ref" != "$_default" ] && \
                warn "$(basename "$_dir"): no ref '$_ref' on the remote — using its default branch '$_default'"
            _ref="$_default"
        fi
    fi
    if [ -d "$_dir/.git" ]; then
        log "updating $(basename "$_dir") -> $_ref"
        git -C "$_dir" fetch --depth 1 origin "$_ref"
        git -C "$_dir" checkout -q FETCH_HEAD
    else
        log "cloning $_repo @ $_ref"
        rm -rf "$_dir"
        git clone --depth 1 -b "$_ref" "$_repo" "$_dir"
    fi
}

# curl against the local API, carrying the bearer token when AUTH_ENABLED is on.
api_curl() {
    if [ -n "${AUTH_TOKEN:-}" ]; then
        curl -fsS -H "Authorization: Bearer $AUTH_TOKEN" "$@"
    else
        curl -fsS "$@"
    fi
}

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# HS256 bearer for the API's own auth gate. Only needed when AUTH_ENABLED=true;
# the API runs unauthenticated by default (see api.RegisterAll).
sign_jwt() {
    _secret="${API_JWT_SECRET:-${INFLOW_INFRA_JWT_SECRET:-}}"
    [ -n "$_secret" ] || return 1
    _now="$(date +%s)"
    _h="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)"
    _p="$(printf '{"admin":true,"iat":%s,"exp":%s}' "$_now" "$((_now + 3600))" | b64url)"
    _s="$(printf '%s.%s' "$_h" "$_p" | openssl dgst -sha256 -hmac "$_secret" -binary | b64url)"
    printf '%s.%s.%s' "$_h" "$_p" "$_s"
}

# ── 1. Go module proxy for the plugin build ───────────────────────────────────
# Pick a working Go module proxy before the plugin nodes are compiled. install.sh
# cannot do this reliably: it runs on the host, but the plugin build runs in THIS
# container, whose egress can differ from the host's — the default proxy redirects
# module zips to storage.googleapis.com, and a host that reaches it does not prove
# this container can (the common case is exactly the reverse). So probe from here,
# the way the build fetches (a real module zip, redirect followed), and fall back
# to a mirror on failure. An explicit GOPROXY is always respected, never probed.
ensure_goproxy() {
    if [ -n "${GOPROXY:-}" ]; then
        log "go module proxy (set by the operator): $GOPROXY"
        return 0
    fi
    command -v go >/dev/null 2>&1 || return 0   # nothing here will compile
    _probe='https://proxy.golang.org/github.com/klauspost/compress/@v/v1.18.5.zip'
    # -r 0-0 keeps it to a single byte; -L follows to storage.googleapis.com,
    # which is the host that actually 403s on a blocked network.
    if curl -fsSL -m 20 -r 0-0 -o /dev/null "$_probe" 2>/dev/null; then
        log "go module proxy: default (proxy.golang.org) reachable from this container"
    else
        export GOPROXY="$GOPROXY_MIRROR"
        warn "the default Go module CDN is unreachable from this container — it blocks"
        warn "proxy.golang.org / storage.googleapis.com and the build would 403 mid-download."
        warn "Falling back to a mirror so the plugin build succeeds: GOPROXY=$GOPROXY"
        warn "Pin GOPROXY in flomorphic/.env to choose a different one."
    fi
}

ensure_goproxy

# api + canvas are baked into the image; only the plugin nodes are built here.
[ -x "$APP_DIR/flomorphic-api" ] || die "no flomorphic-api binary at $APP_DIR/flomorphic-api"
[ -e "$WEB_ROOT/index.html" ]    || die "no canvas build at $WEB_ROOT"

# ── 2. nginx ──────────────────────────────────────────────────────────────────
mkdir -p /run/nginx
sed -e "s|__API_PORT__|$PORT|g" \
    -e "s|__WEB_PORT__|$WEB_PORT|g" \
    -e "s|__WEB_ROOT__|$WEB_ROOT|g" \
    /etc/nginx/nginx.conf.tmpl > /etc/nginx/nginx.conf
nginx -t
nginx -g 'daemon off;' &
track "$!" nginx
log "nginx serving the canvas on :$WEB_PORT"

# ── 3. flomorphic-api ─────────────────────────────────────────────────────────
mkdir -p "$(dirname "$DB_SOURCE")"
cd "$APP_DIR"
./flomorphic-api &
api_pid="$!"
track "$api_pid" flomorphic-api
log "flomorphic-api starting on :$PORT (db: $DB_SOURCE)"

# ── 4. wait for the API ───────────────────────────────────────────────────────
i=0
until curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; do
    kill -0 "$api_pid" 2>/dev/null || die "flomorphic-api exited during startup"
    i=$((i + 1))
    [ "$i" -gt 120 ] && die "flomorphic-api did not answer /health within 120s"
    sleep 1
done
log "flomorphic-api is ready"

AUTH_TOKEN=""
if is_true "${AUTH_ENABLED:-}"; then
    AUTH_TOKEN="$(sign_jwt)" || warn "AUTH_ENABLED is set but no secret is configured"
fi

# ── 5-6. builtin plugin nodes ─────────────────────────────────────────────────
#
# One credential, minted once, shared by every builtin plugin: `access: multi`
# returns an account-wide credential on the builtin-plugins account, which is
# exactly the scope a set of first-party nodes wants. (A third-party plugin
# should get `strict`, which is scoped to a single PLUGIN_ID.)
mint_plugin_cred() {
    _body="$(printf '{"name":"%s","access":"multi"}' "$PLUGIN_CRED_NAME")"
    api_curl -X POST "http://127.0.0.1:$PORT/extension/plugin/cred" \
        -H 'Content-Type: application/json' -d "$_body" \
    | jq -er '.data.cred'
}

# The plugin SDK prefixes nats:// itself, so this must stay host:port. NATS lives
# alongside Infra's REST API, so the host comes straight off INFLOW_INFRA_API.
plugin_infra_url() {
    if [ -n "$PLUGIN_INFRA_URL" ]; then printf '%s' "$PLUGIN_INFRA_URL"; return; fi
    _host="$(printf '%s' "$INFLOW_INFRA_API" \
        | sed -e 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||' -e 's|/.*$||' -e 's|:[0-9]*$||')"
    printf '%s:%s' "$_host" "$PLUGIN_NATS_PORT"
}

# Resolve one plugin folder's inflowv1 PLUGIN_ID. Precedence:
#   PLUGIN_ID_<NAME> env  ->  the seeded builtin row  ->  the seed file on disk.
plugin_id_for() { # <folder name>
    _name="$1"
    _var="PLUGIN_ID_$(printf '%s' "$_name" | tr '[:lower:]-' '[:upper:]_')"
    eval "_override=\${$_var:-}"
    if [ -n "$_override" ]; then printf '%s' "$_override"; return; fi

    _id="$(api_curl "http://127.0.0.1:$PORT/extension?kind=builtin&per_page=100" 2>/dev/null \
        | jq -r --arg t "$_name" '[.data.list[]? | select(.type == $t) | .pluginId // empty][0] // empty' 2>/dev/null || true)"
    if [ -n "$_id" ]; then printf '%s' "$_id"; return; fi

    _seed="$SRC_DIR/api/repository/sqlite/seed/builtins.json"
    if [ -f "$_seed" ]; then
        jq -r --arg t "$_name" '[.[] | select(.type == $t) | .pluginId // empty][0] // empty' "$_seed" 2>/dev/null || true
    fi
}

wanted_plugin() { # <folder name> — honours an explicit PLUGINS list
    [ -z "$PLUGINS" ] && return 0
    for _w in $(printf '%s' "$PLUGINS" | tr ',' ' '); do
        [ "$_w" = "$1" ] && return 0
    done
    return 1
}

# Clone + compile the plugin repo unless binaries for this exact repo@ref are
# already present (the baked image ships them; a volume keeps them across
# restarts). Changing PLUGINS_REPO/PLUGINS_REF invalidates them.
ensure_plugin_binaries() {
    _want="$PLUGINS_REPO@$PLUGINS_REF"
    _have="$(cat "$PLUGIN_BIN_DIR/.ref" 2>/dev/null || true)"
    if [ "$_want" = "$_have" ] && [ -n "$(find "$PLUGIN_BIN_DIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | head -n1)" ]; then
        log "plugin binaries up to date ($_want)"
        return 0
    fi

    # Every step is explicitly checked: the caller treats a failure here as
    # "run without plugin nodes", not as a reason to kill a working canvas.
    git_sync "$PLUGINS_REPO" "$PLUGINS_REF" "$PLUGIN_SRC_DIR" || return 1
    mkdir -p "$PLUGIN_BIN_DIR"
    rm -f "$PLUGIN_BIN_DIR/.ref"
    for _dir in "$PLUGIN_SRC_DIR"/*/; do
        [ -f "${_dir}go.mod" ] || continue
        _name="$(basename "$_dir")"
        wanted_plugin "$_name" || continue
        log "building plugin $_name"
        ( cd "$_dir" && CGO_ENABLED=0 go build -trimpath -o "$PLUGIN_BIN_DIR/$_name" . ) || return 1
    done
    printf '%s' "$_want" > "$PLUGIN_BIN_DIR/.ref"
}

start_plugins() {
    is_true "$PLUGINS_ENABLED" || { log "builtin plugin nodes disabled (PLUGINS_ENABLED=0)"; return 0; }
    if [ -z "$INFLOW_INFRA_API" ]; then
        warn "INFLOW_INFRA_API is not set — the API runs CRUD-only and no plugin can be credentialed."
        warn "The canvas works for designing and saving; Run needs a platform. Skipping plugin nodes."
        return 0
    fi
    if [ -z "${INFLOW_INFRA_JWT_SECRET:-}" ]; then
        warn "INFLOW_INFRA_JWT_SECRET is empty — Infra will reject this API, so no credential can be minted."
        warn "Put the platform's API Secret Key in flomorphic/.env and recreate the container."
    fi

    log "minting the shared builtin-plugins credential"
    _cred="$(mint_plugin_cred || true)"
    if [ -z "$_cred" ]; then
        warn "could not mint a plugin credential — is Infra reachable at $INFLOW_INFRA_API?"
        warn "continuing without the builtin plugin nodes; LLM/MCP nodes will not execute."
        return 0
    fi
    _infra="$(plugin_infra_url)"
    log "plugin NATS endpoint: $_infra"

    if ! ensure_plugin_binaries; then
        warn "could not build the plugin binaries ($PLUGINS_REPO@$PLUGINS_REF) —"
        warn "continuing without the builtin plugin nodes; the canvas and API stay up."
        return 0
    fi

    _started=0
    for _bin in "$PLUGIN_BIN_DIR"/*; do
        [ -f "$_bin" ] && [ -x "$_bin" ] || continue
        _name="$(basename "$_bin")"
        case "$_name" in .*) continue ;; esac
        wanted_plugin "$_name" || continue

        _id="$(plugin_id_for "$_name")"
        if [ -z "$_id" ]; then
            warn "no PLUGIN_ID for '$_name' (not a seeded builtin?) — set PLUGIN_ID_$(printf '%s' "$_name" | tr '[:lower:]-' '[:upper:]_') to run it. Skipped."
            continue
        fi

        log "starting plugin node $_name (PLUGIN_ID=$_id)"
        (
            cd "$PLUGIN_BIN_DIR"
            PLUGIN_ID="$_id" INFRA_CRED="$_cred" INFRA_URL="$_infra" exec "$_bin"
        ) &
        track "$!" "plugin:$_name"
        _started=$((_started + 1))
    done
    log "$_started builtin plugin node(s) running"
}

start_plugins

# ── 7. supervise ──────────────────────────────────────────────────────────────
log "FloMorphic is up — canvas on :$WEB_PORT, api on :$PORT"
while :; do
    for entry in $procs; do
        pid="${entry%%:*}"
        name="${entry#*:}"
        if ! kill -0 "$pid" 2>/dev/null; then
            warn "$name (pid $pid) exited — stopping the container"
            stop_children
            exit 1
        fi
    done
    sleep 5
done
