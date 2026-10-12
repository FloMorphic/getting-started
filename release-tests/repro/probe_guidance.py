#!/usr/bin/env python3
"""Is the designer preamble's own loop recipe race-free?

Three variants of the SAME loop, differing only in how the loop's state is
established before the guard first reads it:

  preamble  the recipe as written: `items` already in the Context, counter
            INIT'd by a js node with key "i" (preamble.md step 1).
  keyed     the collection is also built by a node, but KEYED (key "items"),
            then the keyed counter init. Two keyed writes feeding the guard.
  keyless   the collection + counter built by ONE key-less node committing
            {items, i} at $ — the bench's shape, and what failed.

The guard has the loop back-edge in every variant, so the back-edge is held
constant and the only variable is the write style.

Usage: probe_guidance.py <endpoint> <variant> [runs]
"""
import json
import sys
import time
import urllib.request
from collections import Counter

URL = sys.argv[1]
VARIANT = sys.argv[2]
RUNS = int(sys.argv[3]) if len(sys.argv) > 3 else 20
N = 24

def call(name, **args):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": args}}
    r = urllib.request.Request(URL, data=json.dumps(body).encode(),
                               headers={"Content-Type": "application/json",
                                        "Accept": "application/json, text/event-stream"},
                               method="POST")
    with urllib.request.urlopen(r, timeout=120) as f:
        d = json.load(f)
    if "error" in d:
        raise RuntimeError(d["error"])
    txt = "".join(c.get("text", "") for c in d["result"]["content"])
    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        return {"_text": txt}

BUILD = ("let items = []\nlet n = 1\nwhile (n <= %d) { items.push(n); n = n + 1 }\n" % N)

GUARD = {"ref": "guard", "kind": "rule", "title": "More items?", "key": "guard_state",
         "scope": "$", "position": {"x": 700, "y": 300},
         "data": {"handlers": [{"id": "h1", "name": "next", "tags": ["next"], "title": "Next"},
                               {"id": "h2", "name": "done", "tags": ["done"], "title": "Done"}],
                  "logic_rule": "let items = input.items || []\n"
                                "let decision = input.i < items.length ? 'next' : 'done'\ndecision"}}
LIFT = {"ref": "lift", "kind": "js", "title": "Lift current", "key": "current", "scope": "$",
        "position": {"x": 980, "y": 180},
        "data": {"logic_rule": "let current = (input.items || [])[input.i]\ncurrent\n"}}
ADVANCE = {"ref": "advance", "kind": "js", "title": "Next index", "key": "i", "scope": "$",
           "position": {"x": 1260, "y": 180},
           "data": {"logic_rule": "let i = input.i + 1\ni\n"}}
TALLY = {"ref": "tally", "kind": "js", "title": "Tally", "key": "done_report", "scope": "$",
         "position": {"x": 980, "y": 440},
         "data": {"logic_rule": "let out = { i: input.i, n: (input.items || []).length }\nout\n"}}
START = {"ref": "start", "kind": "startNode", "title": "Start", "position": {"x": 120, "y": 300}}

LOOP_EDGES = [{"from": "guard", "to": "lift", "port": "next"},
              {"from": "lift", "to": "advance"},
              {"from": "advance", "to": "guard"},
              {"from": "guard", "to": "tally", "port": "done"}]

if VARIANT == "preamble":
    # items already in the Context; only the counter is INIT'd, keyed (step 1).
    nodes = [START,
             {"ref": "init", "kind": "js", "title": "Init counter", "key": "i", "scope": "$",
              "position": {"x": 400, "y": 300}, "data": {"logic_rule": "let i = 0\ni\n"}},
             GUARD, LIFT, ADVANCE, TALLY]
    edges = [{"from": "start", "to": "init"}, {"from": "init", "to": "guard"}] + LOOP_EDGES
    seed = {"items": list(range(1, N + 1))}
elif VARIANT == "keyed":
    nodes = [START,
             {"ref": "build", "kind": "js", "title": "Build items (keyed)", "key": "items",
              "scope": "$", "position": {"x": 300, "y": 300},
              "data": {"logic_rule": BUILD + "items\n"}},
             {"ref": "init", "kind": "js", "title": "Init counter", "key": "i", "scope": "$",
              "position": {"x": 500, "y": 300}, "data": {"logic_rule": "let i = 0\ni\n"}},
             GUARD, LIFT, ADVANCE, TALLY]
    edges = [{"from": "start", "to": "build"}, {"from": "build", "to": "init"},
             {"from": "init", "to": "guard"}] + LOOP_EDGES
    seed = {}
elif VARIANT == "keyless":
    nodes = [START,
             {"ref": "seed_all", "kind": "js", "title": "Build items + counter (key-less at $)",
              "key": "", "scope": "$", "position": {"x": 400, "y": 300},
              "data": {"logic_rule": BUILD + "let out = { items: items, i: 0 }\nout\n"}},
             GUARD, LIFT, ADVANCE, TALLY]
    edges = [{"from": "start", "to": "seed_all"}, {"from": "seed_all", "to": "guard"}] + LOOP_EDGES
    seed = {}
else:
    sys.exit("variant must be preamble|keyed|keyless")

DOC = {"flomorphic": {"kind": "workflow", "version": 1},
       "title": f"PROBE guidance — {VARIANT}", "nodes": nodes, "edges": edges}

res = call("flo_import_workflow", workflow=DOC, title=DOC["title"])
flow_id = (res.get("flow") or {}).get("id")
print(f"variant={VARIANT}  flow={flow_id}")
if res.get("compileError"):
    print("  compileError:", res["compileError"])

seen, bad = Counter(), 0
for i in range(RUNS):
    ctx = call("flo_upsert_context", title=f"{VARIANT} {i}", context=dict(seed))["id"]
    started = call("flo_start_process", flowId=flow_id, contextId=ctx,
                   stopOnError=False, executeTimeoutSec=120, processNodeLimit=400)
    proc = started.get("process") or started
    pid = proc.get("pid")
    if started.get("error"):
        time.sleep(1.5)
        started = call("flo_start_process", flowId=flow_id, contextId=ctx,
                       stopOnError=False, executeTimeoutSec=120, processNodeLimit=400)
        proc = started.get("process") or started
        pid = proc.get("pid")
    if started.get("error"):
        seen["<launch-error>"] += 1
        bad += 1
        print(f"  run {i+1:>3}  launch error: {str(started['error'])[:90]}", flush=True)
        continue
    for _ in range(150):
        time.sleep(0.3)
        rows = call("flo_list_processes", pid=pid, per_page=3).get("list") or []
        rec = rows[0] if rows else {}
        if rec.get("status") not in ("running", "pending", "scheduled", None):
            break
    body = call("flo_get_context", id=ctx).get("context")
    if isinstance(body, str):
        body = json.loads(body or "{}")
    rep = (body or {}).get("done_report") or {}
    label = f"i={rep.get('i')},n={rep.get('n')}"
    seen[label] += 1
    if rep.get("i") != N or rep.get("n") != N:
        bad += 1
        print(f"  run {i+1:>3}  {rec.get('durationMs'):>6}ms  {label}   <-- WRONG", flush=True)

print(f"\n{VARIANT}: {RUNS} runs, {RUNS-bad} correct, {bad} wrong")
for k, v in seen.most_common():
    print(f"  {k:>20} : {v}")
