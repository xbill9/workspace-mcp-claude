---
title: "Debugging Claude Code and Google MCP Quirks"
published: false
description: "Claude Code asks for a refresh token the MCP way, with the offline_access scope; Google issues refresh tokens only through access_type=offline. A step by step check of both sides, and the alternatives, from signing in hourly to scripting the token yourself."
tags: claudecode, mcp, googleworkspace, oauth
cover_image: https://raw.githubusercontent.com/xbill9/workspace-mcp-claude/main/docs/article/devto-cover-refresh.5fed71bd.jpg
---

This article provides a step by step investigation of why Claude Code needs a fresh Google sign-in every hour for the Google Workspace remote MCP servers. Each step is a command and its output, from the stored token to the request Claude Code sends to what Google's authorization server accepts, followed by the alternatives and what each one costs to run.

https://github.com/xbill9/workspace-mcp-claude

**Claude Code requests a refresh token with the `offline_access` scope, and only when the authorization server lists that scope. Google lists it nowhere and rejects it as `invalid_scope`. Google issues refresh tokens through its own `access_type=offline` parameter, and with that one parameter the same sign-in returns a refresh token that renews without a browser.**

---

#### What is this article about?

The companion article sets up Claude Code with Google's eight Workspace MCP servers (Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat and People) and lists two sign-in limits:

