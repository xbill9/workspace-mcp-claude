#!/bin/bash

# Probe each Google Workspace MCP server without credentials and report:
#   - the spec versions it advertises via server/discover (MCP 2026-07-28)
#   - the version it negotiates via a legacy initialize (2025-11-25)
#   - its tool count (tools/list answers without a token)
#   - the scopes in its OAuth protected resource metadata
# All counting and comparison happens in Python; the output is the result.

SERVERS="gmail=gmailmcp drive=drivemcp docs=docsmcp sheets=sheetsmcp slides=slidesmcp calendar=calendarmcp chat=chatmcp people=people"

python3 - "$SERVERS" <<'EOF'
import json, sys, urllib.request

TARGET = "2026-07-28"
LEGACY = "2025-11-25"

def post(url, body, headers):
    h = {"Content-Type": "application/json",
         "Accept": "application/json, text/event-stream"}
    h.update(headers)
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=h)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": {"message": str(e)}}

def get(url):
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}

rows = []
for pair in sys.argv[1].split():
    name, host = pair.split("=")
    url = f"https://{host}.googleapis.com/mcp/v1"

    disc = post(url, {"jsonrpc": "2.0", "id": 1, "method": "server/discover",
                      "params": {"_meta": {
                          "io.modelcontextprotocol/protocolVersion": TARGET,
                          "io.modelcontextprotocol/clientCapabilities": {},
                          "io.modelcontextprotocol/clientInfo": {"name": "mcp_probe", "version": "1"}}}},
                {"MCP-Protocol-Version": TARGET, "Mcp-Method": "server/discover"})
    versions = sorted(disc.get("result", {}).get("supportedVersions") or [])

    init = post(url, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                      "params": {"protocolVersion": LEGACY, "capabilities": {},
                                 "clientInfo": {"name": "mcp_probe", "version": "1"}}}, {})
    negotiated = init.get("result", {}).get("protocolVersion") or "error"

    tl = post(url, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
              {"MCP-Protocol-Version": LEGACY})
    tools = [t["name"] for t in tl.get("result", {}).get("tools", [])]

    prm = get(f"https://{host}.googleapis.com/.well-known/oauth-protected-resource/mcp/v1")
    scopes = prm.get("scopes_supported", []) if isinstance(prm, dict) else []

    rows.append((name, TARGET in versions, versions, negotiated, tools, scopes))

print(f"{'server':<9} {TARGET:<11} {'legacy init':<12} tools")
for name, ok, versions, negotiated, tools, _ in rows:
    print(f"{name:<9} {'yes' if ok else 'no':<11} {negotiated:<12} {len(tools)}")

n_ok = sum(1 for r in rows if r[1])
print(f"\n{n_ok} of {len(rows)} servers advertise {TARGET}; "
      f"{sum(len(r[4]) for r in rows)} tools in total.")

print()
for name, _, versions, _, tools, scopes in rows:
    print(f"[{name}] versions: {', '.join(versions) or '-'}")
    print(f"[{name}] tools: {', '.join(tools)}")
    print(f"[{name}] resource scopes: {len(scopes)}")
EOF
