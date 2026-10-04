# Workspace MCP

This workspace provides a set of scripts to initialize a Google Cloud project and connect **Claude Code** (and Gemini CLI) to the Google Workspace remote Model Context Protocol (MCP) servers.

Google Workspace MCP is in Developer Preview. Join the [Google Workspace Developer Preview Program](https://developers.google.com/workspace/preview) first.

## Servers

| Server | URL | Tools |
|---|---|---|
| gmail | `https://gmailmcp.googleapis.com/mcp/v1` | 23 |
| drive | `https://drivemcp.googleapis.com/mcp/v1` | 8 |
| docs | `https://docsmcp.googleapis.com/mcp/v1` | 2 |
| sheets | `https://sheetsmcp.googleapis.com/mcp/v1` | 6 |
| slides | `https://slidesmcp.googleapis.com/mcp/v1` | 4 |
| calendar | `https://calendarmcp.googleapis.com/mcp/v1` | 9 |
| chat | `https://chatmcp.googleapis.com/mcp/v1` | 4 |
| people | `https://people.googleapis.com/mcp/v1` | 3 |
| workspace-developer | `https://workspace-developer.goog/mcp` | docs search, no OAuth |

Tool counts are from `./mcp_probe.sh` on 2026-10-04. All servers use Streamable HTTP and OAuth 2.0.

### MCP protocol version

The MCP 2026-07-28 specification makes the protocol stateless: a `server/discover` request replaces the `initialize` handshake. `./mcp_probe.sh` checks each server:

- gmail, drive, docs, sheets, slides, calendar and chat advertise `2026-07-28` alongside 2024-11-05 through 2025-11-25.
- people does not answer `server/discover`, so it is on the 2025-11-25 handshake only.
- All eight negotiate `2025-11-25` over `initialize`, so any current client connects.

## Scripts

### `init.sh`
Initializes the Google Cloud environment.
- Sets the project ID.
- Enables the Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat and People APIs.
- Enables the matching MCP services (`gmailmcp`, `drivemcp`, `docsmcp`, `sheetsmcp`, `slidesmcp`, `calendarmcp`, `chatmcp`; People serves MCP from `people.googleapis.com`).
- Creates a `.env` file with default configurations.
- Configures Application Default Credentials (ADC).

### `set_env.sh`
Refreshes the `.env` file from the current `gcloud` project and checks authentication.

### `set_adc.sh`
Ensures that both `gcloud` and ADC are authenticated. Source it: `source ./set_adc.sh`.

### `save_oauth.sh`
Prompts for the project ID, OAuth client ID and client secret, keeps them in your home directory, and exports `PROJECT_ID`, `CLIENT_ID` and `CLIENT_SECRET`. Source it: `source ./save_oauth.sh`.

### `claude_setup.sh`
Registers all eight Workspace servers plus `workspace-developer` with Claude Code, using `claude mcp add-json --client-secret`. Each server gets the scopes from Google's guide pinned in `oauth.scopes`, and all share one OAuth callback port. Claude Code stores the client secret in its credential store, never in a config file.

| Variable | Default | Meaning |
|---|---|---|
| `CALLBACK_PORT` | `8765` | Port in the redirect URI `http://localhost:PORT/callback` |
| `MCP_SCOPE` | `local` | `local` (this project, private), `project` (writes `.mcp.json`, no secret), or `user` (all projects) |

### `mcp_probe.sh`
Reports, without credentials, each server's advertised MCP versions, negotiated legacy version, tool list and OAuth resource scopes.

### `mcp_setup.sh`
Prints the authentication commands for Claude Code and Gemini CLI.

## Quick start: `bootstrap.sh`

Once the console steps (2–4 below) are done, one command does the rest:

```bash
./bootstrap.sh                          # newest ~/Downloads/client_secret_*.json
./bootstrap.sh path/to/client.json      # or a specific client file
```

It enables the APIs, installs the OAuth client from the file the console's **Download JSON** button saves (to `~/client_id.txt` and `~/client_secret.txt`, mode 600, never printed), runs `claude_setup.sh`, signs in to each server with `claude mcp login`, and lists the result. `--no-apis` skips the gcloud step; `--no-login` skips sign-in.

Most servers show `✔ Connected` before sign-in because they answer `tools/list` without a token. Tool calls still need the sign-in.

## Getting Started with Claude Code

1. Run `./init.sh` and follow the prompts to set your Project ID.
2. Configure the Chat app (required by the Chat server): Google Cloud console → **Google Chat API → Manage → Configuration**. App name `Chat MCP`, avatar `https://developers.google.com/chat/images/quickstart-app-avatar.png`, description `Chat MCP server`, interactive features off, **Log errors to Logging**, Save.
3. Configure the OAuth consent screen: **Google Auth Platform → Branding → Get Started**, Audience **Internal** (or External plus yourself as a test user), then add the scopes below under **Data Access**.
4. Create the OAuth client: **Google Auth Platform → Clients → Create Client**, type **Web application**, and add these Authorized redirect URIs:
   - `http://localhost:8765/callback` (Claude Code, matches `CALLBACK_PORT`)
   - `https://claude.ai/api/mcp/auth_callback` (only if you also add the servers as claude.ai / Claude Desktop custom connectors)
5. `source ./save_oauth.sh` and enter the client ID and secret.
6. `./claude_setup.sh`
7. Authenticate each server with `/mcp` inside Claude Code, or `claude mcp login gmail` (and so on) from the shell. Over SSH, add `--no-browser`.
8. Verify with `claude mcp list`, then try a prompt such as *"When is my next meeting?"*.

### OAuth scopes

| Server | Scopes (`https://www.googleapis.com/auth/…`) |
|---|---|
| gmail | `gmail.readonly`, `gmail.compose` |
| drive | `drive.readonly`, `drive.file` |
| docs | drive scopes + `documents.readonly`, `documents` |
| sheets | drive scopes + `spreadsheets.readonly`, `spreadsheets` |
| slides | drive scopes + `presentations.readonly`, `presentations` |
| calendar | `calendar.calendarlist.readonly`, `calendar.events.freebusy`, `calendar.events.readonly` |
| chat | `chat.spaces.readonly`, `chat.memberships.readonly`, `chat.messages.readonly`, `chat.messages.create`, `chat.users.readstate` |
| people | `directory.readonly`, `userinfo.profile`, `contacts.readonly` |

These are the scopes in Google's guide. Some tools need more: Gmail's trash, spam and label-editing tools and Calendar's create, update, delete and respond tools are listed by the servers but fall outside these read and compose scopes. Claude Code reports such a call as `insufficient_scope`; add the scope to `SERVERS` in `claude_setup.sh` (and to the consent screen), re-run it, and authenticate again.

### claude.ai and Claude Desktop

Claude.ai and Claude Desktop (Pro, Max, Team or Enterprise) use custom connectors instead: **Settings → Connectors → Add custom connector**, one per server URL above, with the OAuth client ID and secret under **Advanced settings**. That client needs the `https://claude.ai/api/mcp/auth_callback` redirect URI.

## Getting Started with Gemini CLI

1. Steps 1–3 above.
2. `source ./save_oauth.sh` so `${CLIENT_ID}` and `${CLIENT_SECRET}` in `.gemini/settings.json` resolve.
3. Start Gemini CLI and run `./mcp_setup.sh` for the `/mcp auth` commands.

## Security

These servers can read, change and delete Workspace data as you. Content in emails and documents can carry hidden instructions (indirect prompt injection), so review the actions your client takes and avoid pointing it at untrusted content.

## References

- [Configure the Google Workspace MCP servers](https://developers.google.com/workspace/guides/configure-mcp-servers)
- [MCP Configuration for Google Workspace with Antigravity CLI](https://dev.to/gde/mcp-configuration-for-google-workspace-with-antigravity-cli-3f34)
- [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp)
- [The 2026-07-28 MCP specification](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
- [Google Cloud MCP known issues](https://docs.cloud.google.com/mcp/known-issues)