[MCP Configuration for Google Workspace with Claude Code](https://dev.to/gde/mcp-configuration-for-google-workspace-with-claude-code-11om)

This one takes the first limit apart. Every sign-in lasts about an hour, then the server's tools disappear from Claude Code until you sign in again.

---

#### Access Tokens and Refresh Tokens

An OAuth sign-in hands the app an **access token**. Google's access tokens last one hour, for every app.

Apps that stay signed in for days also hold a **refresh token**. When the access token expires, the app trades the refresh token for a new access token, with no browser and no user.

So a one-hour access token is normal. A one-hour *sign-in* means the app has no refresh token.

---

#### At This Point You Should Have…

- The Workspace MCP servers registered in Claude Code, as in the companion article.
- The repository cloned, for `mcp_status.sh`, `oauth_probe.py` and `scope_check.sh`.
- `curl` and Python 3.

This article used Claude Code 2.1.291.

---

#### Step 1 — Check What Claude Code Stored

`mcp_status.sh --verify` reads each server's stored sign-in and asks Google whether the token is still good:

```bash
./mcp_status.sh --verify
```

```
server    registered  token    min left  refresh
gmail     yes         valid          59  no
drive     yes         valid          60  no
```

The last column is the whole problem. Google issued an access token with no refresh token, so Claude Code has nothing to renew with when the 60 minutes run out.

---

#### Step 2 — Read Claude Code's Sign-in Request

`claude mcp login gmail` prints the URL it sends to Google (client ID, PKCE challenge and state shortened here):

```
https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=<client-id>&code_challenge=…&code_challenge_method=S256&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&state=…&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fgmail.readonly+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fgmail.compose&resource=https%3A%2F%2Fgmailmcp.googleapis.com%2Fmcp%2Fv1
```

The request carries `response_type`, `client_id`, PKCE, `redirect_uri`, `state`, `scope` and `resource`. It has no `offline_access` scope and no `access_type` parameter.

---

#### Step 3 — When Claude Code Asks for a Refresh Token

The MCP specification answers this in SEP-2207, "OIDC-Flavored Refresh Token Guidance". A client that wants a refresh token adds the `offline_access` scope **when the authorization server's metadata lists `offline_access` in `scopes_supported`**. The same guidance tells MCP servers to leave `offline_access` out of their own metadata, because a refresh token is a matter between the client and the authorization server.

[SEP-2207: OIDC-Flavored Refresh Token Guidance](https://modelcontextprotocol.io/seps/2207-oidc-refresh-token-guidance)

Claude Code 2.1.291 implements it as one function:

```js
function oms(e,t){if(e!==null&&e.split(" ").includes("offline_access"))return e;if(!t?.scopes_supported?.includes("offline_access"))return e;return e===null?"offline_access":`${e} offline_access`}
```

`e` is the scope string and `t` the authorization server metadata. If the scopes already include `offline_access`, they go out unchanged. If the metadata does not list it, they go out unchanged. Otherwise `offline_access` is appended.

`offline_access` comes from OpenID Connect, where it "requests that an OAuth 2.0 Refresh Token be issued":

[OpenID Connect Core 1.0, §11 Offline Access](https://openid.net/specs/openid-connect-core-1_0.html#OfflineAccess)

---

#### Step 4 — What Google's Metadata Lists

The Gmail MCP server names `accounts.google.com` as its authorization server:

```bash
curl -s https://gmailmcp.googleapis.com/.well-known/oauth-protected-resource/mcp/v1 | jq "{resource, authorization_servers}"
```

```
{"resource": "https://gmailmcp.googleapis.com/mcp/v1", "authorization_servers": ["https://accounts.google.com/"]}
```

That server publishes two metadata documents, and both leave `offline_access` out:

```bash
curl -s https://accounts.google.com/.well-known/openid-configuration | jq .scopes_supported
curl -s https://accounts.google.com/.well-known/oauth-authorization-server | jq .scopes_supported
```

```
["openid", "email", "profile"]
null
```

The refresh grant itself is supported:

```bash
curl -s https://accounts.google.com/.well-known/oauth-authorization-server | jq .grant_types_supported
```

```
["authorization_code", "refresh_token", "urn:ietf:params:oauth:grant-type:device_code", "urn:ietf:params:oauth:grant-type:jwt-bearer"]
```

So Google can issue refresh tokens, and Claude Code's rule from Step 3 never fires.

---

#### Step 5 — Ask Google for offline_access Anyway

`scope_check.sh` sends a sign-in request for each scope set and reports where Google redirects it, without signing in. A valid request goes to the sign-in page. The first scope set is the check that a valid request passes; the last uses a scope that exists nowhere:

```bash
G=https://www.googleapis.com/auth
./scope_check.sh "$G/gmail.readonly" "$G/gmail.readonly offline_access" "$G/gmail.readonly bogus_scope_xyz"
```

```
scope=https://www.googleapis.com/auth/gmail.readonly
  -> /v3/signin/identifier
scope=https://www.googleapis.com/auth/gmail.readonly offline_access
  -> /signin/oauth/error
   invalid_scope - Some requested scopes were invalid. {valid=[https://www.googleapis.com/auth/gmail.readonly], invalid=[offline_access]}
scope=https://www.googleapis.com/auth/gmail.readonly bogus_scope_xyz
  -> /signin/oauth/error
   invalid_scope - Some requested scopes were invalid. {valid=[https://www.googleapis.com/auth/gmail.readonly], invalid=[bogus_scope_xyz]}
```

Google answers `offline_access` exactly as it answers a made-up scope. Its metadata in Step 4 is accurate: Google leaves `offline_access` out because it does not support it.

---

#### Step 6 — Ask Google the Google Way

Google documents its own parameter for this. The refresh token "is only present in this response if you set the `access_type` parameter to `offline`":

[Using OAuth 2.0 for Web Server Applications | Google for Developers](https://developers.google.com/identity/protocols/oauth2/web-server#offline)

`oauth_probe.py` makes the same Gmail sign-in as Claude Code (same OAuth client, scopes, redirect URI and `resource`) with extra parameters added. `prompt=consent` makes Google show the consent screen again, which is when it issues a refresh token:

```bash
python3 oauth_probe.py signin gmail gmail access_type=offline prompt=consent
```

```
{
 "step": "signin",
 "label": "gmail",
 "server": "gmail",
 "extra": {
  "access_type": "offline",
  "prompt": "consent"
 },
 "granted_scope": [
  "https://www.googleapis.com/auth/gmail.compose",
  "https://www.googleapis.com/auth/gmail.readonly"
 ],
 "expires_in": 3599,
 "refresh_token_issued": true,
 "at": "2026-10-06T09:24:55-0400"
}
```

Trading that refresh token for a new access token, with no browser, returned a token Google's token-info endpoint accepted, with the full hour and both Gmail scopes:

```
2026-10-06T09:27:27-0400 refreshed expires_in=3599
```

One parameter is the whole difference between an hourly sign-in and one that renews.

---

#### Step 7 — Script It Yourself with headersHelper

Claude Code has a second way to authenticate an MCP server. `headersHelper` names a command whose output becomes the request headers:

[Connect Claude Code to tools via MCP | Claude Code Docs](https://code.claude.com/docs/en/mcp)

Per those docs, the command prints a JSON object such as `{"Authorization": "Bearer …"}`. Claude Code runs it at connect and on reconnect, runs it again and retries once when a tool call returns `401` or `403`, does not cache its output, and gives it 10 seconds. When the output carries an `Authorization` header, Claude Code skips its own OAuth for that server.

So the refresh token from Step 6 can drive a server directly. `token_header.py` in the repository is the helper. It reads the server name from `CLAUDE_CODE_MCP_SERVER_NAME` and trades that server's refresh token for a new access token on every call. Claude Code calls it only when a server connects, so one call to Google's token endpoint per connect is the whole cost.

Sign each server in once with offline access (`oauth_probe.py` knows `gmail`, `drive` and `people`; add the others to its `SERVERS` table):

```bash
export PROBE_DIR=~/.cache/oauth-probe
python3 oauth_probe.py signin gmail gmail access_type=offline prompt=consent
```

Then register the server with the helper in place of the `oauth` block:

```json
{
  "type": "http",
  "url": "https://gmailmcp.googleapis.com/mcp/v1",
  "headersHelper": "PROBE_DIR=~/.cache/oauth-probe python3 -I ~/workspace-mcp-claude/docs/article/token_header.py"
}
```

Run through Claude Code 2.1.292 with only that server configured, a request to list Gmail labels returned all 38, with the helper called once per session and no browser.

Refreshing on every call matters. With a stored access token that Google no longer accepts but that still shows 50 minutes left, a helper that reused it was called once, the server still connected, and Gmail's tools were missing from the session:

```text
The tool is missing. ToolSearch returned: "No matching deferred tools found"
```

Claude Code did not call the helper again when `tools/list` was refused. The same stale token with the always-refresh helper returned all 38 labels.

The moving parts, all of them yours:

- **The OAuth client secret**, read from `~/client_secret.txt` on every refresh.
- **A sign-in script** that adds `access_type=offline` and `prompt=consent`, run once per server.
- **A token file** holding one refresh token per server, mode 600.
- **The helper**, which must answer inside 10 seconds, including a call to Google's token endpoint.
- **One config entry per server** with `headersHelper` and no `oauth` block.

The tradeoffs:

- **A refresh token on disk works until someone revokes it.** With an Internal consent screen it has no expiry of its own. Anything that can read the file, or run the helper, can read and draft your mail with nobody present. A keyring (`secret-tool` on Linux) is a better home than a file.
- **Revocation still covers the whole grant.** The tokens share one OAuth client, so revoking any of them signs all of them out, the same as in the companion article.
- **Failures are quiet.** A token Google rejects leaves the server connected with no tools, and nothing prompts for a sign-in.
- **You maintain it.** Token handling is code you now own, on every machine you use.

---

#### Step 8 — Put a Proxy in Front

The helper runs only at connect. A small server on your own machine can renew on demand instead: Claude Code connects to it on localhost with no credentials, and it adds the `Authorization` header to each request and forwards it to Google. `token_proxy.py` in the repository is about 90 lines of Python standard library, reusing the token code from `token_header.py`:

```bash
PROBE_DIR=~/.cache/oauth-probe python3 -I token_proxy.py
```

```json
{
  "type": "http",
  "url": "http://127.0.0.1:8790/gmail/mcp/v1"
}
```

When Google answers `401`, the proxy refreshes the token and retries the request once. With the same stale token as in Step 7, its log shows the repair inside one `tools/list` call, and the session listed all 38 labels:

```text
16:50:20 gmail POST initialize -> 200
16:50:20 gmail POST notifications/initialized -> 202
16:50:20 gmail GET - -> 405
16:50:20 gmail POST tools/list -> 401 refreshing and retrying
16:50:20 gmail POST tools/list -> 200
16:50:24 gmail POST tools/call -> 200
```

`initialize` succeeds with an invalid token, which is why a server can show as connected with no tools. The log also gives one line per call with its JSON-RPC method, a record of what Claude Code did with your mail, with no message content.

The moving parts: the same refresh token and client secret as Step 7, plus a process that has to be running before Claude Code starts, listening on a port any local program can reach.

---

#### 🔎 Tip: Leave offline_access Out of the Pinned Scopes

Claude Code's `oauth.scopes` setting is the one place you could add `offline_access` yourself, and the function in Step 3 keeps it if it is there. Step 5 shows what Google does with it: every sign-in fails with `invalid_scope`.

Claude Code's `oauth` settings (`clientId`, `callbackPort`, `scopes`, `authServerMetadataUrl`) have no field for an extra authorization parameter, so `access_type=offline` has no setting either. `authServerMetadataUrl` can point Claude Code at a metadata document of your own that lists `offline_access`, and Claude Code would then append it, which brings back the `invalid_scope` of Step 5.

---

#### 🔎 Tip: A Refresh Token Goes With the Grant

Refresh tokens end when the user revokes the app's access. With all eight Workspace servers on one OAuth client, signing any working server in again revokes the whole grant, and the refresh token from Step 6 came back `Token has been expired or revoked.` after one. The companion article has the measurements.

---

#### Compare and Contrast

| | `offline_access` scope | `access_type=offline` |
| :--- | :--- | :--- |
| Defined by | OpenID Connect Core §11 | Google |
| How the client sends it | in `scope` | separate query parameter |
| How a client learns it is supported | `scopes_supported` in the server's metadata | Google's documentation |
| MCP guidance (SEP-2207) | ✅ the standard route | not mentioned |
| Claude Code 2.1.291 | ✅ sends it when listed | ❌ never sends it |
| Google | ❌ `invalid_scope` | ✅ refresh token issued |

Each side follows its own documentation, and the two routes never meet.

---

#### What Are the Alternatives?

Six ways to live with it, from no moving parts to the most.

**1. Sign in every hour.** Sign all eight servers in together and check them with `mcp_status.sh --verify` at the start of a session. Nothing to build, and the longest-lived credential on the machine is a one-hour access token. The cost is a browser sign-in per server, every working hour.

**2. headersHelper with your own refresh token.** Step 7. No browser after the first sign-in, and the helper renews in the middle of a session. The cost is a refresh token you store and guard, a script you maintain, and code that holds your client secret.

**3. headersHelper with gcloud.** Let gcloud hold the refresh token: sign in once with `gcloud auth application-default login --client-id-file=… --scopes=…` listing every Workspace scope, and have the helper print `gcloud auth application-default print-access-token`. gcloud sends `access_type=offline` on its own and already renews tokens, so there is no token code to write. Run here, gcloud 587.0.0 set two conditions. It refuses any scope list without `cloud-platform`, and it accepts only a Desktop client: the Web client from `claude_setup.sh` was rejected as `Only client IDs of type 'installed' are allowed`, and relabelled as one it reached Google with `redirect_uri=http://localhost:8085/` and got `redirect_uri_mismatch`. So this route needs a second OAuth client, of type Desktop, and gives one credential every Workspace scope plus full Google Cloud access, in gcloud's credential file.

**4. A local proxy MCP server.** A small server on your machine holds the refresh token, adds the `Authorization` header and forwards each request to `*mcp.googleapis.com`; Claude Code connects to localhost. Step 8. It renews on any `401`, at connect or mid-session, and logs every call. It is also the most code: a process to keep running, Streamable HTTP to pass through, and the same stored refresh token as option 2.

**5. A service account with domain-wide delegation.** A Workspace admin lets a service account act as users, and the helper mints tokens for your account with no user sign-in at all. `dwd_header.py` in the repository is a helper for it that needs no key file: the IAM Credentials API signs the request with the service account's Google-held key. Running it needs a service account, a token-creator role on it and an Admin console delegation, none of which were set up here. The cost is a tenant-wide grant: that service account can act as anyone in the domain for the delegated scopes, which is a large grant for one developer's editor.

**6. The fix upstream.** Google accepting `offline_access` and listing it in `scopes_supported`, or a general Claude Code setting for extra authorization parameters. Nothing to run or store, and Claude Code keeps the refresh token in its own credential store. The cost is waiting.

| Option | Code you own | Browser sign-ins | Long-lived credential | Checked here |
| :--- | :--- | :--- | :--- | :--- |
| 1. Sign in hourly | none | every hour | none | ✅ |
| 2. headersHelper + own token | helper + sign-in script | once per server | refresh token in a file | ✅ |
| 3. headersHelper + gcloud | one-line helper + Desktop client | once, then per session length | gcloud's refresh token, with `cloud-platform` | ⚠️ blocked: needs a Desktop client |
| 4. Local proxy | a server + sign-in script | once per server | refresh token in a file | ✅ |
| 5. Service account | helper | none | a domain-wide grant | ❌ not run |
| 6. Upstream fix | none | once | refresh token in Claude Code's store | n/a |

---

#### How Do Other Clients Ask?

The same Gmail server and OAuth client, set up in two other MCP clients, with each authorization URL captured before sign-in:

| | Claude Code 2.1.291 | Codex CLI 0.158.0 | Antigravity CLI 1.2.12 |
| :--- | :--- | :--- | :--- |
| `access_type=offline` | ❌ | ❌ | ✅ with `prompt=consent` |
| Scopes | pinned per server | passed at login | every scope the server lists, 10 for Gmail |
| Redirect URI | `localhost:8765/callback` | `callback_url` setting | `https://antigravity.google/oauth-callback` |
| Client secret kept in | Claude Code's credential store | `config.toml` | `mcp_config.json` |

Codex sends the same request as Claude Code. Antigravity, Google's own client, sends Google's parameter and asks for every scope Gmail lists, including `gmail.send` and `gmail.modify`. Each client needs its redirect URI on the OAuth client, and every client set up with that one OAuth client shares one grant with Google, so the revocation from the Tip above reaches all of them.

---

#### Where Does the Fix Belong?

**Google's authorization server.** SEP-2207 puts the decision with the authorization server's metadata and tells MCP servers to stay out of it. If `accounts.google.com` accepted `offline_access` and listed it in `scopes_supported`, Claude Code's existing code would request it, with no change on Anthropic's side, and so would any other client that follows the MCP guidance.

**Claude Code, as a general setting.** An `oauth` field for extra authorization parameters would let any provider's parameter through, `access_type=offline` included, without a Google-specific case in the client.

---

#### So, Which One?

For most sessions, option 1: sign all eight in together and accept the hourly sign-in. It adds nothing to guard.

To stop signing in on your own machine, option 2, with the refresh token in a keyring and revoked when the work is done. It is one short script, and each new session starts with a fresh hour.

For sessions that run past the hour, or when you want a record of every call, option 4. It renews whenever Google refuses a token, at the price of a process to keep running.

Option 3 needs a second OAuth client and gives gcloud full Google Cloud access alongside your mail, and option 5 needs a domain-wide grant, which is a lot to hand one developer's editor. Pursue option 6 alongside whichever you pick: Google supporting `offline_access` is the fix that follows the MCP specification, and it reaches every standards-based MCP client at once.

---

#### Summary

The goal of this article was to find why Claude Code needs a fresh Google sign-in every hour for the Workspace MCP servers. The key to the solution was checking each side separately: what Claude Code stores and sends, what Google's metadata lists, and what Google's authorization endpoint accepts. The results were:

- ⚠️ **Claude Code stores no refresh token** for the Workspace servers, so each sign-in ends with its one-hour access token.
- 🟢 **Claude Code follows the MCP guidance**: it adds `offline_access` when the authorization server lists it in `scopes_supported`.
- ❌ **Google lists `offline_access` nowhere** and rejects it with `invalid_scope`, the same answer as for a made-up scope.
- 🟢 **`access_type=offline` works**: the same sign-in with that parameter returns a refresh token that renews without a browser.
- ⚠️ **Claude Code has no setting** for an extra authorization parameter, and pinning `offline_access` breaks every sign-in.
- 🟢 **`headersHelper` with your own refresh token works**: Claude Code listed Gmail labels through it with no browser, as long as the helper refreshes on every call.
- 🟢 **A local proxy also works** and repairs a refused token inside the request, with a log of every call.
- ⚠️ **gcloud needs its own Desktop client** and the `cloud-platform` scope before it will hold Workspace scopes.
- ⚠️ **Every route past the hour stores a long-lived credential**: a refresh token, a gcloud credential or a service account key, held by you instead of Claude Code.

Scope: one Google Workspace account in the Developer Preview, one Google Cloud project with an Internal consent screen and one Web application OAuth client, Claude Code 2.1.291 for Steps 1 to 6 and 2.1.292 for Steps 7 and 8, gcloud 587.0.0, on Linux, checked on 2026-10-06. Options 2 to 4 were run against the Gmail server only, one session each, with Claude Code configured with that one server. Claude Code's sign-in behaviour comes from its sign-in URL, the function quoted in Step 3 and its MCP documentation. Option 3 stopped at Google's redirect check for want of a Desktop client, option 5 was not run, renewal after a full hour inside one session was not timed, and other MCP clients were not tested.

The strategy for diagnosing the hourly sign-in for Google Workspace MCP from Claude Code was validated with an incremental step by step approach.

---

#### References

* [workspace-mcp-claude | GitHub](https://github.com/xbill9/workspace-mcp-claude)
* [Known issues: sign-in | workspace-mcp-claude](https://github.com/xbill9/workspace-mcp-claude/blob/main/plugin/skills/google-workspace-mcp/references/known-issues.md)
* [MCP Configuration for Google Workspace with Claude Code | dev.to](https://dev.to/gde/mcp-configuration-for-google-workspace-with-claude-code-11om)
* [SEP-2207: OIDC-Flavored Refresh Token Guidance | Model Context Protocol](https://modelcontextprotocol.io/seps/2207-oidc-refresh-token-guidance)
* [Authorization | Model Context Protocol Specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
* [OpenID Connect Core 1.0, §11 Offline Access | OpenID Foundation](https://openid.net/specs/openid-connect-core-1_0.html#OfflineAccess)
* [Using OAuth 2.0 for Web Server Applications | Google for Developers](https://developers.google.com/identity/protocols/oauth2/web-server)
* [OpenID Connect | Google for Developers](https://developers.google.com/identity/openid-connect/openid-connect)
* [Google's OpenID configuration | accounts.google.com](https://accounts.google.com/.well-known/openid-configuration)
* [Connect Claude Code to tools via MCP | Claude Code Docs](https://code.claude.com/docs/en/mcp)
