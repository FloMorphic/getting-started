# Architecture & deployment

How the processes talk to each other, how the graph reaches into a system you
already run, how the same artifact scales from a laptop to a cluster, and why the
installed stack ships as a single container.

**See also:** [Concepts](./concepts.md) · [Node palette](./nodes.md) ·
[AI harness](./ai-harness.md) · [Developing from source](./development.md) ·
[back to README](../README.md)

---

## How the pieces talk

```
 ┌────────────────────┐   REST: creds, accounts, resources   ┌────────────────────────┐
 │  Infra             │◄────────────────────────────────────►│  flomorphic-api        │
 │  control plane     │                                      │  imports inflow-fusion │
 │  NATS :4222        │   NATS: get flow / get,set context   │  implements the        │
 │  API  :8022        │◄────────────────────────────────────►│  backend contract      │
 └─────────┬──────────┘                                      └───────────┬────────────┘
           │ registered engines                                          │ :8025 HTTP + WS
           ▼                                                             ▼
 ┌────────────────────┐   NATS: flow + context, svc.* calls   ┌────────────────────────┐
 │  Fractal (engine)  │──────────────────────────────────────►│  flomorphic-wapp       │
 │  walks the graph   │                                       │  the canvas (browser)  │
 └─────────┬──────────┘                                       └────────────────────────┘
           │ NATS on an isolated, scoped plugin account
           ▼
 ┌────────────────────────────────────┐
 │  Plugin nodes:  llm  ·  mcp  ·  …  │
 └────────────────────────────────────┘
```

The backend never executes a flow. It answers questions and runs the bits of
domain logic a node calls out to. Fractal does the traversal. Plugins live on
their own isolated accounts.

---

## Meeting the system you already run

This is the part that separates FloMorphic from a canvas you would evaluate and
then abandon: **you do not have to move anything into it.**

Most AI tooling asks you to bring your data and your logic to it. FloMorphic goes
the other way — the graph reaches into what you already have, over subjects your
own services own. Three doors, and you can use all three at once:

| Door | Mechanism | When it fits |
| --- | --- | --- |
| **Extrinsic** | Your Go backend imports `inflow-fusion` and registers handlers with `svcHandler.ImplHandlerOnSubject`. A flow node publishes to that subject; **your handler's reply becomes the node's output.** | Your backend is Go, or you can put a thin Go service in front of it. The cheapest door — a handful of lines, no new process. |
| **Plugin** | A standalone process speaking `inflowv1`, built with the **Go** or **Node/TypeScript** SDK — wire-identical, so pick the language, not a different protocol. It appears on the canvas as a node with its own configuration form. | Anything else: a REST API, a database, a message bus, a mainframe gateway, a vendor system. The SDKs' own worked example is an HTTP call node. |
| **MCP** | The MCP node, as a client. | The system already speaks MCP, or you can put an MCP server in front of it. |

One registration can serve many logical services: `svc.add.issue.{TABLE_NAME}`
subscribes as a wildcard, and the handler recovers the concrete parameter from the
subject the message arrived on. One handler, one door, many capabilities on the
canvas.

### What this actually buys a legacy system

The order matters. You are not replacing the system — you are giving it a new
outer layer:

1. **Nothing moves.** The database stays. The services stay. The deployment stays.
2. **Expose what already exists.** A few subject registrations turn existing
   business operations into nodes, without changing what those operations do.
3. **Draw the new behaviour above them.** Retrieval, model calls, policy checks,
   approvals and scheduling get composed *on top* of capabilities that were already
   proven in production.
4. **The domain expert takes the pen.** Because behaviour is a graph, not code,
   changing it stops requiring a release.

The legacy system does not become AI-native by being rewritten. It becomes
AI-native by being **reachable**.

---

## Plugins: the open end

Everything above is reachable without writing runtime code. When you do need
something the primitives can't express, you write a **plugin** — a standalone
process that speaks the `inflowv1` protocol via the **Go** or **Node/TypeScript**
SDK, gets narrowly-scoped NATS credentials (it can only publish and subscribe on
subjects it owns), and shows up in the palette as a node with its own configuration
form, live progress feedback, and read/write access to the flow's context.

