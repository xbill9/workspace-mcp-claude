# Known issues: sign-in

Two limits on how long Claude Code stays signed in to the Workspace MCP
servers. Both were measured on 2026-10-04 with Claude Code 2.1.289, one Web
application OAuth client shared by all eight servers, and an Internal consent
screen. Neither has a fix in this setup; plan around them.

## 1. Sign-ins last about an hour

Google returns an access token and no refresh token, so Claude Code cannot
renew a sign-in. Each server needs signing in again about an hour after its
last sign-in.

Evidence:

- Every Workspace entry in Claude Code's credential store has `accessToken`
  and `expiresAt` and no `refreshToken`; `expiresAt` is one hour after
  sign-in.
- The authorization URL Claude Code builds carries `response_type`,
  `client_id`, PKCE, `redirect_uri`, `state`, `scope` and `resource`, and no
  `access_type=offline`, which is the parameter Google requires before it
  issues a refresh token.
- Google's metadata does not advertise an `offline_access` scope, so Claude
  Code's automatic `offline_access` request does not apply.
- Claude Code's `oauth` server config accepts `clientId`, `callbackPort`,
  `scopes` and `authServerMetadataUrl`; none of them adds an authorization
  parameter.

## 2. A repeat People sign-in revokes the other servers' tokens

Signing the People server in again makes Google revoke the tokens of every
other server signed in before it, all issued through the same OAuth client,
while those tokens still have most of their hour left. Reproduced twice.

Evidence:

| Sign-in order | Result (Google tokeninfo) |
|---|---|
| Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat, People (first time for all) | 8 of 8 valid; `mcp_test.sh` passed 8 of 8 |
| People again | Gmail through Chat rejected (HTTP 400), People valid |
| Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat, People | Gmail through Chat valid after each other's sign-ins; after People, the seven rejected, People valid |
| People, then Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat | 8 of 8 valid; `mcp_test.sh` passed 8 of 8 |

Sign-ins for the other seven servers revoke neither each other nor People.
People's repeat sign-in differs in one visible way: Google first shows "Sign in
to Workspace MCP Servers" (name and profile picture) and adds a `profile`
scope to the grant. Why Google revokes the other tokens is unconfirmed.

After a revocation, Claude Code's debug log shows
`Failed to fetch tools: Unauthorized` for the affected servers, and their tools
are missing from new sessions.

### Why it is easy to miss

- `claude mcp list` keeps showing `✔ Connected`: these servers answer the
  connection handshake without a valid token.
- The stored expiry time still shows minutes left.
- In a session, the server's tools are simply absent, so Claude reports that
  it has no Gmail or Drive tools rather than an authentication error.

`mcp_status.sh --verify` asks Google about each token and reports `revoked`.
`mcp_test.sh` reports the server as `NOT CALLED` (tools never loaded) or
`FAIL`.

## Working with these limits

- Sign in People first, then the other seven, in one pass; then run
  `mcp_status.sh --verify` and `mcp_test.sh` straight away. `bootstrap.sh`
  uses this order.
- When People needs signing in again, sign the other seven in again after it.
  Any other server can be signed in again on its own.
- `mcp_login.sh start` drops the server's current sign-in immediately, so do
  not use it on a server that still works.
- Before a working session, run `mcp_status.sh --verify`; if any token is
  `revoked` or `expired`, sign everything in again.

## Options not yet tested

- One OAuth client per server, so no two servers share a grant.
- The same full scope set (all 21) pinned on every server, so every sign-in
  requests an identical grant.
- Claude.ai or Claude Desktop custom connectors, which run their own OAuth
  flow through `https://claude.ai/api/mcp/auth_callback`.
