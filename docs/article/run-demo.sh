#!/bin/bash

# Run one demo prompt through a headless Claude Code session and print the
# prompt, the tools it called (in order) and its final answer.
#
#   run-demo.sh "<prompt>" "<allowed tools, comma separated>" [extra claude args...]
#
# Run from the directory the Workspace servers are registered for.

PROMPT=$1
ALLOWED=$2
shift 2

echo "> $PROMPT"
echo
timeout 600 claude -p "$PROMPT" --allowedTools "$ALLOWED" "$@" \
    --output-format stream-json --verbose 2>/dev/null | python3 -c '
import json, sys
calls, ok, final = [], {}, ""
for line in sys.stdin:
    try:
        e = json.loads(line)
    except ValueError:
        continue
    for c in (e.get("message") or {}).get("content", []) if e.get("type") in ("assistant", "user") else []:
        if not isinstance(c, dict):
            continue
        if c.get("type") == "tool_use" and c["name"] != "ToolSearch":
            calls.append((c["id"], c["name"], c.get("input", {})))
        elif c.get("type") == "tool_result":
            ok[c["tool_use_id"]] = not c.get("is_error")
    if e.get("type") == "result":
        final = e.get("result", "")
for i, name, args in calls:
    shown = args.get("skill") or args.get("command") or ""
    mark = "✅" if ok.get(i) else "❌"
    print("  " + mark + " " + name + ("  " + shown if shown else ""))
print()
print(final.strip())
'
