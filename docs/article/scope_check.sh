#!/bin/bash
# Ask Google's authorization endpoint about a scope set without signing in:
# a valid request goes to the sign-in page, a bad one to /signin/oauth/error.
CID=$(cat ~/client_id.txt)
CC=$(python3 -c 'import base64,hashlib,secrets;print(base64.urlsafe_b64encode(hashlib.sha256(secrets.token_urlsafe(48).encode()).digest()).rstrip(b"=").decode())')
for sc in "$@"; do
  enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$sc")
  loc=$(curl -s -o /dev/null -w "%{redirect_url}" "https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=$CID&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&code_challenge=$CC&code_challenge_method=S256&state=x&scope=$enc")
  python3 - "$sc" "$loc" <<'PY'
import sys,urllib.parse,base64,re
sc,u=sys.argv[1],sys.argv[2]
p=urllib.parse.urlparse(u); q=urllib.parse.parse_qs(p.query)
print(f"scope={sc}\n  -> {p.path}")
if "authError" in q:
    raw=base64.urlsafe_b64decode(q["authError"][0]+"==")
    m=re.search(rb"(invalid_\w+).{1,3}(Some requested scopes were invalid\.[^}]*\})", raw, re.S)
    if m: print("  ", m.group(1).decode(), "-", m.group(2).decode())
PY
done
