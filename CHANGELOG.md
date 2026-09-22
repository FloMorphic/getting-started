# Changelog

All notable changes to the **FloMorphic** product are recorded here. FloMorphic
ships as one baked image (`mehdishokohi/flomorphic`) wrapping several component
repos, so this is the single product changelog — it aggregates the changes that
landed in each component between releases. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

**How a release is cut and how this file is written** — see
[docs/RELEASING.md](docs/RELEASING.md). In short: each release records the exact
component commits it was baked from in `releases/<version>.json`, and
`make changelog VERSION=<next>` drafts the next section by diffing every
component from the last recorded offset to its current `main`.

## [Unreleased]

_Run `make changelog VERSION=<next>` to draft this section from the commits landed
across all repos since v0.3.9._

## [v0.3.9] — 2026-09-23

A flow now has a **portable document and a road in and out of an install that
does not need the browser**. The API gains **REST twins of the editor's Import
dialog and Export button** (`POST /flow/import`, `GET /flow/id/:id/export`), the
MCP server gains **`flo_import_workflow` / `flo_export_workflow`**, and every
way a flow can land — REST import, MCP import, the designer's apply-patch — now
goes through **one path** that re-stamps plugin nodes with the install's own
identity and **reports the plugin actions it cannot serve** instead of saving a
node that silently points nowhere. The AI designer also **learned a plugin
action's outbound ports**, and the cookbook gained a **Linux-fleet HTTP / nginx
audit** recipe built entirely over MCP. The palette gains a new builtin, **Jev**
— a fast decider that routes a flow by calibrated answers to typed questions —
and the plugin catalog lists two new Connect-backed plugins, **GitHub** and
**Google Workspace**.

### Added

- **Jev — a new builtin node for fast, typed decisions.** Jev evaluates a block
  of flow state against **typed questions** on TypeSafe's Jev (a "System One"
  model) and returns a calibrated probability over every answer you declared —
  never free text — in one call (70–500 ms, all questions in parallel). A
  question is a `choice` (1–255 named options), a `score` (2–10 ordered levels)
  or a `noul` (yes / no), with an optional `min_confidence` floor. It maps onto
  the canvas the way an LLM with bound functions does: **every option of a
  routed question is an output port**, tagged `<question>.<option>` (e.g.
  `category.billing`), plus an `_exception` port for an API error, a missing
  answer or a low-confidence result; a question with `route: false` is data
  only. The full distribution, model version and credits used land on the node
  scope. `state` is a text template with `{{$.path}}` variables — a template
  that is exactly one token sends that JSON value as-is. The API key, model,
  base URL and timeout come from a `jev-config` settings profile. It ships as
  the `jev` plugin in `builtin-plugins` (picked up by the image build like the
  others), the palette entry and seeded builtin in the API, which compiles it to
  a Plugin node, and the node's drawer in the editor — options render as stacked
  port cards. The AI designer knows it too: edges name a Jev port as
  `<question id>.<option name>`, and the many-scope check flags a wildcard
  `scope` on a Jev node with routed questions. _(builtin-plugins, morph-api,
  morph-wapp)_
