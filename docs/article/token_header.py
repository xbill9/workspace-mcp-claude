#!/usr/bin/env python3
"""Claude Code headersHelper for a Google Workspace MCP server.

Prints {"Authorization": "Bearer <access token>"} for the server Claude Code
names in CLAUDE_CODE_MCP_SERVER_NAME. The refresh token comes from an
oauth_probe.py sign-in made with access_type=offline under the same label:

  PROBE_DIR=~/.cache/oauth-probe python3 oauth_probe.py signin gmail gmail \
      access_type=offline prompt=consent

Run as a helper it always trades the refresh token for a new access token:
Claude Code calls it only at connect and reconnect, and a stored access token
that Google has stopped accepting would leave the server with no tools. Claude
Code gives a helper 10 seconds. token_proxy.py imports access_token() from
here, which reuses a stored token with more than 5 minutes left.
"""
import json, os, sys, time, urllib.error, urllib.parse, urllib.request

DIR = os.path.expanduser(os.environ.get("PROBE_DIR", "~/.cache/oauth-probe"))
STORE = os.path.join(DIR, "tokens.json")


def read(path):
    return open(os.path.expanduser(path)).read().strip()


def access_token(label, force=False):
    """Return a usable access token for label; refresh when near expiry or forced."""
    store = json.load(open(STORE))
    t = store.get(label)
    if not t:
        raise RuntimeError(f"{label}: no sign-in in {STORE}")
    if not t.get("refresh_token"):
        raise RuntimeError(f"{label}: sign in again with access_type=offline prompt=consent")
    if force or t.get("expires_at", 0) - time.time() < 300:
        data = urllib.parse.urlencode({
            "grant_type": "refresh_token", "refresh_token": t["refresh_token"],
            "client_id": read("~/client_id.txt"), "client_secret": read("~/client_secret.txt"),
        }).encode()
        try:
            with urllib.request.urlopen("https://oauth2.googleapis.com/token", data=data, timeout=8) as r:
                new = json.load(r)
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{label}: refresh failed, HTTP {e.code}")
        t["access_token"] = new["access_token"]
        t["expires_at"] = int(time.time()) + int(new["expires_in"])
        with open(os.open(STORE, os.O_WRONLY | os.O_TRUNC, 0o600), "w") as f:
            json.dump(store, f, indent=1)
    return t["access_token"]


if __name__ == "__main__":
    label = os.environ.get("CLAUDE_CODE_MCP_SERVER_NAME") or sys.exit("no CLAUDE_CODE_MCP_SERVER_NAME")
    try:
        token = access_token(label, force=True)
    except RuntimeError as e:
        sys.exit(str(e))
    print(json.dumps({"Authorization": f"Bearer {token}"}))
