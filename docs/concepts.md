# Concepts — the execution model

How FloMorphic actually works, from the bottom up: the three layers, the six
runtime primitives everything compiles to, and the seam between the canvas you
draw on and the engine that runs it.

> **Context is the memory. Workflows are the logic. Fractals are the processors.**

**See also:** [AI harness](./ai-harness.md) · [Node palette](./nodes.md) ·
[Architecture & deployment](./architecture.md) · [back to README](../README.md)

---

## The three layers

FloMorphic is not one program. It is a stack of layers — a headless runtime, a Go
SDK that binds a backend into it, a product API, a canvas frontend, and a set of
plugin node binaries.

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

## Where this goes next

- The thirteen canvas nodes and what each one lowers to → [Node palette](./nodes.md)
- Why the AI capabilities need no runtime support → [AI harness](./ai-harness.md)
- How the processes talk, and how to attach an existing system →
  [Architecture & deployment](./architecture.md)
