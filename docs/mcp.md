# FloMorphic over MCP

The FloMorphic API is itself an **MCP server**. Every entity a person edits on the
canvas — workflows, contexts, prompts, memory stores, triggers, human tasks, runs —
is exposed as an [MCP](https://modelcontextprotocol.io) tool, so an AI client
(Claude Desktop, Claude Code, Cursor, or anything that speaks MCP) can *drive
FloMorphic directly*: design a workflow, save it, run it, read back what it
produced, search a vector store, answer a human task — all over the same call path
the web app uses.

It is not a separate process. The server is embedded in the API and mounted at
**`/mcp`** as a [Streamable HTTP](https://modelcontextprotocol.io/specification/basic/transports)
endpoint. Every tool is a thin wrapper over the exact code a REST handler runs, so
an MCP write is indistinguishable from a web-app write — no logic is duplicated,
nothing is second-class.

- **Endpoint** — `http://localhost:8026/mcp` on an installed stack
  (`http://localhost:8025/mcp` when you run the API [from source](./development.md)).
- **On by default** — the API mounts `/mcp` unless you set `MCP_ENABLED=false`.
- **Auth follows the API** — off by default (fine on localhost); when
  `AUTH_ENABLED=true`, `/mcp` sits behind the same bearer token as every CRUD
  route. See [Authentication](#authentication).

---

## Connect a client

The endpoint is a standard Streamable-HTTP MCP server, so any compliant client can
use it. The three most common are below.

### Claude Desktop

Claude Desktop has **two** ways in. Pick whichever your version offers.

**A. Custom connector (native, recommended).** On Pro/Max/Team/Enterprise plans,
Claude Desktop connects to a remote MCP server by URL — no bridge, no terminal.

1. **Settings → Connectors → Add custom connector**.
2. Name it `FloMorphic`, URL `http://localhost:8026/mcp`.
3. Save, then enable it in the chat's tool/connector menu.

That is the whole setup when auth is off. If `AUTH_ENABLED=true`, the connector
dialog has an **Authorization / bearer token** field — paste the token from
[Authentication](#authentication) there.

**B. `mcp-remote` bridge (any plan).** If your build only shows the classic
`command`-based server list, bridge the HTTP endpoint through the
[`mcp-remote`](https://www.npmjs.com/package/mcp-remote) helper. Edit the config
file:

- macOS — `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows — `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "flomorphic": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:8026/mcp"]
    }
  }
}
```

Restart Claude Desktop; `flomorphic` appears in the tool menu. Needs Node.js on
`PATH` (`npx` ships with it). With auth on, add the header:

```json
{
  "mcpServers": {
    "flomorphic": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote", "http://localhost:8026/mcp",
        "--header", "Authorization: Bearer ${FLOMORPHIC_TOKEN}"
      ],
      "env": { "FLOMORPHIC_TOKEN": "<paste the token>" }
    }
  }
}
```

### Claude Code

One command — Claude Code speaks Streamable HTTP natively, no bridge:

```bash
claude mcp add --transport http flomorphic http://localhost:8026/mcp
# with auth on:
claude mcp add --transport http flomorphic http://localhost:8026/mcp \
  --header "Authorization: Bearer <token>"
