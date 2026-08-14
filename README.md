<div align="center">

# FloMorphic — Getting Started

**The open-source AI harness, built on the Inflowenger context runtime.**

The install path, the developer tooling, and the documentation map for
FloMorphic — the first product built end-to-end on [Inflowenger](https://inflowenger.com).

`Inflowenger` · `inflow-fusion` · `FloMorphic API` · `FloMorphic Web App` · `Builtin plugin nodes`

</div>

```bash
curl -fsSL https://raw.githubusercontent.com/FloMorphic/getting-started/main/install.sh | bash
```

Docker is the only prerequisite; the canvas comes up on http://localhost:8088.
Full details in [Install](#install).

---

## What FloMorphic is

**A platform for building your own agents and AI-native systems — low-code, on a
runtime you own.** Not a library you import. Not a SaaS you send your data to. An
AI harness where every capability the field has developed becomes an ordinary node
on one graph, over one shared context:

<div align="left">

`RAG` · `context engineering` · `agent loops` · `tool use` · `MCP` · `long-term memory` ·
`working memory` · `guardrails & policy` · `human-in-the-loop` · `multi-agent orchestration` ·
`out-of-model reasoning` · `observability`

</div>

And — the part that matters most — **it attaches to the system you are already
running.** Your existing backend does not get rewritten, replaced, or migrated. It
joins: it answers the graph, and the graph calls it. A system that has been in
production for a decade can become AI-native without a rewrite, and can grow from
one laptop to a cluster without changing its shape.

This is the **Software V3** thesis Inflowenger is built on: business logic is not
code distributed across services — it is a workflow graph over living context,
changeable by an operator without a redeploy. FloMorphic is that thesis applied to
the AI layer.

**And it is open source.** The runtime primitives, the compiler seam, the API, the
canvas, and the LLM and MCP plugin nodes are all readable, forkable and
self-hostable. There is no hosted-only capability holding the interesting part
back — the AI nodes are ordinary plugins, which is exactly why yours can be too.

> **Not a product. An opportunity.** FloMorphic is not sold as the finished answer
> to your problem — it is the means to build your own. Nothing in the runtime is
> reserved for it, which is precisely why the thing you build on top can be as much
> a product as FloMorphic is.

**How it works, in one paragraph.** A headless runtime (Infra + Fractal) executes
workflow graphs made of exactly [six primitives](./docs/concepts.md). A Go SDK
(`inflow-fusion`) binds your backend into it. FloMorphic sits on top as the product
layer: thirteen intent-level canvas nodes — LLM, MCP, Rule, stores,
human-in-the-loop — each of which *compiles down* to one of those six. The model's
permitted decisions are edges you can see; policy, retrieval and approval are
ordinary nodes; the whole thing runs on your infrastructure.
→ [Concepts](./docs/concepts.md) · [AI harness](./docs/ai-harness.md) ·
[Node palette](./docs/nodes.md) · [Architecture](./docs/architecture.md)

---

## What this repository is

FloMorphic is a stack of layers — a headless runtime, a Go SDK, a product API, a
canvas frontend, and a set of plugin node binaries — each with its own repository
and its own README. That is a lot of surface for someone who just wants to *run the
thing*. This repository is the entry point:

- **One install path** — [`install.sh`](./install.sh) stands up the whole stack
  (Inflowenger platform + FloMorphic API + web app + builtin plugin nodes) instead
  of five separate setups.
- **Developer tools** — what you need when you want to change FloMorphic rather
  than only use it. The local wiring is documented today
  ([Developing from source](./docs/development.md)); plugin scaffolding, resets
  and smoke checks are being assembled.
- **A documentation map** — [`docs/`](./docs/) explains the model, and the
  [documentation map](#documentation) below points at whichever layer answers your
  question.

> **Status.** The concept, the map, the install path and the from-source
> developer guide are current: `install.sh`, the compose stack and
> [docs/development.md](./docs/development.md) are here. The developer *tooling*
> (plugin scaffolding, resets, an end-to-end smoke check) is still being
> assembled; until it lands, the guide plus each component's own README are the
> source of truth.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/FloMorphic/getting-started/main/install.sh | bash
```

Docker and the Compose v2 plugin are the only prerequisites. The script pulls the
published, baked image and asks only a couple of things:

| It asks | Because |
| --- | --- |
| **Install directory** | where the compose stacks and the database land |
| **Platform: the one already running, or a new one?** | FloMorphic is a product *on* the Inflowenger runtime. A new platform is installed by [the Inflowenger installer](https://github.com/Inflowenger/getting-started) itself — one source of truth, not a copy |
| **Advanced options (optional)** | override the ports (canvas `8088`, API `8026`) |

Building an image is a maintainer job, not an install-time one — the installer
always pulls. To build one yourself, `make build` / `make release` (see the
[Makefile](./Makefile)).

The builtin plugin nodes are not one of the questions: they are what the canvas's
stock nodes run as, so the image always bakes them in. `PLUGINS_ENABLED=0`
is still there for a canvas + API with no platform behind it.

Everything it asks can be set with an env var instead (`ASSUME_YES=1` for an
unattended run) — see the header of [`install.sh`](./install.sh).

```
<install dir>/
├── platform/          Infra + Fractal        (only when it installs one for you)
├── inspector/         inflow-inspector       (only with INSTALL_INSPECTOR=1)
└── flomorphic/
    ├── docker-compose.yml
    ├── .env           image ref, ports, and the shared API Secret Key
    └── data/          the SQLite database — workflows, contexts, prompts, vectors
```

When it finishes: the canvas on **http://localhost:8088**, the API on
**http://localhost:8026**, Infra on **http://localhost:8022**.

```bash
cd <install dir>/flomorphic
docker compose logs -f          # follow the boot
docker compose down             # stop
docker compose up -d            # start again
```

The canvas, the API and the plugin nodes ship as **one image**, all baked in
per-arch (amd64 + arm64), so it starts fast and builds nothing at run time. Why it
is one container — and how to run your own plugin set — is in
[Architecture → One container, on purpose](./docs/architecture.md#one-container-on-purpose).

### Running from source

To *change* FloMorphic rather than only run it, take the container apart: the
platform stays installed, and you run the product layer from your own checkouts.

```bash
# 1. Platform (Infra + Fractal) — installed containers, left running
curl -fsSL https://raw.githubusercontent.com/Inflowenger/getting-started/main/install.sh | bash

# 2. FloMorphic API   (Go 1.26+, cgo)                        → :8025
git clone https://github.com/FloMorphic/morph-api.git && cd morph-api
cp .env.example .env      # INFLOW_INFRA_API=http://localhost:8022
make run                  # INFLOW_INFRA_JWT_SECRET=<the platform's API Secret Key>

# 3. FloMorphic canvas                                       → :5173
git clone https://github.com/FloMorphic/morph-wapp.git && cd morph-wapp
pnpm install && cp .env.example .env    # VITE_API_BASE_URL=http://localhost:8025
pnpm dev

# 4. Builtin plugin nodes — each needs a credential the API mints, in .env.morph
git clone https://github.com/FloMorphic/builtin-plugins.git
cd builtin-plugins/llm && go run .
cd builtin-plugins/mcp && go run .
```

**Two variables bind all of it to the runtime you already have installed:**
`INFLOW_INFRA_API` (Infra's REST base — the NATS endpoint is derived from its
host) and `INFLOW_INFRA_JWT_SECRET` (the platform's API Secret Key). Anything you
start from source joins the same live platform the moment those two are right.
The runtime is also **optional**: leave `INFLOW_INFRA_API` unset and the API runs
CRUD-only, which is enough to design and save workflows. Set it, and `Run` goes
live.

→ **[Developing from source](./docs/development.md)** — the full guide: where to
find the secret, minting a plugin credential by hand, running one piece from
source against the installed container, debugger configs, and what each failure
mode actually means.

> **A Go build that dies on `403 Forbidden`** is a network problem, not a broken
> checkout: `proxy.golang.org` redirects module zips to `storage.googleapis.com`,
> which some networks block. Point Go at a mirror and it goes away — from source
> `export GOPROXY=https://goproxy.cn,direct`, and for an image build
> `--build-arg GOPROXY=https://goproxy.cn,direct`. The installed stack needs
> nothing: everything is baked, so it never compiles at run time.

| Service | From source | Installed |
| --- | --- | --- |
| Infra API | `8022` | `8022` |
| NATS | `4222` (monitoring `8222`) | same |
| FloMorphic canvas | `5173` (Vite dev server) | **`8088`** — and the API behind it on `/api` |
| FloMorphic API | `8025` | `8026` on the host, `8025` inside the container |
| inflow-inspector | `8080` (panel) · `8025` (its API) | same |

> The installed canvas and API sit on `8088`/`8026` rather than `5173`/`8025` so a
> FloMorphic install and an inflow-inspector install can run side by side.

### Drive it from Claude (MCP)

The FloMorphic API is **itself an MCP server** — mounted at `/mcp`, on by default.
Every entity the canvas edits (workflows, contexts, prompts, memory stores,
triggers, human tasks, runs) is an MCP tool over the same call path the web app
uses, so an AI client can drive FloMorphic directly: **design a workflow, save it,
run it, and read back what it produced** — including the same AI-authoring brain the
canvas's [AI Build](https://inflowenger.com/blog/flomorphic-claims-walkthrough)
dialog uses.

Point any MCP client at the endpoint — no bridge for clients that speak Streamable
HTTP:

```bash
# Claude Code
claude mcp add --transport http flomorphic http://localhost:8026/mcp
```

Claude Desktop connects by URL (**Settings → Connectors → Add custom connector**,
`http://localhost:8026/mcp`) or, on classic builds, via the `mcp-remote` bridge.
→ **[FloMorphic over MCP](./docs/mcp.md)** — the full tool catalog, per-client setup
(Claude Desktop, Claude Code, Cursor), auth, and a first design-run-inspect session.

### Still on the roadmap

- [x] **Local dev wiring** — API + Vite + plugin nodes against a running platform,
      documented in [Developing from source](./docs/development.md).
- [ ] **Developer tools** — scripts for that wiring, plugin scaffolding,
      database/context resets, and a smoke check that runs a known flow end to end.
- [ ] **Layered docs** — a walkthrough per layer: *use it* → *extend it with a
      plugin* → *build your own product on the runtime*.

---

## Documentation

**In this repository** — the model, in reading order:

| Doc | What it covers |
| --- | --- |
| [docs/concepts.md](./docs/concepts.md) | The three layers, the six runtime primitives, and the compiler seam between a canvas and the engine. |
| [docs/nodes.md](./docs/nodes.md) | FloMorphic's thirteen canvas nodes, what each lowers to, and the entities around the canvas. |
| [docs/ai-harness.md](./docs/ai-harness.md) | Virtual functions, context, memory stores, out-of-model reasoning — and how RAG, agent loops, tool use and guardrails map onto them. |
| [docs/architecture.md](./docs/architecture.md) | Process topology, attaching a system you already run, scaling out, and the container design. |
| [docs/development.md](./docs/development.md) | Running the API, the canvas and the plugin nodes from source against an installed platform — the two variables that bind them, credentials, debugger configs, failure modes. |
| [docs/mcp.md](./docs/mcp.md) | Driving FloMorphic from an MCP client (Claude Desktop, Claude Code, Cursor) — the `/mcp` endpoint, per-client setup, the `flo_*` tool catalog and designer prompt, and auth. |

**In the component repositories** — which layer answers your question:

| You want to… | Read |
| --- | --- |
| Understand the whole mental model in one page | The website's **Concepts** page |
| Know what each primitive is and how to build one | `inflow-fusion` → `docs/nodes.md` and `docs/nodes/` |
| See how *any* frontend node reduces to a primitive | `inflow-fusion` → `docs/nodes/from-frontend.md` |
| Understand infra, engines, backends and plugins together | `inflow-fusion` → `docs/architecture.md` |
| Get the exact REST endpoints and NATS subjects | `inflow-fusion` → `docs/infra.md` |
| Compile a canvas graph into engine nodes | `inflow-fusion` → `docs/compilers/` |
| Observe a running flow | `inflow-fusion` → `docs/logs.md` |
| Work on FloMorphic's own API | `flomorphic-api/README.md` |
| Work on the canvas | `flomorphic-wapp/README.md` |
| Build or modify a plugin node | `builtin-plugins/README.md`, then the plugin SDK |
| Install the platform by itself | `Inflowenger/getting-started` |

---

## The ecosystem map

| Repository | Layer | What it is |
| --- | --- | --- |
| **Infra** | runtime | Coordination + embedded NATS + credential minting. Everything starts here. |
| **Fractal** | runtime | The execution engine. Attaches to Infra, walks compiled node maps. |
| [`inflow-fusion`](https://github.com/Inflowenger/inflow-fusion) | SDK | The Go SDK: `InitBackend`, the `IInflowService` contract, typed node builders, `svcHandler`, scoped credentials, and the Vue Flow compiler. |
| `go-plugin-sdk` · `node-plugin-sdk` | SDK | Build a plugin against the `inflowv1` protocol — actions, meta methods, settings forms, live progress. Go and Node/TypeScript, wire-identical: pick the language, not a different protocol. |
| `inflow-inspector` + `inspector-api` | reference | The low-level developer panel: edit raw primitives, inspect contexts and running processes. The worked example of consuming the SDK. |
| `flomorphic-api` (`morph-api`) | product | FloMorphic's backend: Go 1.26 + Fiber v3, SQLite + `sqlite-vec` via sqlc, the Vue Flow → primitive compiler, and the `svc.*` handlers backing store / HITL / continue nodes. |
| `flomorphic-wapp` | product | The canvas: Vue 3 + Vite + TypeScript + Vue Flow + Tailwind v4 + Pinia. Runs standalone (browser-local) or connected. |
| [`builtin-plugins`](https://github.com/FloMorphic/builtin-plugins) | product | The `llm` and `mcp` plugin node binaries. |
| [`Inflowenger/getting-started`](https://github.com/Inflowenger/getting-started) | ops | Installer for the platform (Infra + Fractal) and the inspector panel. |
| **this repo** | ops | Installer and developer tooling for the *FloMorphic* stack. |

---

## Contributing

FloMorphic is deliberately open at the seams that matter: the palette is data plus
a compiler hook, the AI nodes are ordinary plugins with no privileged access, the
backend is storage-agnostic, and nothing in the runtime is reserved for FloMorphic
that another product could not use.

Contributions are welcome — node kinds, plugin nodes, storage drivers, docs, and
installer coverage for more platforms. Open an issue before a large change: the
APIs are still pre-1.0 and moving.

## License

Apache License 2.0 — see [LICENSE](./LICENSE) and [NOTICE](./NOTICE). The component
repositories carry the same licence. "Inflowenger" and "FloMorphic" are trademarks;
Apache-2.0 does not grant permission to use them beyond describing this work's
origin.

---

<div align="center">
<sub>Part of the Inflowenger platform · Where context becomes computation.</sub>
</div>
