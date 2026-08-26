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
across all repos since v0.3.3._

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

[Unreleased]: https://github.com/FloMorphic/getting-started/compare/v0.3.3...HEAD
[v0.3.3]: https://github.com/FloMorphic/getting-started/compare/v0.3.2...v0.3.3
[v0.3.2]: https://github.com/FloMorphic/getting-started/releases/tag/v0.3.2