```

Then `/mcp` inside Claude Code lists the `flomorphic` tools.

### Cursor and other MCP clients

Anything that accepts a Streamable-HTTP MCP URL takes the endpoint as-is. Cursor,
for example (**Settings → MCP → Add** or `~/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "flomorphic": { "url": "http://localhost:8026/mcp" }
  }
}
```

Clients that only support stdio can reach it through the same `mcp-remote` bridge
shown above.

---

## What the tools can do

All tools are prefixed `flo_`. They mirror the REST surface — read and write for
every entity, plus the runtime actions a trusted full-control client is given
(start/stop a run, answer/close a human task).

| Area | Tools | What you can do |
| --- | --- | --- |
| **Workflows** | `flo_list_workflows`, `flo_get_workflow`, `flo_upsert_workflow`, `flo_compile_workflow` | List, read, save a Vue-Flow graph (same save as the editor), and validate a draft through the real compiler without saving. |
| **Designer (AI authoring)** | `flo_get_design_guide`, `flo_plan_patch`, `flo_apply_patch` + the `flo_design_workflow` **prompt** | Author a flow the way the app's *build-with-AI* dialog does: read the designer guide, write a readable **graph patch**, plan it (compile, no save) or apply it (save). |
| **Contexts** | `flo_list_contexts`, `flo_get_context`, `flo_upsert_context`, `flo_delete_context` | Inspect the JSON state a run read/wrote, and create or edit context documents. |
| **Runs (processes)** | `flo_list_processes`, `flo_get_process`, `flo_start_process`, `flo_stop_process`, `flo_delete_process` | Launch a run on the engine (or schedule one), stop it, and read status/error/timing/results. *Requires the inflow runtime to be connected.* |
| **Prompts** | `flo_list_prompts`, `flo_get_prompt`, `flo_upsert_prompt`, `flo_delete_prompt` | Manage prompt templates with `{{variable}}` placeholders and tags. |
| **Memory — vector** | `flo_list_memory_stores`, `flo_get_memory_store`, `flo_create_vector_store`, `flo_index_vector`, `flo_search_vectors` | Create a sqlite-vec store (embedding config captured once), index text, and run semantic search (content, metadata, distance). |
| **Memory — document** | `flo_create_document_store`, `flo_list_documents`, `flo_write_document`, `flo_update_document`, `flo_delete_document`, `flo_query_documents` | Store/edit JSON documents and run **read-only** `SELECT` SQL over a store (writes/DDL/PRAGMA/multi-statement rejected, capped at 1000 rows). |
| **Human-in-the-loop** | `flo_list_human_tasks`, `flo_get_human_task`, `flo_answer_human_task`, `flo_message_human_task`, `flo_close_human_task`, `flo_delete_human_task` | Read a task's prompt/questions/thread, answer questions, post a chat turn, and close a task — which **resumes a parked workflow** from its captured next nodes. |
| **Triggers** | `flo_list_triggers`, `flo_get_trigger`, `flo_set_webhook_trigger`, `flo_set_schedule_trigger`, `flo_delete_trigger` | Arm a flow with a webhook (`/hooks/<slug>`) or a cron/interval schedule (one trigger per flow). |
| **Node settings** | `flo_list_node_settings`, `flo_get_node_setting`, `flo_upsert_node_setting`, `flo_delete_node_setting` | Manage reusable node settings profiles (provider tokens, endpoints, …). |
| **Extensions** | `flo_list_extensions`, `flo_get_extension` | Inspect palette extensions — kind, plugin identity, parameters and bindings. |

### The designer prompt — the same brain as *AI Build*

The recommended way to start any FloMorphic workflow is **AI Build**: describe the
goal in plain language on the canvas and let the model draft the graph, which you
then read back and refine. It is not a shortcut around the design work — it is
where the design work happens. The walkthrough
[*Build a Claims Adjudicator You Can Actually Audit*](https://inflowenger.com/blog/flomorphic-claims-walkthrough)
shows that path end to end (install → set up credential profiles and memory stores
first → start in AI Build).

The MCP designer surface is **that same brain, exposed to an external client**. The
server advertises one MCP **prompt**, `flo_design_workflow` — the *exact* guidance
the web app's AI Build dialog uses (node catalog, scope and branching rules,
`$this` per-row templates, wiring and joining, and the plugin actions available in
your install). A client that supports MCP prompts can pull it in, describe a goal
in plain language, and get back the full contract for emitting a graph patch. So
Claude Desktop (or Claude Code) builds a flow from the same brain a person does on
the canvas, then lands it through the same compiler and save. This is the single
biggest lever: **have the model read
`flo_get_design_guide` (or the prompt) *first*, then author with `flo_plan_patch` /
`flo_apply_patch`.** The patch tools return a `problems` list that flags the
mistakes the guide warns about (a routing node on a many-valued scope, a no-op
"wait for all", branches converging without a join) — read it and fix before you
apply.

---

## Authentication

`/mcp` inherits the API's auth. By default `AUTH_ENABLED` is off and the endpoint is
open — which is what you want for a localhost-only install.

Set `AUTH_ENABLED=true` and `/mcp` requires a **bearer token** on every request: an
HS256 JWT signed with `API_JWT_SECRET` (falling back to `INFLOW_INFRA_JWT_SECRET` —
the platform's *API Secret Key*, the same one in `flomorphic/.env`). Mint a token
with that secret and hand it to the client as `Authorization: Bearer <token>` — the
connector's token field, `mcp-remote --header`, or `claude mcp add --header` above.

> Don't expose `/mcp` on a public interface without `AUTH_ENABLED=true`. The tools
> include full write access and runtime control (start/stop runs, resume parked
> flows); treat the endpoint like the API it is.

---

## Turning it off

The server is mounted only when the API boots with `MCP_ENABLED` unset or truthy.
To leave `/mcp` unmounted entirely, set `MCP_ENABLED=false` (or `0`/`no`) in the
FloMorphic API environment (`flomorphic/.env` on an installed stack) and restart.

---

## A first session, end to end

Once connected, a natural sequence a client (or you, prompting one) can run:

1. **`flo_get_design_guide`** — load the authoring contract.
2. **`flo_apply_patch`** — describe and save a small flow (e.g. an LLM node that
   summarizes its input). Read the returned `problems`; fix if any.
3. **`flo_start_process`** — run it (needs the runtime connected).
4. **`flo_get_process`** — read status and results.
5. **`flo_get_context`** — inspect the JSON state the run produced.

That is the whole loop — design, run, inspect — driven entirely from your chat
client, over the same code the canvas runs.
