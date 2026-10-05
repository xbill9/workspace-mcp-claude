# Google Cloud console setup

These steps have no public API, so they are done in the Cloud console, either
by the user or by Claude driving Chrome (claude-in-chrome). Each is one-time
per Google Cloud project. Replace `PROJECT` with the project ID.

Prerequisite: the account is in the
[Google Workspace Developer Preview Program](https://developers.google.com/workspace/preview).

## Contents

1. Enable the APIs (when gcloud auth is not available)
2. OAuth consent screen and scopes
3. OAuth client
4. Client secret file
5. Chat app
6. Signing in with Chrome
7. Console automation notes

## 1. Enable the APIs

`bootstrap.sh` does this with gcloud. When gcloud cannot authenticate, one
console page enables all 15 in one go:

```
https://console.cloud.google.com/flows/enableapi?apiid=gmail.googleapis.com,drive.googleapis.com,docs.googleapis.com,sheets.googleapis.com,slides.googleapis.com,calendar-json.googleapis.com,chat.googleapis.com,people.googleapis.com,gmailmcp.googleapis.com,drivemcp.googleapis.com,docsmcp.googleapis.com,sheetsmcp.googleapis.com,slidesmcp.googleapis.com,calendarmcp.googleapis.com,chatmcp.googleapis.com&project=PROJECT
```

Click **Next**, then **Enable**. The page lists "You have successfully enabled"
with all 15 names when it is done. People has no separate MCP service.

## 2. OAuth consent screen and scopes

`https://console.cloud.google.com/auth/overview?project=PROJECT`

- If it says "not configured yet": **Get Started**, app name
  `Workspace MCP Servers`, support email, Audience **Internal** (External only
  if Internal is unavailable, then add the user as a test user), contact email,
  agree, **Create**.
- **Data Access → Add or remove scopes → Manually add scopes**: paste the 21
  scopes in `servers.md`, comma-separated, **Add to table**, **Update**, then
  **Save** at the bottom of the page.

Check the result on the Data Access page. The sensitive-scopes table is paged
(10 rows per page, "1 – 10 of 13"), so three scopes sit on page 2; count rows on
every page before concluding one is missing. The Save button is greyed out once
nothing is pending.

## 3. OAuth client

`https://console.cloud.google.com/auth/clients/create?project=PROJECT`

- Application type **Web application**, name e.g. `claude-workspace-mcp`.
- Authorized redirect URIs:
  - `http://localhost:8765/callback` (Claude Code; the port is `CALLBACK_PORT`)
  - `https://claude.ai/api/mcp/auth_callback` (only for claude.ai / Claude Desktop connectors)
- Leave "This client will be used by an AI-powered agent" unticked; Google's
  guide does not use it.
- **Create**.

Prefer a new client over editing one another tool already uses.

## 4. Client secret file

The secret is shown only when a client or secret is created. On the client's
page, **Add secret**, then the download button on the new secret. It saves
`client_secret_<n>_<client-id>.json` (or `client_secret_<client-id>.json`) to
the browser's download folder. `bootstrap.sh` picks up the newest
`client_secret_*.json` in `~/Downloads` (and ChromeOS's shared Downloads).

The user does this step. Claude must not read the client secret off the page
or out of the file: Claude Code's auto mode blocks it, and the secret should
stay out of the transcript. `bootstrap.sh` copies it into
`~/client_secret.txt` without printing it.

Afterwards the downloaded JSON can be deleted.

## 5. Chat app

Required by the Chat server.
`https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=PROJECT`

- App name `Chat MCP`
- Avatar URL `https://developers.google.com/chat/images/quickstart-app-avatar.png`
- Description `Chat MCP server`
- Interactive features: **off**
- Logs: **Log errors to Logging** ticked
- **Save**

Leave "Build this Chat app as a Workspace add-on" as it is. Clearing it cannot
be undone and Google's guide does not mention it.

## 6. Signing in with Chrome

`claude mcp login` needs a terminal and opens its own browser, so from Claude's
Bash tool use `scripts/mcp_login.sh`:

1. `mcp_login.sh start <server>` prints the Google sign-in URL and leaves a
   listener on `localhost:8765`.
2. Open the URL in a Chrome tab and choose the account: click it and press
   Enter, and do it again if "Choose an account" is still showing (the first
   interaction after the page loads is often ignored). Review the permissions
   shown (they should match `servers.md`) and click **Allow**; for Chat, scroll
   down first. People also shows "Sign in to Workspace MCP Servers" with a
   **Continue** button before its permissions.
3. The tab lands on `localhost:8765/callback`; `mcp_login.sh check <server>`
   prints `Signed in: <server>`.

One server at a time: they share the callback port. People first: a repeat
People sign-in revokes every token issued before it (`known-issues.md`).
`start` drops the
server's existing sign-in, so only start servers that need it. The consent is
a grant of access to the user's Google data; do it only when the user has
asked for the sign-in to be done for them.

## 7. Console automation notes

What works when driving the Cloud console with claude-in-chrome:

- Much of the console renders inside shadow DOM, so `find` and `read_page`
  often miss form fields. A small JavaScript walker over `shadowRoot`s finds
  buttons and inputs reliably.
- Typing with the `computer` tool while no field has focus triggers console
  keyboard shortcuts and can navigate away. Set text fields with `form_input`
  using refs from `read_page`, or set `value` and dispatch `input`/`change`
  events from JavaScript.
- Dropdowns (`cfc-select`) reject `form_input`; click to open, then click the
  option from a screenshot.
- Screenshots of heavy console pages can time out; `get_page_text` and
  JavaScript reads still work.
- Re-read saved state after a reload rather than trusting the form you filled.
