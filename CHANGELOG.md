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
across all repos since v0.3.2._

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

[Unreleased]: https://github.com/FloMorphic/getting-started/compare/v0.3.2...HEAD
[v0.3.2]: https://github.com/FloMorphic/getting-started/releases/tag/v0.3.2
