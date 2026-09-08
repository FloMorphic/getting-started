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
across all repos since v0.3.7._

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

[Unreleased]: https://github.com/FloMorphic/getting-started/compare/v0.3.7...HEAD
[v0.3.7]: https://github.com/FloMorphic/getting-started/compare/v0.3.6...v0.3.7
[v0.3.6]: https://github.com/FloMorphic/getting-started/compare/v0.3.5...v0.3.6
[v0.3.5]: https://github.com/FloMorphic/getting-started/compare/v0.3.4...v0.3.5
[v0.3.4]: https://github.com/FloMorphic/getting-started/compare/v0.3.3...v0.3.4
[v0.3.3]: https://github.com/FloMorphic/getting-started/compare/v0.3.2...v0.3.3
[v0.3.2]: https://github.com/FloMorphic/getting-started/releases/tag/v0.3.2
