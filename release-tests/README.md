# release-tests — a collection of flows that must still work

A release test here is **a flow plus what it should produce**. The flows live in
`collection/`, one directory each, and `flotest` imports them into a FloMorphic
instance over its MCP endpoint, runs them, and checks the run against what the
case says it should do.

The point is a fresh instance. Build an image, start it in an empty folder, point
`flotest` at it, and the flows that proved the last release's fixes run again
against the new one — with their profiles, their seed data and their expected
results, none of which survive a plain export.

```bash
cd release-tests
cp secrets.env.example secrets.env     # fill in the tokens (gitignored)
./flotest check                        # is the instance up, does it have the nodes
./flotest all                          # profiles + import + run, then a summary
```

Default endpoint is `http://localhost:8026/mcp` — the API port a FloMorphic stack
publishes (`FLOMORPHIC_API_PORT`). Override with `--endpoint` or `FLOTEST_MCP`.

---

## Commands

| | |
|---|---|
| `./flotest check` | Reachable? Which MCP tools, which node kinds the collection needs and whether this install has them, and whether every profile can be filled from `secrets.env`. |
| `./flotest list` | What is in the collection, and what each case claims to prove. |
| `./flotest profiles` | Create the Node Settings profiles the flows bind to. |
| `./flotest import` | Import every flow, each keeping its own id. |
| `./flotest run [slug …]` | Seed a fresh context, run, assert, report. |
| `./flotest all` | `profiles` + `import` + `run`, then a summary table. |
| `./flotest add <flow_id> <slug>` | Export a flow off the instance **into** the collection and scaffold its `case.json`. |
| `./flotest grab-profile <nset_id> <name>` | Copy a Node Settings profile into `profiles/`, splitting its secrets into `secrets.env`. |
| `./flotest pull [slug …]` | Re-export collected flows from the instance, keeping their `case.json`. |

`run` and `all` skip two kinds of case unless you ask for them: `--include-manual`
for a case whose `requires.manualSetup` needs you to do something first, and
`--skip-slow` to drop the ones tagged `slow`. Exit code is non-zero if anything
failed, so this works in CI.

---

## Why a flow alone is not enough

`flo_export_workflow` deliberately strips everything install-local: no canvas ids,
no extension or plugin ids, and **no resolved settings**. That is right for
shipping a flow to a stranger, and not enough to re-run one. Three things have to
travel beside it.

**The profiles.** A node carries `settingsId`; import resolves it against the
local Node Settings table and, finding nothing, leaves the node with an empty
settings map — so it reaches its plugin with no endpoint, no model and no token.
`profiles/*.json` carry those profiles **with their original ids**, so
`./flotest profiles` recreates them and the ids in the flow resolve. Secret values
are replaced by `${VAR}` references and live in `secrets.env`, which is
gitignored; `secrets.env.example` carries the empty shape.

**The seed context.** Some flows read state they do not create — the prescription
needs its twelve lines, the bench its eight cases. `seedContext` is either an
inline object or the name of a file in the case directory. Every run gets a
**fresh** context seeded from it, so a marker left by an earlier run can never be
read as this one's.

**The expectation.** Otherwise "it ran" is all you learn, and these flows are
mostly about a run *not* doing something — a branch that should not fire, an error
that should still be counted.

## Stable ids, on purpose

Each case records the flow's `flowId`, and `./flotest import` imports under it.
Both the workflow and the node-settings repositories insert with a supplied id
when they do not already hold it, so importing is **idempotent**: the same
collection lands on the same ids on any instance, a re-import updates in place
instead of piling up copies, and `runtest`-style scripts that name a flow id keep
working across installs.

---

## A case

```
collection/<slug>/
  flow.json          the portable workflow document (what Export writes)
  case.json          how to run it and what to expect
  seed-context.json  optional, if seedContext names it
```

`case.json`:

```json
{
  "flowId": "flow_…",
  "title": "…",
  "proves": "one sentence a reader can check the result against",
  "since": "v0.4.5",
  "tags": ["llm", "slow"],
  "run": { "stopOnError": true, "executeTimeoutSec": 180, "processNodeLimit": 400 },
  "seedContext": {},
  "requires": {
    "profiles": ["llm-nara-ai"],
    "services": [{ "what": "…", "at": "…" }],
    "manualSetup": "something you must do first, or omit the key",
    "engine": "a note about what the engine must be built past"
  },
  "expect": {
    "status": "finished",
    "errorCount": 1,
    "markers": { "fired_a_exception": true, "fired_b_exception": false },
    "codes": { "uncertain": "low_confidence" },
    "context": { "tally.routed": 12, "report.rows": 24 }
  }
}
```

