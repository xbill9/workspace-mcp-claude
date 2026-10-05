#!/bin/bash

# Sign-in status of the Google Workspace MCP servers in Claude Code.
#
#   mcp_status.sh [--verify]
#
# For each server: whether it is registered for this directory (from
# `claude mcp list`), whether Claude Code holds a token for it, minutes until
# that token expires, and whether a refresh token exists. Prints names, expiry
# times and valid/invalid only; token values are never printed.
#
# Without a refresh token Claude Code cannot renew a sign-in, so the server
# needs signing in again once the minutes reach zero.
#
# --verify also asks Google (oauth2.googleapis.com/tokeninfo) whether each
# token is still accepted. A token can be revoked before it expires, for
# example when another server signs in through the same OAuth client; the
# expiry time alone does not show that. Each token goes only to Google, the
# service that issued it.

LIST=$(claude mcp list 2>&1)
VERIFY=0
[ "$1" = "--verify" ] && VERIFY=1

python3 - "$LIST" "$VERIFY" <<'EOF'
import json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

verify = sys.argv[2] == "1"

servers = ["gmail", "drive", "docs", "sheets", "slides", "calendar", "chat", "people"]
listed = {}
for line in sys.argv[1].splitlines():
    m = re.match(r"^(\w[\w-]*): .* - (.+)$", line)
    if m:
        listed[m.group(1)] = m.group(2).strip()

tokens = {}
path = os.path.expanduser("~/.claude/.credentials.json")
try:
    store = json.load(open(path)).get("mcpOAuth", {})
except (OSError, ValueError):
    store = {}
now = time.time()
for key, entry in store.items():
    if not isinstance(entry, dict) or not entry.get("accessToken"):
        continue
    name = entry.get("serverName") or key.split("|")[0]
    exp = entry.get("expiresAt") or 0
    exp = exp / 1000 if exp > 1e11 else exp
    left = (exp - now) / 60 if exp else None
    prev = tokens.get(name)
    if prev is None or (left or -1e9) > (prev[0] or -1e9):
        tokens[name] = (left, bool(entry.get("refreshToken")), entry["accessToken"])

def accepted(token):
    data = urllib.parse.urlencode({"access_token": token}).encode()
    try:
        urllib.request.urlopen("https://oauth2.googleapis.com/tokeninfo", data=data, timeout=15)
        return True
    except urllib.error.HTTPError:
        return False

print(f"{'server':<9} {'registered':<11} {'token':<8} {'min left':>8}  refresh")
signed_in = 0
revoked = 0
for s in servers:
    reg = "yes" if s in listed else "no"
    if s in tokens:
        left, refresh, token = tokens[s]
        live = left is None or left > 0
        tok = "valid" if live else "expired"
        if live and verify and not accepted(token):
            live, tok = False, "revoked"
            revoked += 1
        signed_in += live
        mins = "-" if left is None else f"{left:.0f}"
        ref = "yes" if refresh else "no"
    else:
        tok, mins, ref = "none", "-", "-"
    print(f"{s:<9} {reg:<11} {tok:<8} {mins:>8}  {ref}")

label = "a token Google accepts" if verify else "an unexpired token"
print(f"\n{signed_in} of {len(servers)} servers hold {label}.")
if revoked:
    print(f"{revoked} token(s) were revoked before expiry; sign those servers in again.")
if not verify:
    print("Expiry alone does not show revocation; add --verify to ask Google.")
if any(not r for _, r, _ in tokens.values()):
    print("Tokens without refresh expire after about an hour; sign in again with "
          "/mcp or mcp_login.sh when they do.")
EOF
