#!/usr/bin/env python3
"""Sign in to Google with chosen authorization parameters and record what comes back.

Tests the two sign-in limits in known-issues.md outside Claude Code, with the
same OAuth client, redirect URI and scopes that claude_setup.sh registers.

  oauth_probe.py signin <label> <server> [key=value ...]
      Builds the authorization URL (PKCE, state, resource, the server's pinned
      scopes, plus any extra parameters such as access_type=offline), prints it,
      waits on localhost:$CALLBACK_PORT/callback for Google's redirect, exchanges
      the code and records the result. Open the URL in a browser on this machine.
  oauth_probe.py check
      Asks Google's tokeninfo whether each recorded access token is still valid.
  oauth_probe.py refresh <label>
      Uses that sign-in's refresh token to get a new access token.
  oauth_probe.py revoke
      Revokes every recorded refresh and access token, and deletes the token file.

Tokens are kept in $PROBE_DIR/tokens.json (mode 600). The evidence log,
$PROBE_DIR/log.jsonl, records parameters, scopes, expiry and whether a refresh
token was issued, never a token value.
"""
import base64, hashlib, http.server, json, os, secrets, sys, time, urllib.parse, urllib.request

G = "https://www.googleapis.com/auth"
SERVERS = {
    "gmail": ("https://gmailmcp.googleapis.com/mcp/v1", f"{G}/gmail.readonly {G}/gmail.compose"),
    "people": ("https://people.googleapis.com/mcp/v1",
               f"{G}/directory.readonly {G}/userinfo.profile {G}/contacts.readonly"),
    "drive": ("https://drivemcp.googleapis.com/mcp/v1", f"{G}/drive.readonly {G}/drive.file"),
}
AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN = "https://oauth2.googleapis.com/token"
DIR = os.path.expanduser(os.environ.get("PROBE_DIR", "~/.cache/oauth-probe"))
PORT = int(os.environ.get("CALLBACK_PORT", "8765"))
REDIRECT = f"http://localhost:{PORT}/callback"


def read(path):
    return open(os.path.expanduser(path)).read().strip()


def post(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    try:
        with urllib.request.urlopen(url, data=data, timeout=20) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def tokens():
    p = os.path.join(DIR, "tokens.json")
    return json.load(open(p)) if os.path.exists(p) else {}


def save(store):
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    p = os.path.join(DIR, "tokens.json")
    with open(os.open(p, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(store, f, indent=1)


def log(entry):
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    entry["at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    with open(os.path.join(DIR, "log.jsonl"), "a") as f:
        f.write(json.dumps(entry) + "\n")
    print(json.dumps(entry, indent=1))


def signin(label, server, extra):
    resource, scopes = SERVERS[server]
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    params = {"response_type": "code", "client_id": read("~/client_id.txt"), "redirect_uri": REDIRECT,
              "scope": scopes, "state": state, "code_challenge": challenge,
              "code_challenge_method": "S256", "resource": resource}
    params.update(extra)
    print("Open this URL in a browser on this machine:\n")
    print(AUTH + "?" + urllib.parse.urlencode(params) + "\n", flush=True)

    got = {}

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            got.update({k: v[0] for k, v in q.items()})
            self.send_response(200); self.end_headers()
            self.wfile.write(b"Done. You can close this tab.")

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", PORT), H)
    srv.timeout = 600
    while "code" not in got and "error" not in got:
        srv.handle_request()
    if got.get("state") != state or "code" not in got:
        sys.exit(f"sign-in failed: {got.get('error', 'state mismatch')}")

    status, t = post(TOKEN, {"grant_type": "authorization_code", "code": got["code"],
                             "redirect_uri": REDIRECT, "client_id": read("~/client_id.txt"),
                             "client_secret": read("~/client_secret.txt"), "code_verifier": verifier})
    if status != 200:
        sys.exit(f"token exchange failed: {status} {t}")
    store = tokens()
    store[label] = {"server": server, "access_token": t["access_token"],
                    "refresh_token": t.get("refresh_token"), "issued": int(time.time())}
    save(store)
    log({"step": "signin", "label": label, "server": server, "extra": extra,
         "granted_scope": sorted(t.get("scope", "").split()), "expires_in": t.get("expires_in"),
         "refresh_token_issued": "refresh_token" in t})


def tokeninfo(access):
    return post("https://oauth2.googleapis.com/tokeninfo", {"access_token": access})


def check():
    for label, v in tokens().items():
        status, info = tokeninfo(v["access_token"])
        log({"step": "check", "label": label, "server": v["server"], "http": status,
             "valid": status == 200, "expires_in": info.get("expires_in"),
             "error": info.get("error_description") or info.get("error")})


def refresh(label):
    v = tokens()[label]
    if not v.get("refresh_token"):
        sys.exit(f"{label}: no refresh token was issued")
    status, t = post(TOKEN, {"grant_type": "refresh_token", "refresh_token": v["refresh_token"],
                             "client_id": read("~/client_id.txt"), "client_secret": read("~/client_secret.txt")})
    entry = {"step": "refresh", "label": label, "http": status,
             "error": t.get("error_description") or t.get("error")}
    if status == 200:
        store = tokens(); store[label]["access_token"] = t["access_token"]; save(store)
        s2, _ = tokeninfo(t["access_token"])
        entry.update({"expires_in": t.get("expires_in"), "new_token_valid": s2 == 200})
    log(entry)


def revoke():
    for label, v in tokens().items():
        for kind in ("refresh_token", "access_token"):
            if v.get(kind):
                status, _ = post("https://oauth2.googleapis.com/revoke", {"token": v[kind]})
                print(f"{label} {kind}: revoke HTTP {status}")
    os.remove(os.path.join(DIR, "tokens.json"))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["signin"] and len(a) >= 3 and a[2] in SERVERS:
        signin(a[1], a[2], dict(kv.split("=", 1) for kv in a[3:]))
    elif a == ["check"]:
        check()
    elif a[:1] == ["refresh"] and len(a) == 2:
        refresh(a[1])
    elif a == ["revoke"]:
        revoke()
    else:
        sys.exit(__doc__)