`repeat` is how many times a passing run has to pass, and `poll` overrides the
status-poll interval for a case that finishes in milliseconds. Repetition is what
makes a case useful against an intermittent defect: one that shows in 5% of runs
clears a single run 95% of the time and tells you nothing. A repeated case
reports `100/100 clean`, and a failure reports how many of the N failed — which
distinguishes "always broken" from "occasionally broken".

`run` holds the engine overrides `flo_start_process` takes. Everything under
`expect` is optional:

- **`status`** — the process row's final status, normally `finished`.
- **`errorCount`** — how many entries the run's error ledger holds. A number, or
  a matcher.
- **`markers`** — context keys starting `fired_`. `true` means it must be
  present, `false` means it must **not** be, a string means it must equal that.
  This is how a flow says "this branch kept routing and that one was cut".
- **`codes`** — `contextKey: code`, read off the node payload that key holds. The
  exception code a node concluded with.
- **`context`** — any dotted path into the context, against a matcher.

Matchers are a bare value for equality, or one of
`{"eq": v}`, `{"gte": n}`, `{"lte": n}`, `{"len": 12}`, `{"len": {"gte": 8}}`,
`{"exists": true}`, `{"contains": "…"}`.

## Adding a flow to the collection

Design it on a live install, then take it:

```bash
./flotest add flow_mv4ne18w4fj72pbm exception-traits-ai-decision --since v0.4.6
```

That writes `flow.json`, scaffolds `case.json`, and tells you which profiles the
flow's nodes bind to. If one of them is not in `profiles/` yet:

```bash
./flotest grab-profile nset_mv47msqq5zlk5tw7 llm-nara-ai
```

Then fill in `proves` and `expect` by hand — run it once, look at what the
context holds, and write down the part of it that is the claim. `./flotest pull`
later refreshes a collected flow from the instance without touching its case.

---

## What is in the collection today

All five came in with **v0.4.5**, whose subject was: *an exception has to be able
to reach the branch drawn for it.*

Two cases came in with **v0.4.6**, as regression tests for a write-visibility
defect in the engine found while release-testing v0.4.5 — a node's result was not
necessarily in the Context by the time its successor ran. Both are `js`/`rule`
only: no model, no plugin, no network, no secret, ~30ms a run.

| slug | proves | needs |
|---|---|---|
| `loop-write-visibility` | A loop guard sees the state written by the node before it, on the first pass and through the back-edge. 100 repeats. | nothing |
| `write-visibility-shapes` | A sequential edge orders a write; a Wait for All is a barrier; parallel peers are deliberately unordered. 60 repeats. | nothing |

The v0.4.5 set:

| slug | proves | needs |
|---|---|---|
| `prescription-intake-router` | An llm node's five bound functions are five routes; the line it cannot route leaves through `_exception` as a decision, not a failure. | hosted router + token |
| `exception-traits-ai-decision` | ai-decision sorts its codes by whether the node delivered: a confidence below the floor keeps its branch under `stopOnError`; a provider error still loses its branch. | local Ollama (`nimble`) |
| `exception-traits-llm` | The same split in the llm node: prose instead of a function call routes; a provider error past its retries still marks the node red and stops the run. | hosted router + token |
| `plugin-never-started-fanout` | A node whose plugin was never up routes **nowhere** instead of firing all six ports. | **manual**: stop the llm plugin first |
| `ai-decision-bench-nimble` | 24 runs of one decision against a local model: confidence tracks difficulty, and the port matches the category. | local Ollama, **slow** |

Two cases do not run unattended. `plugin-never-started-fanout` needs the llm
plugin stopped before the run and an engine built past `fractal-core` `7705f97`
(an older one still fans out to all six ports), so it is gated behind
`--include-manual`. `ai-decision-bench-nimble` is 24 serial local decisions, so
it is tagged `slow`.

The two network cases talk to a hosted OpenAI-compatible router, so they test the
release and the internet at once. A failure there is worth reading before
believing.

---

## Files

| | |
|---|---|
| `flotest` | the runner — stdlib Python 3, no dependencies |
| `collection/<slug>/` | one case: `flow.json`, `case.json`, optional `seed-context.json` |
| `profiles/*.json` | Node Settings profiles, with `${VAR}` in place of secrets |
| `secrets.env` | the real values — **gitignored** |
| `secrets.env.example` | the empty shape, committed |
