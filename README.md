<div align="center">

# FloMorphic — Getting Started

**The open-source AI harness, built on the Inflowenger context runtime.**

The install path, the developer tooling, and the layered documentation for
FloMorphic — the first product built end-to-end on [Inflowenger](https://inflowenger.dev).

`Inflowenger` · `inflow-fusion` · `FloMorphic API` · `FloMorphic Web App` · `Builtin plugin nodes`

</div>

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

---

## Where the market is, and what it leaves open

The AI tooling landscape is not short of good work. It is short of a *substrate*.
Three categories dominate, each excellent at what it set out to do, and each
carrying one structural constraint:

| Category | Examples of the shape | What it does very well | The structural constraint |
| --- | --- | --- | --- |
| **Code-first agent frameworks** | agent/graph SDKs, orchestration libraries, RAG toolkits — well funded, large communities, genuinely deep | Expressive power, fast iteration for engineers, a rich ecosystem of integrations and patterns | The logic is **code inside an application**. Changing what the system does means a developer, a review and a deploy. The people who understand the domain cannot own the behaviour. |
| **No-code automation & hosted agent builders** | visual automation platforms and vendor agent studios | Accessibility, speed to first result, a large catalogue of connectors | They run **beside** your system as an external service. Your logic — often your data — lives in someone else's control plane, and depth of state, policy and scale is bounded by what the vendor exposes. |
| **Durable workflow & BPM engines** | workflow runtimes and process engines used in the enterprise | Real durability, real scale, real operational maturity | **Not AI-native, and developer-only.** AI arrives as an integration, not as part of the execution model. |

Each solves a real problem. None of them is simultaneously *all three* of the
things a team modernising a real system actually needs:

1. **Operator-editable** — a domain expert changes behaviour without a deploy.
2. **A runtime you own** — self-hosted, inspectable, scalable, no vendor holding
   the control plane.
3. **Attachable to what already exists** — it extends the running system instead of
   replacing it.

**That intersection is the hole.** It is where FloMorphic sits: the AI-native
upgrade path for systems that are already in production — and the substrate for new
ones that intend to stay yours.

---

## What this repository is

FloMorphic is not one program. It is a **stack of layers** — a headless runtime, a
Go SDK that binds a backend into it, a product API, a canvas frontend, and a set of
plugin node binaries — each of which has its own repository and its own README.

That is a lot of surface for someone who just wants to *run the thing*. This
repository is the entry point:

- **One install path** — scripts that stand up the whole stack (Inflowenger platform
  + FloMorphic API + web app + builtin plugin nodes) instead of five separate setups.
- **Developer tools** — the helpers you need when you want to change FloMorphic
  rather than only use it: local wiring, plugin scaffolding, resets, and smoke checks.
- **A documentation map** — one place that tells you which layer answers your
  question, and links into the deep docs that live with the code.

Start here. Read the concepts below, run the installer, then follow the map into
whichever layer you need.

> **Status.** The concept and the map are complete and current. The installer and
> developer tooling are being assembled in this repo now — see
> [Roadmap of this repo](#roadmap-of-this-repo). Until they land, the manual paths in
> each component's own README are the source of truth.

---

## The three layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│  LAYER 3 — PRODUCT                                                       │
│  FloMorphic  ·  flomorphic-wapp (canvas) + flomorphic-api (Go backend)    │
│  Intent-level nodes: LLM · MCP · Rule · Stores · Human-in-the-loop        │
└───────────────────────────────────┬──────────────────────────────────────┘
                                    │  compiles down to
┌───────────────────────────────────▼──────────────────────────────────────┐
│  LAYER 2 — SDK & REFERENCE                                               │
│  inflow-fusion (Go SDK)  ·  inflow-inspector (+ inspector-api)           │
│  Six primitives · the compiler seam · the backend contract               │
└───────────────────────────────────┬──────────────────────────────────────┘
                                    │  executed by
┌───────────────────────────────────▼──────────────────────────────────────┐
│  LAYER 1 — RUNTIME (headless)                                            │
│  Infra (coordination, NATS, credentials)  ·  Fractal (execution engine)  │
└──────────────────────────────────────────────────────────────────────────┘
```

**Layer 1 — Inflowenger.** A workflow *runtime and infrastructure*, and nothing
else. Infra bootstraps the ecosystem: it runs an embedded NATS server, mints
accounts and credentials, and coordinates. Fractal is the processor — it fetches a
compiled workflow graph and walks it. Both are headless by design: they have no
opinion about your domain, no UI, and no data of their own.

**Layer 2 — `inflow-fusion` and the inspector.** `inflow-fusion` is the Go SDK you
import into your own backend so that backend can participate: answer the engine's
questions (*what is this flow? what is this run's context?*), expose your domain
logic as callable steps, and start or stop runs. `inflow-inspector` (with
`inspector-api`) is the reference consumer — the system built *under*
`inflow-fusion` to show a developer exactly how the runtime is used. It edits the
raw primitives directly, so it doubles as the low-level workbench.

**Layer 3 — FloMorphic.** The product layer, and the AI harness. Its nodes speak
the language of what you are *building* — a model call, an MCP client, a
retriever, a policy gate, an approval — and each one records which primitive(s) it
lowers to at compile time. This is the proof of the platform's central claim: a
real, non-trivial AI product with nothing special reserved for it in the runtime.

> **Context is the memory. Workflows are the logic. Fractals are the processors.**

---

## The claim: a handful of primitives spans everything

The runtime ships exactly **six** node types. Every higher-level node any product
could want compiles down to one of them.

| Primitive | Role | Compiles away? |
| --- | --- | --- |
| **Void** | Structure — start markers, joins, barriers, dead ends | yes |
| **Code** | Computation — run JS or OPA/Rego against scoped context | yes |
| **Contract** | Decision — evaluate a rule, emit tags, fire matching branches | yes |
| **Extrinsic** | Call a service *you* own, over one NATS request/reply subject | yes |
| **Plugin** | A live external process — the open-ended escape hatch | **no** |
| **GoTo** | Composition — jump into another flow and return | yes |

Five of the six are compiled artifacts. **Plugin is the exception**: it never
compiles away, because it is a real, long-lived process with its own connections,
its own background loops, and its own configuration UI. That is why it is the
richest node in the system — and why an LLM, an MCP client, and a field-mapper can
all be plugin nodes without the runtime knowing what any of them mean.

The design argument for why this set is *closed*:

| Axis | Covered by |
| --- | --- |
| Arbitrary computation | **Code** (JS / OPA over the scoped context) |
| Decision & control flow | **Contract** (tagged branching), **GoTo** (reuse), **Void** (structure) |
| Reaching your own system | **Extrinsic** (one request/reply subject into your backend) |
| Reaching the outside world | **Plugin** (a live process — anything the compiled set can't do) |

Those four axes span what a workflow builder needs. Nothing else has to be a
primitive.

### Branching is one node

A node with one output is a linear step. A node with N labelled outputs is a
**Contract**: its rule returns a list of *tags*, and the engine follows only the
transitions whose tags match. "Success / retry / reject" is not three node types —
it is one Contract with three tagged handlers.

---

## From canvas to execution

Nothing a designer draws reaches the engine. The engine only ever executes a flat
map of primitive nodes. A compiler sits in between.

```
  Author  ──►  Save  ──►  Compile  ──►  Execute
  drag &      the raw     a per-node    a Fractal fetches the
  configure   graph is    hook lowers   node map and walks it,
  nodes on    persisted   each node to  asking your backend for
  a canvas    verbatim    a primitive;  flows and context as
              (view_flow) edges become  it goes
                          transitions
```

The **hook** is the only place product-specific knowledge lives. Your node types
are your frontend's convention; the hook declares which primitive each one means.
In FloMorphic that hook is
[`inflow/compiler.go` + `inflow/node_builders.go`](https://github.com/FloMorphic/morph-api)
in the API, walking a Vue Flow graph via `inflow-fusion`'s `compilers/vueFlow`.

This seam is what makes the primitives claim real rather than rhetorical: two
completely different products can put completely different palettes on the same
runtime, and neither needs a runtime change.

---

## FloMorphic's palette

Thirteen canvas nodes, grouped by intent. Every one is annotated with the
primitive it lowers to — that annotation is visible in the product, not hidden in
the compiler.

### Flow

| Node | Lowers to | What it does |
| --- | --- | --- |
| **Start** | `Void` | The entry marker. Exactly one per flow. |
| **Wait for All** | `Void` | A synchronisation barrier — `Promise.all` for branches. When a node fans out, the runtime runs every branch in parallel; this holds until all inbound branches finish, merges their results into the shared context, and continues once. |
| **Continue After** | `Extrinsic · svc.continue.at` | Park the run and resume it later — `now + delay`, or an absolute time. The captured outbound nodes are re-launched when the clock says so. |
| **Goto** | `GoTo` | Jump into another (or the same) flow like a subroutine, and come back. Composition and reuse. |

### AI & Logic

| Node | Lowers to | What it does |
| --- | --- | --- |
| **LLM** | `Plugin` | One turn of a model conversation held on the node's scope, streamed to the canvas. Provider config comes from a settings profile; the prompt template lives on the node. **Bound functions become output ports.** |
| **MCP** | `Plugin` | An MCP *client*. "Tool only" calls a single tool with typed arguments, no model involved. "With LLM" drives a model bound to the server's tools and runs the agentic loop internally. |
| **Rule** | `Contract` | Evaluate JS or OPA/Rego over the scoped context; each handler is a tagged output port. The branching, policy and guardrail node. |
| **JS** | `Code · js` | A JavaScript step over the scoped context, result written to `key`. |
| **OPA** | `Code · opa` | A Rego policy over the scope (as `input`) plus condition key/values (as `data`). |

### Stores

| Node | Lowers to | What it does |
| --- | --- | --- |
| **Doc Store** | `Extrinsic · svc.store.doc.*` | Read (a validated read-only query) or write documents in a referenced **Document** memory store. |
| **Vector Store** | `Extrinsic · svc.store.vec.*` | Index or search a referenced **Vector** memory store — embedding text, top-k neighbours, optional partition namespace. |
| **Cast / Mapping** | `Plugin` | Build a value by mapping each target key of a store's schema to a static value or a JSONPath resolved at run time. |

### Human

| Node | Lowers to | What it does |
| --- | --- | --- |
| **Human in the Loop** | `Extrinsic · svc.hitl.add` | Pause the flow for a person. Poses questions, records a Human Task, and resumes when the answers arrive (or a human closes it). |

Every node — regardless of kind — shares three universal fields that are mirrored
onto the compiled primitive:

| Field | Meaning |
| --- | --- |
| **title** | Human label |
| **key** | Where this node's output is written into the context |
| **scope** | The JSONPath slice of context this node reads and writes |

### Around the canvas

The graph is not the whole product. FloMorphic also ships the entities a real
system needs beside it:

| Section | What it holds |
| --- | --- |
| **Contexts** | The run documents themselves — listed, opened, edited as a tree or raw JSON. |
| **Memory** | Vector and Document store definitions, and a browser for the data inside them. |
| **Prompts** | A reusable prompt-template library with `{{var}}` placeholders and declared variables. |
| **Node settings** | Named configuration profiles bound to a node kind — e.g. one LLM provider profile per environment — referenced by id from a canvas node, so credentials never live on the graph. |
| **Processes** | Every run: status, duration, error, and a jump to the context it carried. |
| **Human tasks** | The queue the HITL node feeds — open, answer, or close. |
| **Extensions** | Register a plugin from a Git repo; the backend runs it so it joins the ecosystem and contributes nodes to the palette. |

---

## The AI-native parts, in detail

FloMorphic treats AI as a *capability inside* the execution model rather than the
centre of it. The system is useful with no model in it at all, and increasingly
powerful with one. Four mechanisms carry most of that weight.

### 1. Virtual functions — the model routes the diagram

The LLM node's **bound functions are outbound ports on the canvas**. You declare a
function (`approve`, `escalate`, `search_docs`), and it renders as a port you can
wire an edge from.

At run time the plugin sends those functions to the model as tools. When the model
answers with a tool call, the plugin calls `CmdNextFilter([name])` and the runtime
fires **only the matching port(s)**. No tool call means the flow follows its
default route.

The consequence is the interesting part: **the model's decision is a visible edge
in the diagram, not a hidden branch inside an agent's head.** You can see every
route the model is allowed to take, and everything downstream of each one, before
it ever runs. The "function" never has to be implemented as a function — it is a
routing tag whose implementation is whatever you draw after it.

Providers run through langchaingo: OpenAI, OpenRouter (one key, 300+ models),
any OpenAI-compatible endpoint (Ollama, vLLM, Groq, Together, DeepSeek, …), Google
Gemini, and Anthropic. `provider` is the only field that picks the backend.

### 2. Context — runtime memory

Every run carries a **Context**: a live JSON document that *is* the working memory
of the process. Nodes read a `scope` of it, write their result to a `key` in it,
and the engine persists mutations back through your backend
(`RetrieveContext` / `UpdateContext`). It is versioned, inspectable, and stored as
a first-class entity you can list and open.

This replaces the ad-hoc "state dict" that agent frameworks thread through
callbacks. Context is not a convention — it is the substrate, and the runtime's
job is to move it through the graph.

The LLM node's conversation lives here too. The prompt template seeds the messages
on the **first** run; once the scope carries a `messages` array, the template is
ignored and the persisted conversation is used as-is. That single rule is what
makes loops work.

### 3. Doc store + vector store — long-term memory

Contexts are per-run. **Memory stores** are not.

- A **Document store** declares a table and column schema and holds structured
  documents you can query.
- A **Vector store** declares an embedding model, dimensions and a distance
  metric; creating one provisions a `sqlite-vec` `vec0` index sized to it.

The Doc Store and Vector Store nodes reference one by id and compile to Extrinsic
calls into the FloMorphic backend, which resolves the store **server-side** — the
request never gets to choose which table it touches. Retrieval-augmented generation
is not a framework here; it is a Vector Store read node wired into an LLM node's
scope.

### 4. Out-of-model reasoning

A **Rule** node evaluates JavaScript or an OPA/Rego policy against the context and
routes by tag. Put one after an LLM node and you have deterministic, auditable
control over what the model produced — before anything downstream sees it.

That is the pattern the platform is built around: **the model proposes; the graph
decides.** Validation, guardrails, retry policy, escalation thresholds, and cost
ceilings are all ordinary nodes, evaluated outside the model, visible on the
canvas, and changeable without redeploying anything.

### Loops are not a node — by design

There is no Loop node in the palette. A loop is not a primitive; it *emerges from
connections*:

```
   ┌──────────────────────────────────────────────┐
   │                                              │
   ▼                                              │
[ LLM ] ──► [ Rule: is the task satisfied? ] ─────┘   (no)
                     │
                     └──► (yes) ──► [ next step ]
```

The LLM node appends to the message stack on the context. The Rule node checks
whether the task is done. If not, an edge routes back to the LLM. That cycle *is*
the loop — with every iteration observable, every exit condition explicit, and a
Human-in-the-Loop node insertable anywhere in it.

Agent loops, planning systems, self-review cycles, approval chains, and data-quality
passes are all this same shape.

---

## The harness: one substrate for the whole vocabulary

Here is the concept map — the ideas the market treats as separate products, and
the single mechanism each one becomes here:

| The concept | In FloMorphic it is… | Which is really… |
| --- | --- | --- |
| **RAG** | a Vector Store read node wired into an LLM node's scope | retrieval as a step in the graph, not a pipeline library |
| **Context engineering** | `scope` + `key` on every node | an explicit, per-node contract for what the model may see and what it may write — enforced by the runtime, not by prompt discipline |
| **Working / short-term memory** | the run's Context document | one live JSON document the whole flow reads and mutates |
| **Long-term memory** | Document stores and Vector stores | first-class entities with their own schema and index, resolved server-side |
| **Tool use** | virtual functions on the LLM node | a routing tag that fires an outbound port — the "tool" is whatever you draw after it |
| **Agent loop** | an LLM node and a Rule node with an edge between them | iteration as topology; every pass observable, every exit condition explicit |
| **Planning / self-review** | the same cycle with a different Rule | no new mechanism needed |
| **Multi-agent orchestration** | sub-flows via GoTo, parallel branches, Wait for All | real concurrency and barriers in the runtime, not a loop in one process |
| **MCP** | the MCP node — tool-only or model-driven | a client node, with the server's tools loaded into the editor |
| **Guardrails** | a Rule (Contract) node before or after the model | deterministic policy in JS or Rego, evaluated outside the model |
| **Out-of-model reasoning** | Rule, OPA, JS nodes on the graph | the model proposes; the graph decides |
| **Human-in-the-loop** | the HITL node | a run that parks on a real Human Task and resumes on the answer |
| **Observability** | the live process event stream + the process list + persisted contexts | every event the engine emits, streamed to the canvas over a WebSocket and traced back onto the nodes and edges that produced it |
| **Scheduling / long-running work** | Continue After | resumption is an execution primitive, not a queue you operate |

The row that matters most is the last column: none of these needed a runtime
feature invented for them. They are consequences of six primitives, a shared
context, and a compiler seam.

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

## Not a product — an opportunity

FloMorphic is not sold to you as the finished answer. It is the means to build
your own, and it is deliberately shaped so that what you build can be as much a
product as FloMorphic is.

| If you are… | What is actually on offer |
| --- | --- |
| **An organisation with a system in production** | An AI-native upgrade path that does not begin with a rewrite, does not hand your logic to a vendor, and does not require hiring a team of framework specialists to maintain. |
| **A team or consultancy building for others** | A substrate to build a *vertical* product on — logistics, claims, compliance, support, back-office. FloMorphic is the existence proof: nothing in the runtime is reserved for it, so your palette gets the same treatment its palette gets. |
| **A developer** | Six primitives, a compiler seam, two plugin SDKs, and a runtime that stays out of your way. Extend the palette, add a storage driver, write a node — none of it requires permission from the runtime. |
| **A domain expert** | The behaviour of the system, in a form you can read and change, with the model's every permitted decision drawn as an edge you can see. |

The comparison that matters is not feature-by-feature against any one tool. It is
this: **everything is one substrate.** The retrieval, the model call, the policy
check, the human approval, the scheduled resume and the call into the system you
already run are nodes in the same graph, over the same context, watched through the
same event stream. That is the thing no combination of the three categories above
gives you, because it is not a feature — it is an architecture.

### Plugins: the open end

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

### How the pieces talk

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

## Roadmap of this repo

What lands here, in order:

- [ ] **`install.sh`** — one prompt-driven script: platform (Infra + Fractal),
      FloMorphic API + web app, and the builtin plugin nodes, on a shared Docker
      network. Env-var drivable for unattended installs, in the shape of the
      [platform installer](https://github.com/Inflowenger/getting-started).
- [ ] **Compose stacks** — the real `docker compose` files the script writes, so
      you manage the result by hand afterwards.
- [ ] **Developer tools** — local dev wiring (API + Vite + plugins against a running
      platform), plugin scaffolding, database/context resets, and a smoke check that
      runs a known flow end to end.
- [ ] **Layered docs** — the map below, filled in with a walkthrough per layer:
      *use it* → *extend it with a plugin* → *build your own product on the runtime*.

Until these land, use each component's own README — they are current and complete.

### Meanwhile: running from source

```bash
# 1. Platform (Infra + Fractal) — see Inflowenger/getting-started
curl -fsSL https://raw.githubusercontent.com/Inflowenger/getting-started/main/install.sh | bash

# 2. FloMorphic API   (Go 1.26+, cgo)
cd flomorphic-api && cp .env.example .env && make run       # :8025

# 3. FloMorphic canvas
cd flomorphic-wapp && pnpm install && cp .env.example .env  # VITE_API_BASE_URL=http://localhost:8025
pnpm dev

# 4. Builtin plugin nodes
cd builtin-plugins/llm && go build -o bin/llm . && ./bin/llm
cd builtin-plugins/mcp && go build -o bin/mcp . && ./bin/mcp
```

The API's inflow runtime is **optional**: leave `INFLOW_INFRA_API` unset and it
runs CRUD-only, which is enough to design and save workflows. Set it, and `Run`
goes live.

| Service | Default port |
| --- | --- |
| Infra API | `8022` |
| NATS | `4222` (monitoring `8222`) |
| FloMorphic API | `8025` |
| FloMorphic canvas (dev) | `5173` |

---

## Documentation map

Which layer answers your question:

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

## Open source

FloMorphic is open source, and deliberately open at the seams that matter:

- **The palette is data plus a hook.** Adding a node kind is a catalog entry on the
  frontend and a case in the compiler — not a runtime change. Fork the palette,
  keep the runtime.
- **The AI nodes are ordinary plugins.** `llm` and `mcp` are two standalone Go
  binaries with no privileged access. Whatever you build gets the same contract
  they do.
- **The backend is storage-agnostic.** Controllers depend only on the repository
  interfaces; SQLite is one registered driver, and another is a new package plus
  an `init()`.
- **Nothing is reserved.** FloMorphic uses exactly the primitives, subjects and
  credentials any other product on Inflowenger would.

Contributions are welcome — node kinds, plugin nodes, storage drivers, docs, and
installer coverage for more platforms. Open an issue before a large change: the
APIs are still pre-1.0 and moving.

> **Licensing.** Per-repository `LICENSE` files are being finalised as the projects
> are published. Until a `LICENSE` file is present in a given repository, do not
> assume a permissive licence for that component.

---

<div align="center">
<sub>Part of the Inflowenger platform · Where context becomes computation.</sub>
</div>
