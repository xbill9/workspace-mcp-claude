#!/usr/bin/env python3
"""Claude Code headersHelper for a Google Workspace MCP server.

Prints {"Authorization": "Bearer <access token>"} for the server Claude Code
names in CLAUDE_CODE_MCP_SERVER_NAME. The refresh token comes from an
oauth_probe.py sign-in made with access_type=offline under the same label:

  PROBE_DIR=~/.cache/oauth-probe python3 oauth_probe.py signin gmail gmail \
      access_type=offline prompt=consent

Reuses the stored access token while it has more than 5 minutes left (Claude
Code does not cache helper output), otherwise trades the refresh token for a
new one. Claude Code gives a helper 10 seconds.
"""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request

DIR = os.path.expanduser(os.environ.get("PROBE_DIR", "~/.cache/oauth-probe"))
STORE = os.path.join(DIR, "tokens.json")
LABEL = os.environ.get("CLAUDE_CODE_MCP_SERVER_NAME") or sys.exit("no CLAUDE_CODE_MCP_SERVER_NAME")


def read(path):
    return open(os.path.expanduser(path)).read().strip()


store = json.load(open(STORE))
t = store.get(LABEL) or sys.exit(f"{LABEL}: no sign-in in {STORE}")
if not t.get("refresh_token"):
    sys.exit(f"{LABEL}: sign in again with access_type=offline prompt=consent")

if t.get("expires_at", 0) - time.time() < 300:
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token", "refresh_token": t["refresh_token"],
        "client_id": read("~/client_id.txt"), "client_secret": read("~/client_secret.txt"),
    }).encode()
    try:
        with urllib.request.urlopen("https://oauth2.googleapis.com/token", data=data, timeout=8) as r:
            new = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"{LABEL}: refresh failed, HTTP {e.code}")
    t["access_token"] = new["access_token"]
    t["expires_at"] = int(time.time()) + int(new["expires_in"])
    with open(os.open(STORE, os.O_WRONLY | os.O_TRUNC, 0o600), "w") as f:
        json.dump(store, f, indent=1)

print(json.dumps({"Authorization": f"Bearer {t['access_token']}"}))
