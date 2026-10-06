---
title: "Why Claude Code Signs In to Google Workspace MCP Every Hour"
published: false
description: "Claude Code asks for a refresh token the MCP way, with the offline_access scope. Google issues refresh tokens only through access_type=offline. A step by step check of both sides, with the commands and their output."
tags: claudecode, mcp, googleworkspace, oauth
cover_image: https://raw.githubusercontent.com/xbill9/workspace-mcp-claude/main/docs/article/devto-cover-refresh.5fed71bd.jpg
---

This article provides a step by step investigation of why Claude Code needs a fresh Google sign-in every hour for the Google Workspace remote MCP servers. Each step is a command and its output, from the stored token to the request Claude Code sends to what Google's authorization server accepts.

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

#### 🔎 Tip: Leave offline_access Out of the Pinned Scopes

Claude Code's `oauth.scopes` setting is the one place you could add `offline_access` yourself, and the function in Step 3 keeps it if it is there. Step 5 shows what Google does with it: every sign-in fails with `invalid_scope`.

Claude Code's `oauth` settings (`clientId`, `callbackPort`, `scopes`, `authServerMetadataUrl`) have no field for an extra authorization parameter, so `access_type=offline` has no setting either.

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

#### Where Does the Fix Belong?

**Google's authorization server.** SEP-2207 puts the decision with the authorization server's metadata and tells MCP servers to stay out of it. If `accounts.google.com` accepted `offline_access` and listed it in `scopes_supported`, Claude Code's existing code would request it, with no change on Anthropic's side, and so would any other client that follows the MCP guidance.

**Claude Code, as a general setting.** An `oauth` field for extra authorization parameters would let any provider's parameter through, `access_type=offline` included, without a Google-specific case in the client.

---

#### So, Which One?

Google supporting `offline_access` is the fix that follows the MCP specification, and it reaches every standards-based MCP client at once. A general authorization-parameter setting in Claude Code would also work and helps with other providers that have their own conventions.

Until one of them lands, plan for a fresh sign-in each working hour, and sign all eight servers in together.

---

#### Summary

The goal of this article was to find why Claude Code needs a fresh Google sign-in every hour for the Workspace MCP servers. The key to the solution was checking each side separately: what Claude Code stores and sends, what Google's metadata lists, and what Google's authorization endpoint accepts. The results were:

- ⚠️ **Claude Code stores no refresh token** for the Workspace servers, so each sign-in ends with its one-hour access token.
- 🟢 **Claude Code follows the MCP guidance**: it adds `offline_access` when the authorization server lists it in `scopes_supported`.
- ❌ **Google lists `offline_access` nowhere** and rejects it with `invalid_scope`, the same answer as for a made-up scope.
- 🟢 **`access_type=offline` works**: the same sign-in with that parameter returns a refresh token that renews without a browser.
- ⚠️ **Claude Code has no setting** for an extra authorization parameter, and pinning `offline_access` breaks every sign-in.

Scope: one Google Workspace account in the Developer Preview, one Google Cloud project with an Internal consent screen and one Web application OAuth client, Claude Code 2.1.291 on Linux, checked on 2026-10-06. The refresh test used the Gmail server only. Claude Code's behaviour comes from its sign-in URL and the function quoted in Step 3; other MCP clients were not tested.

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
