# Developing FloMorphic from source

The installed stack is one container with the api and canvas baked in (only the
plugin nodes build on first start). To *change* FloMorphic
you take it apart: run `morph-api` from your own checkout, the canvas on Vite,
the plugin nodes as ordinary processes you can attach a debugger to — all bound
to a platform (Infra + a Fractal) that keeps running in Docker exactly as
installed.

**Two environment variables bind all of it:** `INFLOW_INFRA_API` and
`INFLOW_INFRA_JWT_SECRET`. Everything else has a working default. Anything you
start from source — the API, a plugin node, a service of your own — becomes part
of the same live runtime the moment those two are right.

**See also:** [Architecture & deployment](./architecture.md) ·
[Concepts](./concepts.md) · [Node palette](./nodes.md) ·
[back to README](../README.md)

---

## The shape of a dev setup

You never build the runtime to develop the product. Infra and Fractal stay as
installed containers; the FloMorphic layer is what you run from source — all of
it, or one piece with the rest still in the container.

| Piece | Repository | Dev command | Listens on |
| --- | --- | --- | --- |
| Infra + Fractal | *(installed containers — leave them running)* | `docker compose up -d` | `8022` REST · `4222` NATS |
| FloMorphic API | [`FloMorphic/morph-api`](https://github.com/FloMorphic/morph-api) | `make run` | `8025` |
| FloMorphic canvas | [`FloMorphic/morph-wapp`](https://github.com/FloMorphic/morph-wapp) | `pnpm dev` | `5173` |
| Builtin plugin nodes | [`FloMorphic/builtin-plugins`](https://github.com/FloMorphic/builtin-plugins) | `go run .` | *(nothing — NATS clients)* |

```
 your machine (source)                        docker (installed platform)
 ┌────────────────────────────────┐          ┌────────────────────────────┐
 │ morph-wapp    pnpm dev  :5173  │          │  Infra                     │
 │      │                         │          │    REST  :8022             │
 │      │ VITE_API_BASE_URL       │          │    NATS  :4222             │
 │      ▼                         │  REST +  │                            │
 │ morph-api     make run  :8025  │───NATS──►│  Fractal (engine)          │
 │        INFLOW_INFRA_API        │          │    walks the graph         │
 │        INFLOW_INFRA_JWT_SECRET │          │                            │
 │                                │          └────────────────────────────┘
 │ llm / mcp plugin nodes         │───NATS──────────────┘
 │        PLUGIN_ID + INFRA_CRED  │   (credential minted by morph-api)
 └────────────────────────────────┘
```

The API is not in the execution path: it answers the engine's questions (fetch a
flow, read and write context) and serves the `svc.*` handlers behind the store,
HITL and Continue After nodes. Fractal does the traversal, and the plugin nodes
answer on their own subjects. That is why each piece can be restarted — or paused
on a breakpoint — without the others noticing.

---

## The two variables that bind everything

| Variable | What it does |
| --- | --- |
| `INFLOW_INFRA_API` | Infra's REST base URL — accounts, resources, credential minting. **The NATS endpoint is derived from it:** the same hostname on port `4222`. It is the only address you set. Empty ⇒ the API serves CRUD only. |
| `INFLOW_INFRA_JWT_SECRET` | The platform's **API Secret Key** (`API_JWT_SECRET` in the platform's `.env`). The API signs its calls to Infra with it, so it must match character for character — a wrong value fails at connect, not at first use. |

The value of `INFLOW_INFRA_API` depends on where the process runs, because it is
a host name resolved by that process:

| The process runs… | Use |
| --- | --- |
| On your machine (`make run`, `go run`, a debugger) | `http://localhost:8022` |
| In a container on `inflow_net` | `http://inflow-infra:8022` |
| Against a platform on another box | that box's address — publish `8022` **and** `4222` |

Finding the secret, in order of least typing:

```bash
grep API_JWT_SECRET <install dir>/platform/.env        # written by the installer
docker logs inflow-infra 2>&1 | grep -i 'api secret'   # Infra prints it on first boot
```

`install.sh` also prints it in its closing summary. The same value goes into
`flomorphic/.env` as `INFLOW_INFRA_JWT_SECRET` for the installed container and
into your shell, `.env` or debugger config for a source run — one secret, three
places it can be spelled.

---

## 0. A platform to bind to

If you have installed FloMorphic already, you have one — reuse it, and skip
ahead. Otherwise install the platform on its own:

```bash
curl -fsSL https://raw.githubusercontent.com/Inflowenger/getting-started/main/install.sh | bash
```

Two things must be true before anything from source can bind:

```bash
docker ps --format '{{.Names}}\t{{.Status}}'                       # inflow-infra + a fractal, up
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8022/    # any status = reachable
```

The platform compose publishes `4222` as well as `8022`, which is exactly what a
process on the host needs — `nats://localhost:4222` is where your API and your
plugin nodes will connect. A Fractal must be registered too, or a flow will
compile and save but never run.

Nothing here assumes containers: if you run Infra or a Fractal from source, the
two variables point at wherever they listen instead. The FloMorphic layer cannot
tell the difference.

---

## 1. `morph-api` from source

Go 1.26+ and a C compiler (the sqlite driver and `sqlite-vec` are cgo).

```bash
git clone https://github.com/FloMorphic/morph-api.git
cd morph-api
cp .env.example .env
```

The only two lines that matter:

```bash
INFLOW_INFRA_API=http://localhost:8022
INFLOW_INFRA_JWT_SECRET=<the platform's API Secret Key>
```

```bash
make run          # or: make build && ./flomorphic-api      → :8025
```

`make` owns the cgo flags for the vendored `sqlite3.h`, so a plain `go build`
needs `CGO_CFLAGS="-I$PWD/repository/sqlite/cdeps"` to find the header.

**What "bound" looks like in the log.** The runtime is optional by design, and
the API says which mode it came up in:

| Log line | Meaning |
| --- | --- |
| `New SVC handler registered On svc.hitl.add` (and the store / continue subjects) | Bound. Runs work. |
| `inflow runtime disabled (INFLOW_INFRA_API not set) — serving CRUD only` | No platform. Design and save workflows; `Run` does nothing. |
| `warning: inflow runtime not connected: …` | It tried and failed — wrong secret, wrong host, or Infra unreachable. The CRUD API keeps serving. |

CRUD-only is a legitimate mode, not a failure: it is the right setup for canvas
work, and it needs no platform at all.

Two loading details worth knowing before you fight them:

- The `.env` file is read **relative to the working directory**, so a binary run
  from elsewhere sees no config. Process environment always wins over the file.
- `ENV=dev` makes it read `.env.dev` instead — one checkout, several platforms.

The database is a file (`DB_SOURCE`, `db/flomorphic.db` by default). Deleting it
is the reset: builtin nodes and prompt templates are re-seeded from the binary on
the next start, and the seeded plugin ids stay the same, so saved workflows
elsewhere keep resolving.

---

## 2. `morph-wapp` from source

```bash
git clone https://github.com/FloMorphic/morph-wapp.git
cd morph-wapp
pnpm install
cp .env.example .env
```

```bash
VITE_API_BASE_URL=http://localhost:8025      # the API you just started
```

```bash
pnpm dev            # → :5173, with HMR
pnpm typecheck      # vue-tsc, no emit
pnpm build          # type-check + production bundle into dist/
```

The API enables CORS, so pointing the dev server straight at `:8025`
cross-origin works — no proxy to configure. (The installed image does the
opposite: it bakes a *relative* base and lets nginx route `/api` and `/ws`, which
is why one image runs anywhere. See
[Architecture → One container, on purpose](./architecture.md#one-container-on-purpose).)

Leave `VITE_API_BASE_URL` empty and the canvas runs standalone against browser
storage — useful for pure UI work, and the mode the header reports as
disconnected.

The log drawer is a WebSocket (`/ws/flomorphic`) onto the same base URL. It is
mounted before the auth gate, so it stays open even with `AUTH_ENABLED=true`.

---

## 3. The plugin nodes from source

The LLM and MCP nodes are ordinary inflow plugins: separate processes, no
privileged access, talking `inflowv1` over NATS. Each needs three things.

**A credential.** Only `morph-api` can mint one (it holds the builtin-plugins
account), which is why the container starts the API first and the plugins second.
From source you do that step by hand, once — the credential is account-wide, so
the same value serves every builtin plugin:

```bash
curl -fsS -X POST http://localhost:8025/extension/plugin/cred \
  -H 'Content-Type: application/json' \
  -d '{"name":"dev-builtins","access":"multi"}' | jq -r '.data.cred'
```

The canvas does the same thing from **Settings → plugin credential**, with a copy
button. Either way, take the `cred` value: the response's ready-made `env` block
carries `INFRA_URL=infra:4222`, which is the container's view, not yours.

**A plugin id.** These are fixed seed values, not generated — that is what keeps a
saved workflow resolving across reinstalls:

| Plugin folder | `PLUGIN_ID` |
| --- | --- |
| `llm` | `aaaa-bbbb-cccc-llm0` |
| `mcp` | `aaaa-bbbb-cccc-mcp0` |

Read them back from the API if you ever doubt it:

```bash
curl -fsS 'http://localhost:8025/extension?kind=builtin&per_page=100' \
  | jq -r '.data.list[] | select(.pluginId != null and .pluginId != "") | "\(.type)\t\(.pluginId)"'
```

**An env file.** Each plugin's `main.go` loads `.env.morph` from its working
directory (`.env.inflow.example` is the template):

```bash
git clone https://github.com/FloMorphic/builtin-plugins.git
cd builtin-plugins/llm
cp .env.inflow.example .env.morph
```

```bash
PLUGIN_ID=aaaa-bbbb-cccc-llm0
INFRA_URL=localhost:4222
INFRA_CRED=<the cred string from above>
```

`INFRA_CRED` is the base64 credential **itself**, not a path to a `.creds` file —
the SDK decodes it in place. `INFRA_URL` is `host:port` with no scheme; the SDK
prefixes `nats://`.

```bash
go run .                 # or: go build -o bin/llm . && ./bin/llm
```

Repeat for `mcp` with its own `PLUGIN_ID`, reusing the same credential. Provider
API keys are not env vars here — they are node settings, configured on the canvas
and delivered with the call.

---

## Mixing installed and source

You rarely want all four processes from source. Keep the container for the parts
you are not touching, and replace one:

| You are working on | Keep running | Run from source | Wiring |
| --- | --- | --- | --- |
| **The canvas** | the whole `flomorphic` container | `pnpm dev` | `VITE_API_BASE_URL=http://localhost:8026` — the container's published API port |
| **The API** or its `svc.*` handlers | the platform only (`docker compose stop flomorphic`) | API + the plugin nodes | `INFLOW_INFRA_API=http://localhost:8022`, canvas on `:5173` or a `pnpm build` |
| **A plugin node** | the container with `PLUGINS_ENABLED=0` in `flomorphic/.env` | just that plugin | mint the credential from the container's API on `:8026` |
| **A backend of your own** (`inflow-fusion`) | everything | your service | the same two variables — [Architecture → attaching a system you already run](./architecture.md#meeting-the-system-you-already-run) |

> **Run one `morph-api` per platform.** The `svc.*` handlers are plain NATS
> subscriptions, not a queue group: two API instances bound to the same Infra
> both receive every HITL, store and continue request and both answer, each from
> its own database. Stop the container before you `make run` against the same
> platform (the ports don't collide — the subjects do).

The installed stack and a source run keep separate databases (the container's
`flomorphic/data/flomorphic.db`, yours wherever `DB_SOURCE` points), so workflows
saved in one do not appear in the other. Export a flow from the canvas to carry
it across.

---

## Debugging

**The API, in VS Code.** The cgo flags the Makefile exports have to be restated
for delve, or the sqlite build fails before the debugger starts:

```json
{
  "name": "morph-api",
  "type": "go",
  "request": "launch",
  "mode": "debug",
  "program": "${workspaceFolder}",
  "cwd": "${workspaceFolder}",
  "env": {
    "CGO_ENABLED": "1",
    "CGO_CFLAGS": "-I${workspaceFolder}/repository/sqlite/cdeps",
    "PORT": "8025",
    "DB_SOURCE": "db/flomorphic.db",
    "INFLOW_INFRA_API": "http://localhost:8022",
    "INFLOW_INFRA_JWT_SECRET": "<the platform's API Secret Key>"
  }
}
```

Same on the command line: `CGO_CFLAGS="-I$PWD/repository/sqlite/cdeps" dlv debug .`

**A plugin node.** `program` and `cwd` both point at the plugin folder — the SDK
reads `.env.morph` relative to the working directory, so a wrong `cwd` looks
exactly like a missing credential.

```json
{
  "name": "llm plugin",
  "type": "go",
  "request": "launch",
  "mode": "debug",
  "program": "${workspaceFolder}/llm",
  "cwd": "${workspaceFolder}/llm"
}
```

**Where to look when a run misbehaves.** The canvas traces events back onto the
nodes that produced them; the layer below that is process logs:

```bash
docker logs -f fractal-1        # the engine walking the graph
docker logs -f inflow-infra     # accounts, credentials, registration
```

Breakpoints are safe on every side of this: the engine waits on a reply, so a
paused `svc.*` handler or plugin action parks the run rather than failing it —
until the request times out.

---

## When it does not bind

| Symptom | Cause | Fix |
| --- | --- | --- |
| `serving CRUD only` | `INFLOW_INFRA_API` empty — often a `.env` that is not in the working directory | Run from the checkout root, or set the variable in the environment |
| `inflow runtime not connected` | Secret mismatch, or Infra not reachable at that address | Re-copy `API_JWT_SECRET` from `platform/.env`; use `localhost:8022` from the host, not `inflow-infra:8022` |
| Saves work, `Run` does nothing | No Fractal registered with Infra | `docker ps` for the fractal container; it retries registration on restart |
| Plugin exits at startup | `INFRA_CRED` is a file path or a truncated paste, or `INFRA_URL` carries a `nats://` scheme | The cred is the base64 string verbatim; the URL is `host:port` |
| LLM/MCP node never executes | The plugin process is not running, or its `PLUGIN_ID` does not match the seed | Check the ids against `GET /extension?kind=builtin` |
| Two answers to one HITL request | A second `morph-api` bound to the same platform | Stop one of them |
| `403 Forbidden` during a Go build | `proxy.golang.org` redirects module zips to `storage.googleapis.com`, blocked on some networks | `export GOPROXY=https://goproxy.cn,direct` |
| `u_int8_t` typedef errors | musl (Alpine) building `sqlite-vec` — a container problem, not a host one | `make build CGO_CFLAGS="-I$PWD/repository/sqlite/cdeps -Du_int8_t=uint8_t -Du_int16_t=uint16_t -Du_int64_t=uint64_t"` |
| Port `8025` already taken | `inflow-inspector-api` uses it too | Move one with `PORT` |

---

## Where this goes next

- What the pieces are and how they talk → [Architecture & deployment](./architecture.md)
- What a node compiles down to before you change the compiler →
  [Concepts](./concepts.md) and [Node palette](./nodes.md)
- Building a node of your own: a palette entry plus a compiler case, or a plugin
  against the Go / Node SDK → [Node palette → Adding a node kind](./nodes.md#adding-a-node-kind)
