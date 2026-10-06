# Known issues: sign-in

Two limits on how long Claude Code stays signed in to the Workspace MCP
servers, measured on 2026-10-04 and 2026-10-06 with Claude Code 2.1.289 and
2.1.291, one Web application OAuth client shared by all eight servers, and an
Internal consent screen. Neither has a fix in this setup; plan around them.

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
- The same Gmail sign-in made outside Claude Code (`oauth_probe.py`) with
  `access_type=offline&prompt=consent` added returned a refresh token, and
  that refresh token returned a new access token without a browser
  (2026-10-06). The missing parameter is the whole gap.

## 2. Signing a server in again revokes every server's token

Starting a new sign-in for a server whose token still works makes Claude Code
revoke that token at Google's revocation endpoint, and Google revokes the
whole grant for the OAuth client: every server's access token, and any refresh
token, all at once. All eight servers share one OAuth client, so to Google
they are one app with one grant. Measured on 2026-10-06 with Claude Code
2.1.291.

Evidence:

| Step | Result (Google tokeninfo) |
|---|---|
| Gmail, then People, then People again, signed in outside Claude Code (`oauth_probe.py`) | Gmail valid after both People sign-ins |
| Revoke one People access token | Gmail and both People tokens rejected |
| Fresh Gmail and Drive; revoke the Drive access token | Gmail rejected too |
| Gmail and Drive signed in through Claude Code; `claude mcp login drive` started | Gmail `revoked` with 58 minutes left |
| A Gmail refresh token issued before these revocations | `Token has been expired or revoked` |

After a revocation, Google shows the full permissions page again on the next
sign-in of every server, because the grant is gone.

A sign-in on its own revokes nothing; the revoke of the old token does. A
server whose token is already revoked can be signed in again on its own: on
2026-10-04, seven sign-ins in a row after a revocation cancelled nothing. An
expired token should behave the same, since Google rejects it outright. The 2026-10-04 runs
pointed at People only because People was the one server re-signed while its
token still worked: the other seven had already been revoked by then.

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

- Sign all eight in together, in any order, once their tokens have expired;
  then run `mcp_status.sh --verify` and `mcp_test.sh` straight away.
- Never sign in again a server whose token still works: it signs every server
  out. A server whose token is `revoked` (or `expired`) can be signed in on
  its own.
- `mcp_login.sh start` revokes the server's current token immediately, and
  with it every other server's, whether or not the new sign-in finishes.
- Before a working session, run `mcp_status.sh --verify`; if any token is
  `revoked` or `expired`, sign in the ones that are.

## Options not yet tested

- One OAuth client per server, so no two servers share a grant and a revoke
  reaches only its own server.
- Claude.ai or Claude Desktop custom connectors, which run their own OAuth
  flow through `https://claude.ai/api/mcp/auth_callback`.
