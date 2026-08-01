# The AI harness

FloMorphic treats AI as a *capability inside* the execution model rather than the
centre of it. The system is useful with no model in it at all, and increasingly
powerful with one. Four mechanisms carry most of that weight — and none of them
required a runtime feature invented for AI.

**See also:** [Concepts](./concepts.md) · [Node palette](./nodes.md) ·
[Architecture & deployment](./architecture.md) · [back to README](../README.md)

---

## 1. Virtual functions — the model routes the diagram

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

## 2. Context — runtime memory

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

## 3. Doc store + vector store — long-term memory

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

## 4. Out-of-model reasoning

A **Rule** node evaluates JavaScript or an OPA/Rego policy against the context and
routes by tag. Put one after an LLM node and you have deterministic, auditable
control over what the model produced — before anything downstream sees it.

That is the pattern the platform is built around: **the model proposes; the graph
decides.** Validation, guardrails, retry policy, escalation thresholds, and cost
ceilings are all ordinary nodes, evaluated outside the model, visible on the
canvas, and changeable without redeploying anything.

---

## Loops are not a node — by design

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

## One substrate for the whole vocabulary

The concept map — the ideas the market treats as separate products, and the single
mechanism each one becomes here:

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
feature invented for them. They are consequences of
[six primitives](./concepts.md#the-claim-a-handful-of-primitives-spans-everything),
a shared context, and a compiler seam.
