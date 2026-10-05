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

## 2. A later sign-in can revoke earlier ones

Signing one server in again made Google revoke the tokens of the other seven
servers, all issued through the same OAuth client, while those tokens still
had about 35 minutes left.

Evidence, in order:

1. Eight servers signed in one after another; `mcp_test.sh` passed 8 of 8.
2. The People server was signed in again.
3. Google's tokeninfo endpoint rejected the Gmail, Drive, Docs, Sheets,
   Slides, Calendar and Chat tokens (HTTP 400) and accepted People's.
4. Claude Code's debug log showed `Failed to fetch tools: Unauthorized` for
   those servers, and their tools were missing from new sessions.

The first round of eight sequential sign-ins did not revoke each other: all
eight passed together. The revocations followed a repeat sign-in for a server
that already held a grant. The exact trigger on Google's side is unconfirmed.

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

- Sign in all servers in one pass, then run `mcp_status.sh --verify` and
  `mcp_test.sh` straight away.
- Avoid signing in a single server that is already signed in. When one server
  needs it, sign in all of them again in one pass.
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
