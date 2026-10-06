#!/usr/bin/env python3
"""Claude Code headersHelper using a service account with domain-wide delegation.

NOT RUN: written for the article's option 5; the service account, its
token-creator grant and the Admin console delegation were not set up here.

Mints an access token for DWD_USER with no browser sign-in and no key file:
the IAM Credentials API signs the assertion with the service account's
Google-held key, and Google's token endpoint trades it for an access token.

Needs, once:
  gcloud iam service-accounts create workspace-mcp-dwd
  gcloud iam service-accounts add-iam-policy-binding \
      workspace-mcp-dwd@$PROJECT.iam.gserviceaccount.com \
      --member=user:$YOU --role=roles/iam.serviceAccountTokenCreator
  Admin console > Security > API controls > Domain-wide delegation:
      the service account's client ID and the scopes below.

Env: DWD_SA (service account email), DWD_USER (account to act as).
The caller's own token comes from `gcloud auth print-access-token`.
"""
import json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

G = "https://www.googleapis.com/auth"
SCOPES = {
    "gmail": f"{G}/gmail.readonly {G}/gmail.compose",
    "drive": f"{G}/drive.readonly {G}/drive.file",
    "people": f"{G}/directory.readonly {G}/userinfo.profile {G}/contacts.readonly",
}
TOKEN = "https://oauth2.googleapis.com/token"


def post(url, data, headers):
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=4) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"{url}: HTTP {e.code} {e.read()[:200].decode(errors='replace')}")


label = os.environ.get("CLAUDE_CODE_MCP_SERVER_NAME") or sys.exit("no CLAUDE_CODE_MCP_SERVER_NAME")
sa, user = os.environ["DWD_SA"], os.environ["DWD_USER"]
now = int(time.time())
claims = {"iss": sa, "sub": user, "scope": SCOPES[label], "aud": TOKEN, "iat": now, "exp": now + 3600}
caller = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True,
                        timeout=5).stdout.strip()
signed = post(f"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/{sa}:signJwt",
              json.dumps({"payload": json.dumps(claims)}).encode(),
              {"Authorization": f"Bearer {caller}", "Content-Type": "application/json"})
tok = post(TOKEN, urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                          "assertion": signed["signedJwt"]}).encode(),
           {"Content-Type": "application/x-www-form-urlencoded"})
print(json.dumps({"Authorization": f"Bearer {tok['access_token']}"}))
