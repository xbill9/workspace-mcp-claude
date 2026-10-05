# Quirks

Behaviour observed while setting up and running the Workspace MCP servers with
Claude Code 2.1.289 on 2026-10-04. Each entry is what happens and what to do
about it. The two sign-in limits with lasting impact have their own page,
`known-issues.md`.

## Contents

1. Google sign-in pages
2. Workspace MCP servers
3. Claude Code
4. Google Cloud console
5. Environment

## 1. Google sign-in pages

- **People must be signed in first.** A repeat People sign-in revokes the
  tokens of every server signed in before it (reproduced twice). Sign-ins for
  the other seven revoke neither each other nor People. Order: People, then
  Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat. `bootstrap.sh` and
  `mcp_setup.sh` use this order.
- **People's sign-in has an extra step.** Before the permissions page it shows
  "Sign in to Workspace MCP Servers" with name and profile picture and a
  **Continue** button. The callback then reports a `profile` scope on top of
  the three requested.
- **People's sign-in names a different resource.** Claude Code sends
  `resource=https://people.googleapis.com/mcp`, the value from People's
  protected resource metadata, while the configured server URL is
  `https://people.googleapis.com/mcp/v1`. The sign-in works either way.
- **The account chooser ignores the first interaction after it loads.** A
  click on the account, by coordinates or by element, often leaves the page on
  "Choose an account". Click the account and press Enter; if the chooser is
  still showing, do it once more.
- **The Allow button moves.** Its position depends on how many permissions are
  listed. Chat's five push it below the fold behind a scroll arrow: scroll
  down, or find the button by its label rather than by coordinates.
- **A previously approved app goes straight to the permissions page** for most
  servers; there is no "already granted" shortcut, so Allow is needed every
  time.

## 2. Workspace MCP servers

- **Tool lists answer without a token.** All eight servers return
  `tools/list` unauthenticated (`mcp_probe.sh`), and seven accept Claude
  Code's connection without one, which is why Claude Code shows `✔ Connected`
  for servers that are not signed in. People asks Claude Code for a sign-in
  and shows `! Needs authentication`.
- **Spec 2026-07-28 needs the `Mcp-Method` header.** `server/discover`
  without `Mcp-Method: server/discover` returns `-32602 Invalid params`. With
  it, seven servers list 2026-07-28; People returns `Method not supported`.
- **`initialize` with 2026-07-28 splits the servers.** Gmail, Drive and
  Calendar answer `Method not supported` (the stateless spec drops
  `initialize`); Docs, Sheets, Slides and Chat negotiate 2026-07-28 anyway.
  All eight negotiate 2025-11-25. Claude Code connects to the 2026-07-28
  servers in that version (`"protocolEra":"modern"` in its debug log).
- **More tools than the guide lists.** Gmail exposes 23 tools, the guide
  lists 10. Trash, spam and label-editing tools need scopes beyond the pinned
  set and fail with `insufficient_scope`.
- **Protected resource metadata offers broad scopes.** Gmail's
  `/.well-known/oauth-protected-resource/mcp/v1` lists 11 scopes including
  `https://mail.google.com/`. Pinning `oauth.scopes` keeps Claude Code from
  requesting what the metadata or a 401 suggests.
- **Docs' `update_doc` description is 35,410 characters**; Claude Code
  truncates it to 2,048.

## 3. Claude Code

- **`claude mcp login` needs a terminal.** From a non-interactive shell it
  stops with "stdin isn't a terminal". `mcp_login.sh` runs it under `script`
  with `BROWSER=/bin/true` and prints the sign-in URL instead.
- **Starting a login drops the current token** at once, whether or not the
  login finishes.
- **Revoked tokens look healthy.** `claude mcp list` stays `✔ Connected`, the
  stored expiry shows minutes left, and in a session the server's tools are
  missing. With `--debug`, the log (`~/.claude/debug/<session>.txt`) shows
  `Failed to fetch tools: Unauthorized`, followed by an attempted sign-in on a
  random callback port with "Redirection handling is disabled".
  `mcp_status.sh --verify` is the direct check.
- **New servers and new sign-ins load in the next session.** A session that
  started before them does not see their tools.
- **`local` scope belongs to a directory.** Servers added with the default
  scope exist only for the working directory at the time of `claude mcp add`,
  and `claude mcp list` elsewhere does not show them. Scripts that register
  servers must not `cd` first.
- **Moving servers to another scope drops their sign-ins and client secret.**
  Credentials are stored per server name, so removing the `local` copies after
  registering the eight at `user` scope left every server with no token, and
  sign-in then failed with `client_secret is missing`. Run
  `MCP_SCOPE=user ./claude_setup.sh` again after the removal, then sign in,
  People first.
- **The client secret is set only when a server is added**
  (`--client-secret` with `MCP_CLIENT_SECRET`). Changing it means
  `claude mcp remove` and adding the server again.
- **MCP tools in a headless session are deferred.** They are reached through
  ToolSearch rather than listed up front; the `init` event's `tools` list shows
  only some servers' tools.
- **Auto mode blocks credential handling.** Reading the client secret from the
  console or its downloaded file, and clicking **Add secret**, are refused by
  auto mode's safety check; allowing the tool in `/permissions` does not change
  that. The user downloads the secret; `bootstrap.sh` installs it without
  printing it.

## 4. Google Cloud console

- **One URL enables all 15 services**:
  `console.cloud.google.com/flows/enableapi?apiid=<comma-separated>&project=<id>`.
- **People has no separate MCP service.** Enabling `people.googleapis.com`
  covers it.
- **The client secret is shown once.** Later visits to the client show
  "Viewing and downloading client secrets is no longer available";
  **Add secret** creates a new one with a download button. Downloads are named
  `client_secret_<client-id>.json` or `client_secret_<n>_<client-id>.json`.
- **The sensitive-scopes table pages at 10 rows.** With all 21 scopes, three
  sit on page 2 of "1 – 10 of 13"; count every page before adding a scope
  again.
- **Shadow DOM hides most form fields** from accessibility-tree tools; a
  JavaScript walker over `shadowRoot`s finds them.
- **Typing without a focused field fires console keyboard shortcuts** and can
  navigate away from the form. Use `form_input` with element refs.
- **`cfc-select` dropdowns reject `form_input`**; open them with a click and
  pick the option from a screenshot.
- **Screenshots of heavy console pages time out**; page text and JavaScript
  reads still work.
- **Two checkboxes to leave alone**: "This client will be used by an
  AI-powered agent" on the OAuth client (Google's guide leaves it off), and
  "Build this Chat app as a Workspace add-on" on the Chat app (clearing it
  cannot be undone).
- **Unused OAuth clients are deleted.** The overview warns that clients unused
  for six months are subject to deletion, so a dormant setup can lose its
  client.

## 5. Environment

- **gcloud cannot re-authenticate without a terminal.** Expired gcloud
  credentials fail with "Reauthentication failed. cannot prompt during
  non-interactive execution"; the user runs `gcloud auth login`, or the APIs are
  enabled in the console.
- **ChromeOS keeps browser downloads outside Linux.** A downloaded client JSON
  is visible to Linux only after **Share with Linux** on the Downloads folder
  (it then appears under `/mnt/chromeos/MyFiles/Downloads`) or a move into
  Linux files.
- **ADC quota project warnings are harmless here.** gcloud warns when the
  active project differs from the ADC quota project; the Workspace MCP setup
  does not use ADC.
