# Node palette

FloMorphic's canvas ships thirteen nodes, grouped by intent. Every one is
annotated with the [runtime primitive](./concepts.md#the-claim-a-handful-of-primitives-spans-everything)
it lowers to — that annotation is visible in the product, not hidden in the
compiler.

**See also:** [Concepts](./concepts.md) · [AI harness](./ai-harness.md) ·
[Architecture & deployment](./architecture.md) · [back to README](../README.md)

---

## Flow

| Node | Lowers to | What it does |
| --- | --- | --- |
| **Start** | `Void` | The entry marker. Exactly one per flow. |
| **Wait for All** | `Void` | A synchronisation barrier — `Promise.all` for branches. When a node fans out, the runtime runs every branch in parallel; this holds until all inbound branches finish, merges their results into the shared context, and continues once. |
| **Continue After** | `Extrinsic · svc.continue.at` | Park the run and resume it later — `now + delay`, or an absolute time. The captured outbound nodes are re-launched when the clock says so. |
| **Goto** | `GoTo` | Jump into another (or the same) flow like a subroutine, and come back. Composition and reuse. |

## AI & Logic

| Node | Lowers to | What it does |
| --- | --- | --- |
| **LLM** | `Plugin` | One turn of a model conversation held on the node's scope, streamed to the canvas. Provider config comes from a settings profile; the prompt template lives on the node. **Bound functions become output ports.** |
| **MCP** | `Plugin` | An MCP *client*. "Tool only" calls a single tool with typed arguments, no model involved. "With LLM" drives a model bound to the server's tools and runs the agentic loop internally. |
| **Rule** | `Contract` | Evaluate JS or OPA/Rego over the scoped context; each handler is a tagged output port. The branching, policy and guardrail node. |
| **JS** | `Code · js` | A JavaScript step over the scoped context, result written to `key`. |
| **OPA** | `Code · opa` | A Rego policy over the scope (as `input`) plus condition key/values (as `data`). |

## Stores

| Node | Lowers to | What it does |
| --- | --- | --- |
| **Doc Store** | `Extrinsic · svc.store.doc.*` | Read (a validated read-only query) or write documents in a referenced **Document** memory store. |
| **Vector Store** | `Extrinsic · svc.store.vec.*` | Index or search a referenced **Vector** memory store — embedding text, top-k neighbours, optional partition namespace. |
| **Cast / Mapping** | `Plugin` | Build a value by mapping each target key of a store's schema to a static value or a JSONPath resolved at run time. |

## Human

| Node | Lowers to | What it does |
| --- | --- | --- |
| **Human in the Loop** | `Extrinsic · svc.hitl.add` | Pause the flow for a person. Poses questions, records a Human Task, and resumes when the answers arrive (or a human closes it). |

---

## The three universal fields

Every node — regardless of kind — shares three fields that are mirrored onto the
compiled primitive:

| Field | Meaning |
| --- | --- |
| **title** | Human label |
| **key** | Where this node's output is written into the context |
| **scope** | The JSONPath slice of context this node reads and writes |

---

## Around the canvas

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

## Adding a node kind

The palette is data plus a hook: a catalog entry on the frontend and a case in the
compiler — not a runtime change. If the behaviour you need is not expressible with
the compiled primitives, it becomes a
[plugin node](./architecture.md#plugins-the-open-end) instead, built against the
Go or Node/TypeScript SDK.