- **`POST /flow/import` and `GET /flow/id/:id/export` — the portable workflow
  document over REST.** The document is the file the editor's Export writes and
  the cookbook ships: a designer **graph patch** (nodes named by a readable
  `ref`, wired by `port` names, each carrying only the data that differs from
  its kind's defaults) under a small header (`flomorphic`, `title`, `plugins`).
  It is about half the size of the saved `FlowRecord` — no Vue-Flow render
  state — and holds **no install-local identity**: no canvas ids, no
  `extensionId` / `pluginId` (a per-install address), no plugin `form` /
  `outbound`, and no resolved settings profile, so a provider token never rides
  along in a file meant to be shared. Import takes `{ workflow, id?, title?,
  dryRun? }`: `id` overwrites an existing flow (a re-install), `title` overrides
  the document's own, and `dryRun` plans, stamps and compile-checks without
  saving. Plugin nodes are matched **by action name** and re-stamped from this
  install's extension table; an action no local plugin provides is kept, flagged
  with the same `missingPlugin` marker the canvas badges, and listed in
  `missingActions` with the repo / ref / subdir the document knows about — so an
  installer can tell the operator what to install. Compiling is a check, not a
  gate (a plugin node resolves its account through the live runtime, which an
  install being provisioned has none of yet): the result carries `compileError`
  alongside `problems`. Any JSON object with a `nodes` array is accepted, header
  or not, so a bare patch a model wrote imports the same as an editor file. A
  successful import emits `flow.changed` (`source: "import"`) so an open editor
  refetches. _(morph-api)_
- **`flo_export_workflow` / `flo_import_workflow` MCP tools.** The same document
  and the same road, for an assistant: export returns the compact form to *read
  and edit* a flow's design in, import takes it back with the same `id` /
  `title` / `dryRun` choices and the same `missingActions` report. The tool
  descriptions carry a short guide to the document's shape;
  `flo_get_workflow` now points readers at export rather than the verbose raw
  record. _(morph-api)_
- **`designer.GraphToPatch` — the Go twin of the canvas exporter.** The inverse
  of `PlanPatch`: canvas ids become refs derived from node titles, handle ids
  become designer port names, and each node keeps only the data that differs
  from its catalog defaults. A faithful port of the web app's `graphToPatch`, so
  a flow exported by the API reads the same as one the Export button writes and
  re-imports through the same planner. Lives with the new `flowfile` package
  that both the REST routes and the MCP tools call. _(morph-api)_
- **Cookbook: `linux-fleet-http-audit/`.** Audit a whole Linux fleet for HTTP
  servers, nginx (host or Docker) and the hostnames they serve, one evidence row
  per node: three parallel osquery sweeps fanned in by `promissall`, a JS node
  that normalises plugin results and classifies by a union of signals, a `rule`
  whose handlers are the branch, four probes `scope`'d over a computed target
  list, and a `db.stages.upsert` sink. Built and debugged entirely over MCP.
  _(flow-cookbook)_

### Changed

- **`flo_plan_patch` / `flo_apply_patch` land through the import road.** Both
  now stamp plugin nodes with this install's identity by `action` and return
  `missingActions`; a plan reports a compile failure in the result (with the
  planned `graph` and `problems`) instead of raising it, and an apply returns
  `compileError` next to the saved flow. A patch from the designer, a document
  from a file and a flow drawn by hand are now indistinguishable once saved.
  _(morph-api)_
- **The AI designer knows a plugin action's outbound ports.** A plugin node
  with declared `outbound` branches is a routing node like an LLM with functions
  or a Rule with handlers: its edges can name a port by the branch's title, the
  port resolves to the branch's tags, and the many-scope check now flags a
  wildcard scope on such a node the same way it does for the builtins. Import
  stamps identity *before* planning so those ports exist when the edges are
  resolved. _(morph-api)_
- `docs/mcp.md` tool table lists the import / export tools in place of the
  removed upsert / compile pair. _(getting-started)_

### Removed

- **`flo_upsert_workflow` and `flo_compile_workflow` MCP tools.** Both took the
  raw Vue-Flow `FlowRecord`, which is the wrong shape for anything that is not
  the canvas. `flo_import_workflow` (with `dryRun` for a compile-only check) and
  `flo_export_workflow` replace them; the designer's `flo_plan_patch` /
  `flo_apply_patch` remain the way to author from scratch. `POST /flow` still
  accepts a raw record over REST. _(morph-api)_

### Fixed

- **Connecting an oomol app that has no in-app OAuth now opens that app's own
  page** in the oomol console (`/connections/<app>`, `no_auth:` prefix dropped)
  instead of the generic connections list. _(morph-wapp)_
- **The Jev plugin reads the reply the live service actually sends.** The
  service wraps its answers (`{"code":0,"data":{"result":{…},"creditsUsed":1}}`)
  while TypeSafe's published reference shows them flat; both shapes are now
  decoded, and the credits a call used are reported on the scope. The plugin
  also targets the host that serves the API (`thejevai.com`) and sends an
  explicit `User-Agent` for its CDN. _(builtin-plugins)_

### Maintenance

- `morph-api` README documents the two new routes. _(morph-api)_
- `bytedance/sonic` bumped 1.15.2 → 1.15.4. _(morph-api)_
- **Plugin catalog: two new Connect-backed plugins, both beta.**
  [GitHub (OpenConnector)](https://github.com/FloMorphic/github-oc) — 13
  read-only actions over repositories, activity, search and the security surface
  (Dependabot / secret-scanning / code-scanning alerts, branch protection and
  rulesets, org members and 2FA, deploy keys, webhooks, Actions settings); the
  catalog's first Python `-oc` plugin. [Google Workspace
  (OpenConnector)](https://github.com/FloMorphic/google-office-oc-plugin) — 30
  actions across Sheets, Docs, Drive and Calendar. Like Gmail, both hold no
  provider credentials: they act as an account connected once in **Connect**,
  over `flomorphic.svc.oc.*`, so they run on FloMorphic only. The catalog also
  gained a *Running one* guide (`docs/run-a-plugin.md`). _(plugin-catalog)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `bf7fe69` |
| `morph-wapp`        | `main` | `ce0815e` |
| `builtin-plugins`   | `main` | `bd99581` |
| `inflow-plugin-sdk` | `main` | `87ed880` |
| `node-plugin-sdk`   | `main` | `a025c5c` |

## [v0.3.8] — 2026-09-18

A robustness release. The headline fix is for the **host-reboot race**: after a
machine restart the API could come up with an empty engine pool and answer
"no resource" to every run until someone restarted the container — it now
**keeps looking for the engine in the background** until one is reachable. The
**installer and image learned to point at an Infra by IP** (an existing platform
on the Docker host, a remote box) instead of only by container name, the **AI
flow designer stops generating Rule nodes that silently dead-end**, and the
canvas got its **brand mark**.

### Added

- **`PLUGIN_INFRA_URL` — Infra's NATS address, set on its own.** Infra answers on
  two addresses: its REST API (`:8022`) and NATS (`:4222`), and every plugin node
  talks over the second. Until now the NATS endpoint was always derived from the
  `INFLOW_INFRA_API` host, which is right for the stock platform stack and wrong
  for a remapped NATS port or an Infra reachable on a different address. The
  compose file, the installer and the entrypoint now take `PLUGIN_INFRA_URL`
  (`host:port`, no scheme); left empty, the derived value still applies. The
  installer's "existing platform" path derives and records it in `.env`, and the
  summary prints it. _(getting-started)_
- **`host.docker.internal` inside the FloMorphic container.** The compose file
  injects `host.docker.internal:host-gateway`, so an Infra — or an LLM, an MCP
  server, a database a node calls — running on the Docker host rather than on
  `inflow_net` has a stable name from inside the container. The installer offers
  it as the address for that case instead of a bridge-gateway IP that changes
  whenever the network is recreated. _(getting-started)_
- **`WithConnection` in the Go plugin SDK.** A plugin that already holds a NATS
  handler can hand it to the SDK directly instead of having the SDK dial a
  second time. _(inflow-plugin-sdk v0.2.3)_
- **Canvas brand mark.** The header logo and favicon are now the FloMorphic mark
  itself. The artwork was drawn for a dark surface, so light theme seats it on a
  dark chip and dark theme leaves the chip transparent. _(morph-wapp)_

### Changed

- **The AI flow designer is taught the Rule node's real contract.** A Rule's
  decision must be **one string equal to a handler `name`** (or an array of names
  to fire several ports); anything else — an object like `{ pass: true }`, an
  unknown string, `''`, `null`, `undefined` — fires no port, which prunes every
  outgoing edge and ends that branch with no error and no log line. The designer
  preamble and node catalog (server-side and canvas-side) now say exactly that,
  demand an exhaustive decision on every path (`ok ? 'approved' : 'rejected'`,
  never an `if` with no `else`), and the Rule node's default `logic_rule`
  template — which used to be the very `{ pass: true }` object that never routes
  — is a working two-way branch. _(morph-api, morph-wapp)_
- **Installer normalizes whatever you type for the Infra address.** `host`,
  `host:8022`, `http://host:8022/`, `nats://host:4222` and bracketed IPv6 all
  land in `.env` the same way: the REST URL gains `http://` and the default port
  when missing (but not behind `https://`, which is already a proxy on 443), and
  the NATS endpoint is stripped to bare `host:port`. A non-HTTP scheme pasted
  into the API prompt is flagged rather than written out. _(getting-started)_
- **Installer always confirms the API Secret Key for an existing platform.** A key
  found in a local `platform/.env` is now offered as an editable default rather
  than silently assumed — that file describes the platform installed *here*,
  which need not be the one being pointed at, and Infra mints a fresh secret
  whenever it comes up without one. The paste hint (`Ctrl+Shift+V`) is shown
  when the key has to be typed in. _(getting-started)_
- **Cookbook flows carry their plugin's repo.** The naive-RAG and Qdrant-migrate
  samples now declare `repo` on their Qdrant plugin reference, so the importer's
  missing-plugin panel (new in v0.3.7) links straight to where to install it
  from. _(flow-cookbook)_

### Fixed

- **The API no longer stays engine-less after a host reboot.** On a machine
  restart every container starts at once; the engine (Fractal) is usually still
  registering — or crash-looping on a NATS that is not up yet — when the runtime
  SDK's one-shot startup reload probes Infra's engine list, so the pool came up
  empty and stayed that way for the life of the process: **"no resource" on every
  run** until the container was restarted or the engine was added by hand. The
  API now keeps re-reading the engine list in the background with a capped
  backoff (2 s → 30 s) until at least one registered engine answers. The reload
  only fills the pool if it is still empty, so a resource an operator adds by
  hand while a tick is in flight is kept and ends the loop, and the retry does
  not repeat the per-resource "dropped" warnings every tick. _(morph-api,
  inflow-fusion v0.3.5)_
- **Adding an engine by hand from the settings dialog works for
  portal-registered engines.** A hand-added resource carries no credential, and
  the probe fell back to the Infra bearer — a different key — so an engine
  enrolled through a portal answered 401 and never joined the pool, even though
  it was live and correctly addressed. The runtime SDK now looks up the token
  Infra already holds for that URL before probing. Along the way, a resource URL
  typed without a scheme (`localhost:9001`, `127.0.0.1:9001`) is parsed
  correctly instead of ending up as `localhost:9001:9001` or failing outright,
  and the liveness error now says *which* part failed. _(morph-api, inflow-fusion
  v0.3.4)_
- **Plugin nodes can dial an Infra given by IP.** The Go plugin SDK ran
  `url.Parse` over a bare `INFRA_URL`; that only worked because Go read
  `inflow-infra:4222` as a scheme, and it rejected any host not starting with a
  letter — `172.28.0.1:4222` failed with *"first path segment in URL cannot
  contain colon"*, i.e. every install pointed at an existing platform by IP.
  `INFRA_URL` is now normalized before dialing, accepting both `host:port` and
  `nats://host:port`. The four builtin plugin modules (`cast`, `http`, `llm`,
  `mcp`) build against the fixed SDK, and the image entrypoint additionally
  aliases a bare-IP NATS endpoint in `/etc/hosts` (`infra-nats`) so any plugin
  binary still on an older SDK keeps working. _(inflow-plugin-sdk v0.2.3,
  builtin-plugins, getting-started)_

### Maintenance

- **Builtin plugin nodes build against Go plugin SDK v0.2.3.** _(builtin-plugins)_
- **`morph-api` on inflow-fusion v0.3.5** (via v0.3.4), which carries the two
  runtime fixes above. _(morph-api)_
- `docs/development.md` documents `PLUGIN_INFRA_URL` next to `INFLOW_INFRA_API`.
  _(getting-started)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `2f36ed0` |
| `morph-wapp`        | `main` | `12b97ab` |
| `builtin-plugins`   | `main` | `051f611` |
| `inflow-plugin-sdk` | `main` | `87ed880` |
| `node-plugin-sdk`   | `main` | `a025c5c` |

## [v0.3.7] — 2026-09-08

Two of FloMorphic's own AI nodes got more legible and more controllable this
release: the **MCP node** now streams a turn-by-turn account of what the model is
doing and lets you **raise its agentic-loop cap**, and the **LLM node** stops
drowning the canvas in progress frames on token-streaming providers. Off the
canvas, the **plugin SDK family gained a third language — Python — now published
on PyPI**, and importing a flow now **tells you which plugin nodes you don't have
installed** instead of failing quietly.

### Added

- **First public release of the Python plugin SDK.** `inflowenger-plugin-sdk` is
  now on [PyPI](https://pypi.org/project/inflowenger-plugin-sdk/) (`pip install
  inflowenger-plugin-sdk`, Python 3.11+) — the Python port of the Go SDK, speaking
  the same `inflowv1` protocol wire-for-wire. Go stays the normative reference;
  Node.js and Python track it. Not baked into the image; it ships on its own for
  plugin authors. _(py-plugin-sdk)_
- **Configurable MCP agentic-loop cap.** The MCP node's run body now takes an
  optional `max_tool_turns`, exposed as a **Min tool turns** control in the MCP
  settings drawer. The previous hard-coded limit of 8 becomes the default and the
  floor — a node can raise the cap for longer agentic runs but never drop below
  the default — so a model that keeps asking for tools still can't spin forever.
  _(builtin-plugins, morph-wapp)_
- **Live activity stream from the MCP node.** A `run` now narrates each turn as it
  goes: a **`thinking`** frame while the model is being consulted (`consulting
  <model> (turn N)`), a **`tools selected`** frame listing the batch the model
  picked, then per-tool **`calling tool` / `tool done` / `tool failed`** frames.
  The progress percentage ramps steadily toward — but never reaches — 100, which
  the runtime reserves for "done". _(builtin-plugins)_
- **Copy settings profiles between dialogs via the clipboard.** Both the node
  settings and plugin onboarding dialogs now have **Export** and **Import**
  buttons that move a profile's field values as JSON on the clipboard — export
  copies whatever is on screen, import pastes it into the form's fields. Paste
  only updates the on-screen fields; nothing is saved until you commit, and a
  paste that isn't a JSON object is rejected with a readable message. _(morph-wapp)_
- **Plugin credentials can be minted with extra environment variables.** A cred
  request now takes an optional `env` list — upstream keys, endpoints, mode flags
  — and the generated `.env` carries them alongside the minted credential instead
  of leaving the plugin author to paste them in by hand. `PLUGIN_ID` and
  `INFRA_CRED` are always emitted and can't be overridden; an `INFRA_URL` entry
  is honoured, since the address this API reaches Infra on ("infra:4222" in
  compose) is often not the one a plugin on someone's laptop can dial. _(morph-api)_

### Changed

- **Importing a flow now detects plugin nodes you don't have installed.** Instead
  of a flow that quietly fails to run, the importer surfaces the missing plugin
  nodes up front across the import, canvas and node UI, so you know what to install
  before wiring it up. _(morph-wapp)_
- **LLM node streaming is batched.** Token-streaming providers (OpenAI and the
  like) emit one delta per token — 1000–2000+ chunks for a single long turn — and
  the old one-chunk-one-frame path blew past the runtime's per-job send threshold.
  A new frame batcher decouples the canvas update rate from the provider's chunk
  granularity: it flushes on a word boundary after enough new text, on a hard
  character cap (so a boundary-less token run still flushes), or on a minimum time
  gap (so a slow stream stays live), and always shows the complete text before the
  job finalizes. Coarse-chunk providers like Gemini are unaffected.
  _(builtin-plugins)_
- **stdio dropped from the MCP node's transport picker.** The MCP node is a
  builtin that talks to a *remote* server, so it has no local process to speak
  stdio with — the option could only ever be a dead end. Streamable HTTP, SSE and
  WebSocket remain. _(morph-wapp)_

### Fixed

- **Re-syncing a plugin no longer breaks the flows already using it.** A sync used
  to delete every derived palette row for a plugin and re-insert one per live
  action, which handed each node a fresh id — and since a saved workflow stores
  that id, every canvas pointing at the plugin was left with stale references
  after a routine re-sync. Sync now reconciles instead: an action that already has
  a row keeps it (matched on its method, falling back to its exact name so a
  renamed method still finds its node) and is rewritten in place, an action with
  no row gets a new one, and only rows no live action claimed are deleted — so a
  dropped method still disappears from the palette. The sync result reports
  `updated` alongside `added` and `removed`. _(morph-api)_

### Maintenance

- **Builtin plugin nodes build against Go plugin SDK v0.2.2.** All four modules
  (`cast`, `http`, `llm`, `mcp`) bump their `inflow-plugin-sdk` dependency to
  v0.2.2. _(builtin-plugins)_
- **Cookbook: a naive-RAG example flow.** A new end-to-end retrieval-augmented
  flow (with readme) demonstrating the vector store landed in v0.3.6, updated to
  match the new import behavior. Ships with `flow-cookbook`, not baked.
  _(flow-cookbook)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `44111d4` |
| `morph-wapp`        | `main` | `3882481` |
| `builtin-plugins`   | `main` | `0145d5f` |
| `inflow-plugin-sdk` | `main` | `96d24b9` |
| `node-plugin-sdk`   | `main` | `a051113` |

## [v0.3.6] — 2026-08-30

Headlined by a **vector store you can wire up entirely from the canvas**: pick an
embedding provider, load its real model list with your own key, set the output
dimension, then **write** records (text plus metadata) and **read** them back by
top-K with an optional similarity floor and metadata filtering. This release also
restores **builtin nodes' access to plugin services**, which the previous release
had narrowed by accident.

### Added

- **Vector store with a live model-provider picker.** The add-vector-store form
  now offers a real catalog of embedding providers — **OpenAI, Google Gemini,
  Cohere, Mistral, Voyage AI**, plus an **OpenAI-compatible custom base URL** —
  instead of a free-text guess. Choosing a provider and supplying its key loads
  the embedding models that key can actually use: the browser posts to
  `POST /memory/embedding-models`, which proxies each provider's list-models API
  server-side (via `svc.ListEmbeddingModels`) so the key never leaves the backend
  and CORS is never in the way. Voyage (no list API) falls back to its published
  line-up. Each model carries a sensible **default output dimension** that
  pre-fills the size field, which stays editable because several models
  (`text-embedding-3-*`, `gemini-embedding-001`, `embed-v4.0`…) support more than
  one size. _(morph-api, morph-wapp)_
- **Top-K and minimum-score vector queries.** A vector search now takes an
  optional `minScore` alongside `topK`, and every hit comes back with a
  normalized **similarity `score`** (higher is nearer) derived from the raw
  distance regardless of the store's metric — `1 − distance` clamped to `[0,1]`
  for cosine, `1/(1+distance)` for L2. Because both are monotonic in distance, a
  search can rank and threshold on the intuitive `0–1` scale and stop at the first
  sub-threshold hit. The store settings expose top-K and score in the UI.
  _(morph-api, morph-wapp)_
- **Vector write mode with metadata, and metadata as a read filter.** A vector
  store node now runs in **write** or **read** mode. In write mode the text to
  embed comes from the node's own `text` parameter — a `{{$.path}}` placeholder
  the engine resolves against the flow context before the call (with fallbacks to
  a `text`/`content` field or a scope that resolved to a bare string) — and you
  attach **metadata** as key/value rows whose values are themselves
  jsonpath-resolvable, so a record can carry live fields from the run. Those rows
  are flattened onto the payload as root-level `meta.<key>` entries (the only
  place the engine resolves placeholders) and reassembled handler-side. On a
  **read**, the same metadata rows become an **equality filter** that restricts
  which records a similarity search can match, so a store can be partitioned by
  arbitrary fields at query time. _(morph-api, morph-wapp)_

### Fixed

- **Builtin nodes can talk to plugin services again.** When minting a plugin's
  credential, `mintCred` unconditionally added `flomorphic.svc.>` to the publish
  allow-list. For an **open** (multi-plugin) credential that allow-list is meant to
  be empty — NATS reads an empty allow-list as "allow all" — so adding one subject
  flipped it to "allow *only* that subject", stripping the plugin of its ability to
  respond on `_INBOX.>` and breaking every builtin node. The svc reach is now added
  only for **strict** credentials, which enumerate their publish subjects
  explicitly; open credentials are left as "allow all" and can already reach
  `flomorphic.svc.>`. _(morph-api)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `c4f19b2` |
| `morph-wapp`        | `main` | `ed331fc` |
| `builtin-plugins`   | `main` | `e31fa4a` |
| `inflow-plugin-sdk` | `main` | `96d24b9` |
| `node-plugin-sdk`   | `main` | `a051113` |

## [v0.3.5] — 2026-08-29

A small maintenance release: the **workflow stop** path now recognizes the engine's
graceful "accepted" reply instead of surfacing it as an error, plugins built on the
**node SDK** can no longer crash when a stopped run leaves their requests
unanswered, and the cookbook gains a **Qdrant vector-data migration** example.

### Added

- **Qdrant vector-data migration flow.** A new `qdrant-migrate` cookbook example
  (flow, README and screenshots) walks through adding a Qdrant collection and
  transferring vector data into it. _(flow-cookbook)_

### Fixed

- **Stopping a workflow no longer reports a false error.** The fractal engine
  answers a stop request with a graceful `202/OK` (`{"data":"OK"}`), which
  inflow-fusion cannot decode into a pid-shaped response and returns as a sonic
  mismatch error. `StopWorkflow` now reads that specific decode error as "stop
  accepted": it records the stop and lets the run's own finish reconcile the final
  status, instead of surfacing the mismatch as a failure. Bundles the
  inflow-fusion `v0.3.1 → v0.3.3` bump this relies on. _(morph-api)_
- **A stopped workflow can no longer crash a node-SDK plugin.** When a user stops a
  run, the plugin's NATS requests are left with no responders; `send()` used to
  throw, surfacing as an unhandled rejection that took down the whole plugin. It now
  mirrors the Go SDK — logs the failing call and returns `undefined` — and every
  `cmd*` helper guards against that empty reply, so a stopped run winds down quietly.
  Retry diagnostics now include the subject and body of the failing call.
  _(node-plugin-sdk, 0.1.7)_

### Maintenance

- Build fix on the canvas. _(morph-wapp)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `eb5145e` |
| `morph-wapp`        | `main` | `40cbdb9` |
| `builtin-plugins`   | `main` | `e31fa4a` |
| `inflow-plugin-sdk` | `main` | `96d24b9` |
| `node-plugin-sdk`   | `main` | `a051113` |

## [v0.3.4] — 2026-08-28

A small follow-up to v0.3.3: a **JSONPath probe** in the context inspector so a
designer can see exactly which values a node's `{{$.path}}` template resolves
against a real run, **per-plugin icons and colors** so imported plugin nodes are
visually distinct on the canvas instead of all wearing the same generic plug, and
a **more robust workflow stop** that reconciles against Infra's trace instead of
surfacing a misleading error when a run has already finished.

### Added

- **JSONPath probe on the context inspector.** The full-page context view now
  carries a read-only query box: type the same `{{$.path}}` expression a node uses
  in its template and see, against the real context document, exactly which values
  resolve — the scope that node reads from. Supports child/index selectors, `*`
  wildcards, `..` recursive descent, slices and unions (filters are out of scope by
  design). It never mutates the context. _(morph-wapp)_

### Changed

- **Plugin nodes render their own icons and colors.** Every plugin action used to
  show the same generic plug glyph on a same-hue tile. `Icon` now resolves
  Iconify-style names (`mdi:database` / `mdi-database`) from the bundled Material
  Design Icons set — lazy-loaded as its own async chunk so the ~3 MB collection
  never blocks cold load and stays offline — and the action's declared icon is
  threaded through to the node. Each imported plugin also derives a stable color
  from its id (hashed hue), with an optional per-class shade so a multi-service
  plugin's sub-groups (e.g. google's docs / sheets / drive) tell themselves apart
  while staying one family; the color is applied to node, palette and drawer
  accents and to the Extensions/Registry cards. _(morph-wapp)_

### Fixed

- **Stopping an already-finished workflow no longer errors.** A fractal engine
  instance forgets a run's pid the instant the run ends, so `StopWorkflow` could
  answer with a misleading "no pid to stop" error while the row still read
  `running` (a `proc.finish` that never made it back on the event log). Stop now
  consults Infra's week-long trace before surfacing that error: if the trace shows
  the run finished, the row is reconciled to its real terminal status and the stop
  is a satisfied no-op; if the trace still shows it live, the genuine error is
  surfaced unchanged; and a row the engine and Infra both have no record of is
  best-effort marked `stopped` so it never sits as `running` forever. Infra being
  unreachable is never treated as a finish — the original error is passed through.
  _(morph-api)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `f063ae7` |
| `morph-wapp`        | `main` | `7fa6826` |
| `builtin-plugins`   | `main` | `e31fa4a` |
| `inflow-plugin-sdk` | `main` | `96d24b9` |
| `node-plugin-sdk`   | `main` | `f50c101` |

## [v0.3.3] — 2026-08-26

A follow-up to v0.3.2 focused on the node-authoring experience and flow
reliability: a **clear-history** option for LLM and MCP nodes so looping flows can
start each pass fresh, a **prompt expander** for editing long prompts, more
reliable AI-designed flows, a **security fix** that stops workflow exports from
leaking settings-profile tokens, and fixes to process-stop and the plugin build.
This release also begins tracking the new `flow-cookbook` repo in the changelog
roll-up.

### Added

- **Clear-history option for LLM and MCP nodes.** A new `clear_history` toggle in
  the node settings drawer makes a node discard the conversation carried on its
  scope and re-seed its init messages (the system/user template) on every run. In
  a looping or resumed flow this starts each pass from a fresh init instead of
  accumulating history across passes. _(morph-wapp, builtin-plugins)_
- **Prompt expander on every prompt input.** An "Expand" affordance beside the
  prompt boxes (LLM / MCP drawers and the human-in-the-loop settings) opens the
  same text in a roomy dialog, so long init prompts can be read and edited
  comfortably; edits sync live with the small textarea. _(morph-wapp)_

### Changed

- **More reliable AI-designed flows.** The flow-designer preamble now spells out
  strict-JSON rules (single-quoted JS string literals, `\n`-encoded newlines) and
  the `rule`-vs-`js` branching contract (only a `rule` node may branch), so the
  model's generated workflows parse and import cleanly instead of failing on
  malformed JSON or a `js` node with handlers. _(morph-api)_

### Security

- **Workflow exports no longer leak settings-profile secrets.** A node's settings
  profile now leaves an exported flow by *reference* only (`settingsId`); its
  resolved values — which hold the provider API token — are dropped on export
  instead of being written into the shared file. On import the id is re-resolved
  against the target install's own profiles, and a node whose profile is missing
  is flagged for the designer to pick one. _(morph-wapp)_

### Fixed

- **Stopping a scheduled or already-finished process is now handled correctly.**
  `StopWorkflow` previously assumed a live engine run: cancelling a *scheduled*
  row (recorded but not yet dispatched) errored, and the run would still fire at
  its scheduled time. A scheduled row is now simply marked `stopped` and the
  scheduler re-armed so it never fires; a stop on an already terminal row is a
  harmless no-op. _(morph-api)_
- **Plugin build no longer fails when `bin/` is missing.** The Go branch of the
  plugin install/build script now creates the output directory (`mkdir -p bin`)
  before `go build`, so building a Go plugin extension from a clean checkout
  succeeds. _(morph-api)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `62f66df` |
| `morph-wapp`        | `main` | `a914559` |
| `builtin-plugins`   | `main` | `e31fa4a` |
| `inflow-plugin-sdk` | `main` | `96d24b9` |
| `node-plugin-sdk`   | `main` | `f50c101` |

## [v0.3.2] — 2026-08-24

First changelog-tracked release, and the first to aggregate the whole team's work
across every FloMorphic repo. v0.3.1 and earlier were cut manually; the commits
v0.3.1 baked from are recorded in `releases/v0.3.1.json` as the baseline, so this
entry covers everything landed after it. The theme of this release is
**OpenConnector integration** and a **full plugin lifecycle + metadata pass**
across the API, the canvas and both plugin SDKs.

### Added

- **OpenConnector integration.** The API connects to the OpenConnector server and
  proxies plugin traffic over the NATS plugins handler; the canvas gains a Connect
  page to drive it. _(morph-api, morph-wapp)_
- **Plugin lifecycle service.** A plugin service in the API exposes
  `start` / `stop` / `restart` / `status` / `logs` / `build` commands for managing
  plugin extensions. _(morph-api)_
- **Per-plugin request timeouts.** A configurable `REQ_TIMEOUT` now exists in both
  plugin SDKs (`WithTimeout` in the Go builder, request `setTimeout` in the node
  SDK) and is surfaced as an env var when creating a plugin extension.
  _(inflow-plugin-sdk, node-plugin-sdk, morph-wapp)_
- **Plugin action metadata / tags.** Action models carry `tags`; the API surfaces
  plugin action parameters in the designer prompt builder; the canvas groups
  plugin classes by a tag divider and supports multi-select list fields.
  _(inflow-plugin-sdk, node-plugin-sdk, morph-api, morph-wapp)_
- **"Manual" plugin mode.** A `manual` field on the plugin intro (both SDKs) plus
  a manual plugin view in the canvas extension list.
  _(inflow-plugin-sdk, node-plugin-sdk, morph-wapp)_
- **node-plugin-sdk publishing.** A GitHub Action now publishes the node SDK to
  npm. _(node-plugin-sdk)_

### Changed

- Plugin credentials now grant the `flomorphic.svc.>` NATS subject. _(morph-api)_
- node-plugin-sdk synced with the mainstream plugin-sdk; git workflow and README
  updates. _(node-plugin-sdk)_
- Flow edges tidied in the canvas. _(morph-wapp)_

### Fixed

- node-plugin-sdk package version. _(node-plugin-sdk)_

### Baked from

| Component           | Ref    | Commit    |
| ------------------- | ------ | --------- |
| `morph-api`         | `main` | `18bd3f0` |
| `morph-wapp`        | `main` | `00a3b5d` |
| `builtin-plugins`   | `main` | `470d258` |
| `inflow-plugin-sdk` | `main` | `96d24b9` |
| `node-plugin-sdk`   | `main` | `f50c101` |

[Unreleased]: https://github.com/FloMorphic/getting-started/compare/v0.3.8...HEAD
[v0.3.8]: https://github.com/FloMorphic/getting-started/compare/v0.3.7...v0.3.8
[v0.3.7]: https://github.com/FloMorphic/getting-started/compare/v0.3.6...v0.3.7
[v0.3.6]: https://github.com/FloMorphic/getting-started/compare/v0.3.5...v0.3.6
[v0.3.5]: https://github.com/FloMorphic/getting-started/compare/v0.3.4...v0.3.5
[v0.3.4]: https://github.com/FloMorphic/getting-started/compare/v0.3.3...v0.3.4
[v0.3.3]: https://github.com/FloMorphic/getting-started/compare/v0.3.2...v0.3.3
[v0.3.2]: https://github.com/FloMorphic/getting-started/releases/tag/v0.3.2
