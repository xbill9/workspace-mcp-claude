# Using the servers from more than one MCP client

The same eight servers can be used from Claude Code, Codex CLI, Antigravity CLI
and Gemini CLI. Each client signs in differently, and the differences decide
what has to be set up on the OAuth client and what happens to each client's
sign-in. Measured on 2026-10-06 against the Gmail server with the Web
application OAuth client from `claude_setup.sh`; evidence in
`docs/article/evidence/other-clients-2026-10-06.txt`.

## How each client signs in

| | Claude Code 2.1.291 | Codex CLI 0.158.0 | Antigravity CLI 1.2.12 | Gemini CLI |
|---|---|---|---|---|
| Config | `claude mcp add-json` (`claude_setup.sh`) | `~/.codex/config.toml`, `[mcp_servers.<name>.oauth]` | `~/.gemini/config/mcp_config.json`, `"oauth": {"clientId", "clientSecret"}` | `.gemini/settings.json` in this repo |
| Client secret stored | Claude Code's credential store | in `config.toml`, plain text | in `mcp_config.json`, plain text | `${CLIENT_SECRET}` from the environment (`save_oauth.sh`) |
| Redirect URI | `http://localhost:8765/callback` | `callback_url`; `codex mcp add` writes `http://127.0.0.1/callback` | `https://antigravity.google/oauth-callback`, fixed | not recorded here |
| Scopes requested | pinned per server | `--scopes` on `codex mcp login` | every scope Google lists for the server (Gmail: 10, including `gmail.send` and `gmail.modify`) | pinned per server in `settings.json` |
| `access_type=offline` sent | no | no | yes, with `prompt=consent` | not recorded here |
| Refresh token | none (hourly sign-in) | none expected (same URL shape as Claude Code) | requested; storage and renewal not yet tested | not recorded here |
| Finishing the sign-in | browser returns to the local listener | browser, or `--no-browser` and paste the callback URL | paste the authorization code shown on the `antigravity.google` page | `/mcp auth <name>` |

Notes:

- **Codex** starts a sign-in as soon as `codex mcp add` registers a server
  with OAuth, and waits for the browser. `codex mcp login <name> --no-browser`
  prints the URL instead. The client secret passed to
  `--oauth-client-secret` is written into `config.toml`.
- **Antigravity** refuses to sign in with no `oauth` block:
  `OAuth client ID required: server supports neither client ID metadata
  documents nor dynamic client registration`. Google offers no automatic client
  registration, so a client ID and secret are required. `agy mcp add` has no
  OAuth flags; add the block to `mcp_config.json` by hand. Print mode
  (`agy -p`) does not start a sign-in; use `/mcp` → the server →
  Authenticate. It also self-updates (1.2.12 to 1.3.0 during these tests).
- **Antigravity's scope list is not pinnable** as far as was checked: no scope
  field was found in its MCP config. The consent screen must allow every scope
  the server lists, and users grant all of them.

## What one shared OAuth client means

All four clients can use the one Web application client, provided it lists
every redirect URI:

- `http://localhost:8765/callback` (Claude Code; Codex if its `callback_url` is set to it)
- `https://antigravity.google/oauth-callback` (Antigravity CLI)
- `https://claude.ai/api/mcp/auth_callback` (claude.ai / Claude Desktop connectors)
- Gemini CLI's redirect URI

To Google, one client is one app with one grant per user. `known-issues.md` §2
measured that revoking any token from that client revokes the whole grant,
refresh tokens included. Not run across clients, but it follows: a re-sign-in
in Claude Code, which revokes the old token, would also end Antigravity's
and Codex's sign-ins, and the other way round.

## One OAuth client per MCP client

Creating a separate Web application client for each MCP client (same project,
same consent screen) gives:

- **Separate grants.** A sign-in or revoke in one tool leaves the others signed in.
- **One redirect URI per client**, so each client's list shows what it is for.
- **Revocation per tool** from the Google Account's third-party access page,
  where each client shows under its own name.

The cost is one console step per client and one set of `client_id` /
`client_secret` files per client. The consent screen, its scopes and the
enabled APIs stay shared. This has not been run here yet.

## Setup per client today

- Claude Code: `claude_setup.sh` (scripted).
- Gemini CLI: `.gemini/settings.json` plus `save_oauth.sh` (checked in).
- Codex CLI and Antigravity CLI: by hand, one server at a time, as above.
  The server URLs and scopes are in `servers.md`; Antigravity ignores the
  scopes.
