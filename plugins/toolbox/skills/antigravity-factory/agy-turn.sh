#!/usr/bin/env bash
# Run one headless Antigravity turn and summarize it.
# Usage: agy-turn.sh <repo_wsl> <prompt_file_wsl> <out_prefix_wsl> [conversation_id]
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
repo=$1 prompt=$2 out=$3 conv=${4:-}
cd "$repo" || { echo "cannot cd to $repo"; exit 2; }
args=(-p "$(cat "$prompt")" --output-format stream-json --mode accept-edits --print-timeout "${AGY_TIMEOUT:-45m}")
[ -n "$conv" ] && args+=(--conversation "$conv")
agy "${args[@]}" > "$out.ndjson" 2> "$out.stderr"
rc=$?
python3 - "$out.ndjson" "$out.stderr" <<'PY' | tee "$out.summary.txt"
import json, sys, collections
conv = status = response = None; denied = []; tools = collections.Counter(); files = set(); cmds = []; errors = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try: d = json.loads(line)
    except ValueError: continue
    if d.get("event") == "init": conv = d.get("conversation_id")
    elif d.get("event") == "step_update":
        s = d["step_update"]
        if s.get("step_type") != "tool" or s.get("state") not in ("DONE", "ERROR"): continue
        ti = s.get("tool_info", {}); name = ti.get("name", "?"); p = ti.get("parameters") or {}
        tools[name] += 1
        if s.get("state") == "ERROR": errors.append(f"{name}: {json.dumps(p)[:160]}")
        for k, v in p.items():
            if isinstance(v, str) and ("file" in k.lower() or "path" in k.lower()) and "/brain/" not in v: files.add(v)
        if name == "run_command": cmds.append(p.get("CommandLine", ""))
    elif d.get("event") == "result":
        r = d["result"]; conv = r.get("conversation_id", conv); status = r.get("status")
        response = r.get("response"); denied = r.get("denied_actions", [])
print(f"conversation_id: {conv}\nstatus: {status}")
print("tools:", dict(tools))
print("files touched:", *sorted(files), sep="\n  ")
print("commands:", *cmds, sep="\n  ")
if denied: print("denied:", denied)
if errors: print("tool errors:", *errors, sep="\n  ")
err = open(sys.argv[2], encoding="utf-8", errors="replace").read().strip()
if err: print("stderr:", err[-1500:])
print("---- response ----\n" + (response or "")[-6000:])
PY
exit $rc