FloMorphic's own LLM and MCP nodes are exactly this. They are not built into the
runtime — they are two independent Go modules in
[`builtin-plugins`](https://github.com/FloMorphic/builtin-plugins), each a plain
binary, each pinning its own SDK version, sharing nothing at build time. That is
the whole point: the AI capability of the product is an ordinary plugin, so
*anything else you need can be one too.*

---

## From a laptop to a cluster

The same artifact runs at every size. Nothing about the workflow changes as the
deployment grows — only how many processors are attached.

| Stage | What is running | Notes |
| --- | --- | --- |
| **Standalone** | The canvas alone, or the canvas + API with the runtime disabled | The web app persists to browser storage with no backend at all; the API runs CRUD-only when `INFLOW_INFRA_API` is unset. Enough to design, save and review real workflows on a plane. |
| **Single box** | Infra + one Fractal + the API + the canvas | One `docker compose` network. SQLite is a file. This is a complete, executing system. |
| **Scaled out** | Infra + **many** Fractals | Fractals register themselves with Infra; `inflow-fusion` keeps a round-robin pool of registered engines and load-balances each new process across them. Fractals carry **tags**, so work can be steered to the right class of processor. |

Scaling is adding processors, not re-architecting. The graph, the context model and
the node semantics are identical at every stage — which means the prototype you
drew on day one is the thing that runs in production, not a sketch of it.

---

## One container, on purpose

The installed stack puts the canvas, the API and the plugin nodes in **one image**:

```
     browser ──► :8090 ─── nginx ──┬── /            the canvas (static SPA)
                                   ├── /api/*  ───► flomorphic-api  :8025
                                   └── /ws/*   ───►      "          (log stream)
                                                          │
                                            NATS ◄────────┤  llm plugin node
                                     (Infra :4222) ◄──────┘  mcp plugin node
```

Two reasons, both structural rather than cosmetic:

- **The canvas bakes its backend URL at build time.** Baking a host name would tie
  one image to one machine and drag CORS in with it. Instead the SPA is built with
  a *relative* base (`/api`) and nginx routes it, so every request is same-origin.
  One port to publish, and the same image works on a laptop, a LAN box or a server.
- **A plugin node cannot start before the API does.** Each one needs a NATS
  credential on the builtin-plugins account, and the component that mints it is
  `flomorphic-api` itself (`POST /extension/plugin/cred`). So the container's
  entrypoint starts the API, waits for `/health`, mints **one** multi-access
  credential, clones the plugin repo, and runs every plugin folder in it with that
  credential — each under the `PLUGIN_ID` the API's seed assigns to its builtin
  node, so saved workflows keep resolving across reinstalls. Adding a plugin to
  [`builtin-plugins`](https://github.com/FloMorphic/builtin-plugins) is enough; no
  image change is needed.

Point `PLUGINS_REPO` / `PLUGINS_REF` somewhere else to run your own set, or
`PLUGINS_ENABLED=0` to run the canvas without any.

### The two images

| | What it does | When |
| --- | --- | --- |
| **self-building** (published, the default) | ships only tooling and clones + compiles morph-api and morph-wapp at container **start**, native to your CPU | first start takes a few minutes and needs network; one manifest serves amd64 and arm64 |
| **baked** (`install.sh --build`) | compiles everything at image-build time | starts in seconds; what CI publishes per-arch |

Both are driven by the same entrypoint and the same env vars — only the moment of
compilation differs. `/src` holds the checkout, the Go module cache and the pnpm
store, so restarts skip the work. `API_REF` / `WAPP_REF` / `PLUGINS_REF` in
`flomorphic/.env` pick the branch or tag each source is built from; pin release
tags for reproducible restarts.

Dockerfiles: [`docker/Dockerfile.flomorphic-src`](../docker/Dockerfile.flomorphic-src)
(self-building) and [`docker/Dockerfile.flomorphic`](../docker/Dockerfile.flomorphic)
(baked). Each component repo also carries its own Dockerfile — `flomorphic-api`
(API + plugin nodes) and `flomorphic-wapp` (canvas + proxy) — for a split
deployment or a CI pipeline that publishes them separately.
