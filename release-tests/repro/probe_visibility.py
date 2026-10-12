#!/usr/bin/env python3
"""Does a key-less `$` commit become visible to the next node?

One flow, two branches off Start, identical except for HOW the data is written:

  A   seed_a (js, NO key) -> commits {pqa: [1..24]} at $   -> gate_a (rule) reads input.pqa
  B   seed_b (js, key "pqb") -> returns [1..24]            -> gate_b (rule) reads input.pqb

Each gate routes 'has' or 'empty' and a marker records which. Both branches run in
the same process, against the same engine, in the same millisecond window — so a
difference between them is about the commit style and nothing else.

Usage: probe_visibility.py <mcp-endpoint> [runs]
"""
import json
import sys
import time
import urllib.request
from collections import Counter

URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8026/mcp"
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 40


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


def gate(ref, title, reads):
    return {"ref": ref, "kind": "rule", "title": title, "key": f"{ref}_state",
            "data": {"handlers": [{"id": "h1", "name": "has", "tags": ["has"], "title": "Has"},
                                  {"id": "h2", "name": "empty", "tags": ["empty"], "title": "Empty"}],
                     "logic_rule": f"let q = input.{reads} || []\n"
                                   f"let decision = q.length > 0 ? 'has' : 'empty'\ndecision"}}


def mark(ref, key, val):
    return {"ref": ref, "kind": "js", "title": f"{key}={val}", "key": key,
            "data": {"logic_rule": f"'{val}'\n"}}


DOC = {
    "flomorphic": {"kind": "workflow", "version": 1},
    "title": "PROBE — is a key-less $ commit visible to the next node?",
    "nodes": [
        {"ref": "start", "kind": "startNode", "title": "Start", "position": {"x": 80, "y": 300}},
        # A: key-less, commits a multi-key object at $ — the bench's pattern.
        {"ref": "seed_a", "kind": "js", "title": "A seed (key-less, commits at $)", "key": "",
         "position": {"x": 320, "y": 140},
         "data": {"logic_rule": "let q = []\nlet n = 1\nwhile (n <= 24) { q.push(n); n = n + 1 }\n"
                                "let out = { pqa: q, pia: 0 }\nout\n"}},
        dict(gate("gate_a", "A gate (reads input.pqa)", "pqa"), position={"x": 620, "y": 140}),
        dict(mark("a_has", "saw_a", "has"), position={"x": 900, "y": 80}),
        dict(mark("a_empty", "saw_a", "empty"), position={"x": 900, "y": 200}),
        # B: the same array, written under a key — the control.
        {"ref": "seed_b", "kind": "js", "title": "B seed (keyed 'pqb')", "key": "pqb",
         "position": {"x": 320, "y": 460},
         "data": {"logic_rule": "let q = []\nlet n = 1\nwhile (n <= 24) { q.push(n); n = n + 1 }\nq\n"}},
        dict(gate("gate_b", "B gate (reads input.pqb)", "pqb"), position={"x": 620, "y": 460}),
        dict(mark("b_has", "saw_b", "has"), position={"x": 900, "y": 400}),
        dict(mark("b_empty", "saw_b", "empty"), position={"x": 900, "y": 520}),
    ],
    "edges": [
        {"from": "start", "to": "seed_a"},
        {"from": "seed_a", "to": "gate_a"},
        {"from": "gate_a", "to": "a_has", "port": "has"},
        {"from": "gate_a", "to": "a_empty", "port": "empty"},
        {"from": "start", "to": "seed_b"},
        {"from": "seed_b", "to": "gate_b"},
        {"from": "gate_b", "to": "b_has", "port": "has"},
        {"from": "gate_b", "to": "b_empty", "port": "empty"},
    ],
}

res = call("flo_import_workflow", workflow=DOC, title=DOC["title"])
flow_id = (res.get("flow") or {}).get("id")
print(f"probe flow: {flow_id}")
if res.get("missingActions"):
    print("  missingActions:", res["missingActions"])
if res.get("compileError"):
    print("  compileError:", res["compileError"])

a, b, durations, bad = Counter(), Counter(), [], []
for i in range(RUNS):
    ctx = call("flo_upsert_context", title=f"probe {i}", context={})["id"]
    started = call("flo_start_process", flowId=flow_id, contextId=ctx,
                   stopOnError=False, executeTimeoutSec=60)
    proc = started.get("process") or started
    pid = proc.get("pid")
    if started.get("error"):
        bad.append(started["error"])
        continue
    for _ in range(60):
        time.sleep(0.4)
        rows = call("flo_list_processes", pid=pid, per_page=3).get("list") or []
        rec = rows[0] if rows else {}
        if rec.get("status") not in ("running", "pending", "scheduled", None):
            break
    doc = call("flo_get_context", id=ctx)
    body = doc.get("context")
    if isinstance(body, str):
        body = json.loads(body or "{}")
    body = body or {}
    a[body.get("saw_a", "<none>")] += 1
    b[body.get("saw_b", "<none>")] += 1
    durations.append(rec.get("durationMs") or 0)
    print(f"  run {i+1:>3}/{RUNS}  {rec.get('durationMs'):>6}ms  "
          f"A={body.get('saw_a','<none>'):<7} B={body.get('saw_b','<none>')}", flush=True)

print(f"\n{RUNS} runs, median {sorted(durations)[len(durations)//2] if durations else '?'}ms")
print(f"  A  key-less commit at $   : {dict(a)}")
print(f"  B  keyed write            : {dict(b)}")
if bad:
    print(f"  launch errors: {len(bad)}  e.g. {bad[0][:120]}")
print(f"\nprobe flow left on the install as {flow_id} — delete it when done.")
