#!/usr/bin/env python3
"""Minimal cursor loop — the bench's structure with no model and no plugin.

  start -> seed (js, NO key, commits {q:[1..24], i:0} at $)
            -> gate (rule)  <--- ALSO fed by the back-edge from bump
                 'next' -> bump (js, key 'i', i+1) --back--> gate
                 'done' -> tally (js, key 'done_report') -> {i, qlen}

The only thing that differs from probe_visibility.py is that `gate` has TWO
inbound edges, one of them a loop back-edge. If a run ends with i=0 and
qlen=0, the gate routed 'done' on its first evaluation — the bench's run #5.

Usage: probe_loop.py <mcp-endpoint> [runs]
"""
import json
import sys
import time
import urllib.request
from collections import Counter

URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8026/mcp"
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 30

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

DOC = {
    "flomorphic": {"kind": "workflow", "version": 1},
    "title": "PROBE — loop with q,i PRE-SEEDED in the context",
    "nodes": [
        {"ref": "start", "kind": "startNode", "title": "Start", "position": {"x": 80, "y": 300}},
        {"ref": "gate", "kind": "rule", "title": "More?", "key": "gate_state",
         "position": {"x": 620, "y": 300},
         "data": {"handlers": [{"id": "h1", "name": "next", "tags": ["next"], "title": "Next"},
                               {"id": "h2", "name": "done", "tags": ["done"], "title": "Done"}],
                  "logic_rule": "let q = input.q || []\n"
                                "let decision = input.i < q.length ? 'next' : 'done'\ndecision"}},
        {"ref": "bump", "kind": "js", "title": "Next index", "key": "i",
         "position": {"x": 620, "y": 120},
         "data": {"logic_rule": "let i = input.i + 1\ni\n"}},
        {"ref": "tally", "kind": "js", "title": "Tally", "key": "done_report",
         "position": {"x": 940, "y": 300},
         "data": {"logic_rule": "let out = { i: input.i, qlen: (input.q || []).length }\nout\n"}},
    ],
    "edges": [
        {"from": "start", "to": "gate"},
        {"from": "gate", "to": "bump", "port": "next"},
        {"from": "bump", "to": "gate"},
        {"from": "gate", "to": "tally", "port": "done"},
    ],
}

res = call("flo_import_workflow", workflow=DOC, title=DOC["title"])
flow_id = (res.get("flow") or {}).get("id")
print(f"probe flow: {flow_id}")
if res.get("compileError"):
    print("  compileError:", res["compileError"])
for p in (res.get("problems") or [])[:3]:
    print("  lint:", (p.get("message") if isinstance(p, dict) else p))

seen, durations = Counter(), []
for i in range(RUNS):
    ctx = call("flo_upsert_context", title=f"seeded probe {i}",
               context={"q": list(range(1, 25)), "i": 0})["id"]
    started = call("flo_start_process", flowId=flow_id, contextId=ctx,
                   stopOnError=False, executeTimeoutSec=120, processNodeLimit=400)
    proc = started.get("process") or started
    pid = proc.get("pid")
    if started.get("error"):
        print(f"  run {i+1}: launch error {started['error'][:90]}")
        seen["<launch-error>"] += 1
        continue
    for _ in range(150):
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
    rep = body.get("done_report") or {}
    label = f"i={rep.get('i')},qlen={rep.get('qlen')}"
    seen[label] += 1
    durations.append(rec.get("durationMs") or 0)
    flag = "" if rep.get("i") == 24 else "   <-- SHORT"
    print(f"  run {i+1:>3}/{RUNS}  {rec.get('durationMs'):>7}ms  {label}{flag}", flush=True)

print(f"\n{RUNS} runs, median {sorted(durations)[len(durations)//2] if durations else '?'}ms")
for k, v in seen.most_common():
    print(f"  {k:>24} : {v}")
print(f"\nprobe flow left on the install as {flow_id} — delete it when done.")
