# Using the servers from more than one MCP client

The same eight servers can be used from Claude Code, Codex CLI, Antigravity CLI
and Gemini CLI. Each client signs in differently, and the differences decide
what has to be set up on the OAuth client, how broad the grant is, where the
tokens end up and how long a sign-in lasts. Measured on 2026-10-06 against the
Gmail server, all clients on the one Web application OAuth client from
`claude_setup.sh`. Evidence: `docs/article/evidence/other-clients-2026-10-06.txt`
(authorization URLs) and `docs/article/evidence/other-clients-signin-2026-10-06.txt`
(completed sign-ins, renewal, revocation).

## How each client signs in

| | Claude Code 2.1.291 | Codex CLI 0.158.0 | Antigravity CLI 1.3.0 | Gemini CLI |
|---|---|---|---|---|
| Config | `claude mcp add-json` (`claude_setup.sh`) | `~/.codex/config.toml`, `[mcp_servers.<name>.oauth]` | `~/.gemini/config/mcp_config.json`, `"oauth": {"clientId", "clientSecret"}` | `.gemini/settings.json` in this repo |
| Client secret in config | no (credential store) | yes, `config.toml` | yes, `mcp_config.json` | no, `${CLIENT_SECRET}` from the environment |
| Redirect URI | `http://localhost:8765/callback` | `callback_url`; `codex mcp add` writes `http://127.0.0.1/callback` | `https://antigravity.google/oauth-callback`, fixed | not recorded here |
| Scopes requested | pinned per server | `--scopes` on `codex mcp login` | every scope the server lists; for Gmail 11, including `https://mail.google.com/` | pinned per server in `settings.json` |
| `access_type=offline` | no | no | yes, with `prompt=consent` | not recorded here |
| Refresh token stored | no | no (`refresh_token: null`) | yes | not recorded here |
| Tokens stored in | Claude Code's credential store | the desktop keyring, or `$CODEX_HOME/.credentials.json` (mode 600) with `mcp_oauth_credentials_store = "file"` | `~/.gemini/antigravity-cli/mcp_oauth_tokens.json`, mode 644, with the client secret | not recorded here |
| Sign-in lasts | 1 hour | 1 hour | renews without a browser | not recorded here |
| Finishing the sign-in | browser returns to the local listener | browser, or `--no-browser` and paste the callback URL | paste the code shown on the `antigravity.google` page | `/mcp auth <name>` |

## Per client

**Codex CLI.** `codex mcp add` with `--oauth-client-id` and
`--oauth-client-secret` writes both into `config.toml`, then starts a sign-in
and waits for the browser. Its authorization request matches Claude Code's
(PKCE, `scope`, `resource`, no `access_type`), and Google issues no refresh
token, so a Codex sign-in also lasts an hour. `codex mcp logout` deletes the
local credential and does not revoke it at Google.

**Antigravity CLI.**

- With no `oauth` block it refuses: `OAuth client ID required: server supports
  neither client ID metadata documents nor dynamic client registration`.
  `agy mcp add` has no OAuth flags, so the block is added to
  `mcp_config.json` by hand.
- Print mode (`agy -p`) does not start a sign-in; use `/mcp` → the server →
  Authenticate. Google redirects to `antigravity.google/oauth-callback`, which
  shows the authorization code to paste back into the CLI.
- It requests every scope in the server's metadata. For Gmail that includes
  `https://mail.google.com/`, which Google's consent page describes as "Read,
  compose, send, and permanently delete all your email from Gmail". No setting
  to narrow it was found.
- The consent page names the OAuth client's app ("Workspace MCP Servers"
  here), not Antigravity, and, with Claude Code's scopes already granted,
  says the app "wants additional access".
- It stores the access token, the refresh token and the client secret
  together in `mcp_oauth_tokens.json`, mode 644. In a home directory with
  mode 755 (the default on many Linux systems) other local users can read it.
- Renewal works: with the stored expiry in the past, the next call fetched a
  new access token with the same refresh token, no browser.
- It trusts the stored expiry. An access token that Google rejects while the
  expiry is in the future fails with `tools/list: Unauthorized` and is not
  refreshed.
- It updates itself (1.2.12 to 1.3.0 during these tests).

## What one shared OAuth client means

All clients can use the one Web application client, provided it lists every
redirect URI:

- `http://localhost:8765/callback` (Claude Code; Codex with `callback_url` set to it)
- `https://antigravity.google/oauth-callback` (Antigravity CLI)
- `https://claude.ai/api/mcp/auth_callback` (claude.ai / Claude Desktop connectors)
- Gemini CLI's redirect URI

To Google, one OAuth client is one app with one grant per user, and every
client's sign-in adds to that grant. Measured: revoking one Codex access token
also invalidated Antigravity's access token and refresh token
(`invalid_grant: Token has been expired or revoked.`) and the refresh token
held for Claude Code's `headersHelper`. Claude Code revokes the old token on
every re-sign-in, so signing in a working server in Claude Code ends every
other client's sign-in on the same OAuth client, including the ones that hold
refresh tokens.

The grant is also cumulative: after Antigravity's sign-in, the app the user
approved holds full Gmail access, whichever client asked for it.

## One OAuth client per MCP client

A separate Web application client for each MCP client (same project, same
consent screen) gives:

- **Separate grants.** A sign-in or revoke in one tool leaves the others signed in.
- **Separate scope sets.** Antigravity's full-mailbox grant stays with
  Antigravity's client instead of widening the app the other clients use.
- **One redirect URI per client**, and revocation per tool from the Google
  Account's third-party access page, if each client gets its own app name.

The cost is one console step per client and one set of `client_id` /
`client_secret` files per client. The consent screen, its scopes and the
enabled APIs stay shared. Not run here yet.

## Setup per client today

- Claude Code: `claude_setup.sh` (scripted).
- Gemini CLI: `.gemini/settings.json` plus `save_oauth.sh` (checked in).
- Codex CLI and Antigravity CLI: by hand, one server at a time, as above.
  The server URLs and scopes are in `servers.md`; Antigravity ignores the
  scopes. Every Workspace scope Antigravity requests must be allowed on the
  consent screen.
