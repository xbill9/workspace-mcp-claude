#!/bin/bash

# Read-only end-to-end test of the Google Workspace MCP servers in Claude Code.
#
#   mcp_test.sh [server ...]      (default: all eight)
#
# Runs one headless Claude Code session (`claude -p`) in the current directory,
# allowed only read-only tools, and asks it to call one tool per server. Pass or
# fail per server is computed here from the session's stream-json events (tool
# calls and their is_error flags), not from the model's own summary.
#
# With MCP_SCOPE=local registrations, run it from the directory the servers were
# registered for. Run it after signing in to each one. Exit status is 0 only if every server passes.

SERVERS="${*:-gmail drive docs sheets slides calendar chat people}"
TIMEOUT=${MCP_TEST_TIMEOUT:-600}

# One read-only tool per server. Docs, Sheets and Slides need a file ID, so
# drive.search_files is allowed for finding one.
ALLOWED="mcp__gmail__list_labels,mcp__drive__list_recent_files,mcp__drive__search_files,\
mcp__docs__read_doc,mcp__sheets__get_spreadsheet,mcp__slides__read_presentation,\
mcp__calendar__list_calendars,mcp__chat__search_conversations,mcp__people__get_user_profile"

PROMPT="Test the Google Workspace MCP servers. Read only: change nothing.
For each of these servers, make exactly one call: $SERVERS
- gmail: list_labels
- drive: list_recent_files
- docs: drive search_files for mimeType 'application/vnd.google-apps.document' (pageSize 1), then docs read_doc on it
- sheets: drive search_files for mimeType 'application/vnd.google-apps.spreadsheet' (pageSize 1), then sheets get_spreadsheet on it
- slides: drive search_files for mimeType 'application/vnd.google-apps.presentation' (pageSize 1), then slides read_presentation on it
- calendar: list_calendars
- chat: search_conversations
- people: get_user_profile
Skip servers not in the list. The drive search_files step for docs, sheets and slides
is always allowed, even when drive itself is not in the list. If a search finds no
file, skip that server. Reply with one line: done."

EVENTS=$(mktemp)
trap 'rm -f "$EVENTS"' EXIT

echo "Testing: $SERVERS"
timeout "$TIMEOUT" claude -p "$PROMPT" --allowedTools "$ALLOWED" \
    --output-format stream-json --verbose > "$EVENTS" 2>/dev/null

python3 - "$EVENTS" $SERVERS <<'EOF'
import json, sys

path, servers = sys.argv[1], sys.argv[2:]
connected, calls, results = {}, {}, {}
for line in open(path):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if e.get("type") == "system" and e.get("subtype") == "init":
        connected = {s["name"]: s.get("status") for s in e.get("mcp_servers", [])}
    for c in (e.get("message") or {}).get("content", []) if e.get("type") in ("assistant", "user") else []:
        if not isinstance(c, dict):
            continue
        if c.get("type") == "tool_use" and c.get("name", "").startswith("mcp__"):
            calls[c["id"]] = c["name"]
        elif c.get("type") == "tool_result" and c.get("tool_use_id") in calls:
            results[c["tool_use_id"]] = bool(c.get("is_error"))

rows = []
for s in servers:
    ids = [i for i, n in calls.items() if n.startswith(f"mcp__{s}__")]
    ok = [i for i in ids if i in results and not results[i]]
    bad = [i for i in ids if results.get(i)]
    # Tool results decide first: a server still connecting when the session
    # starts reports "pending" in the init event, then answers normally.
    if bad:
        status = "FAIL"
    elif ok:
        status = "PASS"
    elif s not in connected:
        status = "NOT REGISTERED"
    elif connected[s] != "connected":
        status = f"NOT CONNECTED ({connected[s]})"
    else:
        status = "NOT CALLED"
    tools = sorted({calls[i].split("__")[2] for i in ids})
    rows.append((s, status, len(ok), len(bad), ", ".join(tools) or "-"))

print(f"\n{'server':<9} {'result':<16} {'ok':>3} {'err':>4}  tools")
for s, status, ok, bad, tools in rows:
    print(f"{s:<9} {status:<16} {ok:>3} {bad:>4}  {tools}")

passed = sum(1 for r in rows if r[1] == "PASS")
print(f"\n{passed} of {len(rows)} servers passed.")
if passed < len(rows):
    print("NOT CALLED usually means no matching file was found (docs/sheets/slides)"
          " or the session timed out; FAIL means the tool returned an error -"
          " sign in again with /mcp or `claude mcp login <server>`.")
sys.exit(0 if passed == len(rows) else 1)
EOF
