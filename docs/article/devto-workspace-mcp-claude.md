---
title: "MCP Configuration for Google Workspace with Claude Code"
published: false
description: "Connect Claude Code to Google's eight remote Workspace MCP servers (Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat and People), packaged as a Claude Code skill, with the two sign-in limits that decide how you use it."
tags: claudecode, mcp, googleworkspace, googleoauth
cover_image: https://raw.githubusercontent.com/xbill9/workspace-mcp-claude/main/docs/article/devto-cover.1528ae3f.jpg
---

This article provides a step by step configuration guide for the Google Workspace remote MCP servers with Claude Code. The setup is packaged as a Claude Code skill and plugin, so Claude Code can enable the APIs, register the servers, sign in, and test all eight of them.

https://github.com/xbill9/workspace-mcp-claude

**All eight Workspace servers pass a read-only test from Claude Code. Two sign-in limits shape how you use them: each sign-in lasts about an hour, and signing People in again revokes every other server's token, so People always goes first.**

---

#### Didn't You Already Do This?

Yes! The first two versions of this setup used Gemini CLI and Antigravity CLI:

[MCP Configuration for Google Workspace with Gemini CLI](https://medium.com/google-cloud/mcp-configuration-for-google-workspace-with-gemini-cli-ead9ebdc5903)

[MCP Configuration for Google Workspace with Antigravity CLI](https://dev.to/gde/mcp-configuration-for-google-workspace-with-antigravity-cli-3f34)

This version moves the same Google Cloud project to Claude Code, adds the three newer servers (Docs, Sheets and Slides), and adds Chat, which the earlier config files left out.

---

#### What is this project trying to Do?

Google hosts one remote MCP server per Workspace product. Getting Claude Code connected takes a Google Cloud project with the right APIs, an OAuth web client, a few console settings, the servers registered in Claude Code, and a browser sign-in per server.

The repository turns that into scripts and a skill. The scripts do everything that has an API. The skill tells Claude Code how to check what is already done, run the scripts, walk through the console steps, and test the result.

---

#### What is Google Workspace?

Google Workspace is Google's subscription productivity suite: Gmail, Drive, Docs, Sheets, Slides, Calendar, Chat and Meet on a custom domain, with admin controls and shared storage.

[Google Workspace: Secure Online Productivity & Collaboration Tools](https://workspace.google.com/)

Workspace MCP support is in Developer Preview. Sign up here before starting:

[Google Workspace Developer Preview Program](https://developers.google.com/workspace/preview)

---

#### At This Point You Should Have…

- A Google Workspace account in the Developer Preview Program, with admin access to its Google Cloud project.
- The Google Cloud CLI (`gcloud`), signed in.
- Claude Code. This guide used version 2.1.289.
- Chrome on the same machine, for the OAuth sign-in pages.
- A clone of the repository:

```bash
cd ~
git clone https://github.com/xbill9/workspace-mcp-claude
cd workspace-mcp-claude
```

---

#### The Servers

| Server | URL | Tools |
| :--- | :--- | ---: |
| gmail | `https://gmailmcp.googleapis.com/mcp/v1` | 23 |
| drive | `https://drivemcp.googleapis.com/mcp/v1` | 8 |
| docs | `https://docsmcp.googleapis.com/mcp/v1` | 2 |
| sheets | `https://sheetsmcp.googleapis.com/mcp/v1` | 6 |
| slides | `https://slidesmcp.googleapis.com/mcp/v1` | 4 |
| calendar | `https://calendarmcp.googleapis.com/mcp/v1` | 9 |
| chat | `https://chatmcp.googleapis.com/mcp/v1` | 4 |
| people | `https://people.googleapis.com/mcp/v1` | 3 |

A ninth server, `workspace-developer` at `https://workspace-developer.goog/mcp`, searches the Workspace developer docs and needs no sign-in. The tool counts come from `mcp_probe.sh`, shown later.

---

#### Step 1 — Enable the APIs

Each product needs its API and its MCP service. People serves MCP from `people.googleapis.com`, so the total is 15 services. `bootstrap.sh` enables them with gcloud:

```bash
./bootstrap.sh
```

```
Updated property [core/project].
Enabling Workspace APIs and MCP services on comglitn
Operation "operations/acat.p2-<project-number>-d46329d0-40b5-4232-a430-c43e10731dc2" finished successfully.
```

When gcloud cannot sign in from the current shell, one console URL enables all 15 at once:

```
https://console.cloud.google.com/flows/enableapi?apiid=gmail.googleapis.com,drive.googleapis.com,docs.googleapis.com,sheets.googleapis.com,slides.googleapis.com,calendar-json.googleapis.com,chat.googleapis.com,people.googleapis.com,gmailmcp.googleapis.com,drivemcp.googleapis.com,docsmcp.googleapis.com,sheetsmcp.googleapis.com,slidesmcp.googleapis.com,calendarmcp.googleapis.com,chatmcp.googleapis.com&project=PROJECT_ID
```

---

#### Step 2 — Set Up the OAuth Consent Screen

In the Google Cloud console, open **Google Auth Platform → Branding** and click **Get Started** if it is not configured. Name the app `Workspace MCP Servers`, pick **Internal** for the audience, and add a contact email.

Then **Data Access → Add or remove scopes → Manually add scopes**, and paste the scopes for the servers you want. Prefix each with `https://www.googleapis.com/auth/`:

| Server | Scopes |
| :--- | :--- |
| gmail | `gmail.readonly`, `gmail.compose` |
| drive | `drive.readonly`, `drive.file` |
| docs | drive scopes, `documents.readonly`, `documents` |
| sheets | drive scopes, `spreadsheets.readonly`, `spreadsheets` |
| slides | drive scopes, `presentations.readonly`, `presentations` |
| calendar | `calendar.calendarlist.readonly`, `calendar.events.freebusy`, `calendar.events.readonly` |
| chat | `chat.spaces.readonly`, `chat.memberships.readonly`, `chat.messages.readonly`, `chat.messages.create`, `chat.users.readstate` |
| people | `directory.readonly`, `userinfo.profile`, `contacts.readonly` |

That is 21 distinct scopes. The sensitive-scopes table on the Data Access page shows 10 rows per page, so three of them land on page 2.

---

#### Step 3 — Create the OAuth Client

**Google Auth Platform → Clients → Create Client**. Pick **Web application** and add two authorized redirect URIs:

- `http://localhost:8765/callback` for Claude Code. The port matches `CALLBACK_PORT` in the scripts.
- `https://claude.ai/api/mcp/auth_callback` for claude.ai and Claude Desktop custom connectors.

Leave "This client will be used by an AI-powered agent" unticked. Google's guide leaves it off.

---

#### Step 4 — Configure the Chat App

The Chat server needs a Chat app in the project. Open **Google Chat API → Manage → Configuration** and set:

- App name `Chat MCP`
- Avatar URL `https://developers.google.com/chat/images/quickstart-app-avatar.png`
- Description `Chat MCP server`
- Interactive features off
- **Log errors to Logging** ticked

Leave "Build this Chat app as a Workspace add-on" as it is. Clearing it cannot be undone.

---

#### Step 5 — Download the Client Secret

The console shows a client secret once, when it is created. On a later visit the client page says viewing and downloading secrets is no longer available, and **Add secret** creates a new one with a download button.

The download lands in `~/Downloads` as `client_secret_<client-id>.json` or `client_secret_<n>_<client-id>.json`. `bootstrap.sh` picks up the newest one.

---

#### Step 6 — Register the Servers

`bootstrap.sh` installs the client from the downloaded JSON into `~/client_id.txt` and `~/client_secret.txt` (mode 600, never printed), then registers the servers with `claude mcp add-json`:

```bash
./bootstrap.sh --no-apis --no-login
```

```
Installing OAuth client from /home/xbill/Downloads/client_secret_2_<project-number>-<client>.apps.googleusercontent.com.json
Saved client <project-number>-… to ~/client_id.txt and ~/client_secret.txt
Adding Workspace MCP servers to Claude Code (scope: local)
Redirect URI required on the OAuth client: http://localhost:8765/callback

gmail: https://gmailmcp.googleapis.com/mcp/v1 (HTTP) - ✔ Connected
drive: https://drivemcp.googleapis.com/mcp/v1 (HTTP) - ✔ Connected
docs: https://docsmcp.googleapis.com/mcp/v1 (HTTP) - ✔ Connected
sheets: https://sheetsmcp.googleapis.com/mcp/v1 (HTTP) - ✔ Connected
slides: https://slidesmcp.googleapis.com/mcp/v1 (HTTP) - ✔ Connected
calendar: https://calendarmcp.googleapis.com/mcp/v1 (HTTP) - ✔ Connected
chat: https://chatmcp.googleapis.com/mcp/v1 (HTTP) - ✔ Connected
people: https://people.googleapis.com/mcp/v1 (HTTP) - ! Needs authentication
workspace-developer: https://workspace-developer.goog/mcp (HTTP) - ✔ Connected
```

Each server gets its scopes pinned in `oauth.scopes` and the fixed callback port. Claude Code keeps the client secret in its own credential store, so nothing secret reaches `.mcp.json` or `~/.claude.json`.

`MCP_SCOPE` picks where the servers live: `local` (the default, this directory only), `user` (every project) or `project` (a shared `.mcp.json`).

---

#### Step 7 — Sign In, People First

Sign in People before the other seven. A repeat People sign-in revokes every token issued before it, so the order matters every time you sign in again. The known issues below have the measurements.

From your own terminal, in the repository directory:

```bash
for s in people gmail drive docs sheets slides calendar chat; do claude mcp login $s; done
```

Or run `/mcp` inside Claude Code and pick **Authenticate** on each server, People first.

Claude Code can also do it for you through the Chrome extension. `claude mcp login` needs a terminal, so `mcp_login.sh` runs it under a pseudo-terminal and prints the Google sign-in URL for Claude to open:

```bash
./mcp_login.sh start people
./mcp_login.sh check people
```

```
https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=<id>&code_challenge=<…>&code_challenge_method=S256&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback&state=<…>&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdirectory.readonly+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.profile+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcontacts.readonly&resource=https%3A%2F%2Fpeople.googleapis.com%2Fmcp
Signed in: people
```

The consent page is a grant of access to your mail, files and calendar. Check the permissions it lists against the scope table before clicking **Allow**.

---

#### Step 8 — Check the Sign-Ins

`mcp_status.sh` lists each server's sign-in. `--verify` asks Google whether each token is still accepted, printing only valid or invalid:

```bash
./mcp_status.sh --verify
```

```
server    registered  token    min left  refresh
gmail     yes         valid          50  no
drive     yes         valid          51  no
docs      yes         valid          52  no
sheets    yes         valid          53  no
slides    yes         valid          54  no
calendar  yes         valid          54  no
chat      yes         valid          55  no
people    yes         valid          49  no

8 of 8 servers hold a token Google accepts.
Tokens without refresh expire after about an hour; sign in again with /mcp or mcp_login.sh when they do.
```

---

#### Step 9 — Test Every Server

`mcp_test.sh` runs one headless Claude Code session allowed only read-only tools, asks it to make one call per server, and grades each server from the tool results in the session's event stream. The model's own summary plays no part in the grade:

```bash
./mcp_test.sh
```

```
Testing: gmail drive docs sheets slides calendar chat people

server    result            ok  err  tools
gmail     PASS               1    0  list_labels
drive     PASS               4    0  list_recent_files, search_files
docs      PASS               1    0  read_doc
sheets    PASS               1    0  get_spreadsheet
slides    PASS               1    0  read_presentation
calendar  PASS               1    0  list_calendars
chat      PASS               1    0  search_conversations
people    PASS               1    0  get_user_profile

8 of 8 servers passed.
exit=0
```

Drive shows four calls because its file search also finds the Doc, Sheet and Slides deck the next three checks read. `./mcp_test.sh slides` tests one server.

---

#### Which MCP Version Do the Servers Speak?

The 2026-07-28 MCP specification makes the protocol stateless: a `server/discover` request replaces the `initialize` handshake. `mcp_probe.sh` checks each server with no credentials:

```bash
./mcp_probe.sh
```

```
server    2026-07-28  legacy init  tools
gmail     yes         2025-11-25   23
drive     yes         2025-11-25   8
docs      yes         2025-11-25   2
sheets    yes         2025-11-25   6
slides    yes         2025-11-25   4
calendar  yes         2025-11-25   9
chat      yes         2025-11-25   4
people    no          2025-11-25   3

7 of 8 servers advertise 2026-07-28; 59 tools in total.
```

Seven servers advertise 2026-07-28 and Claude Code connects to those at that version. People answers only the 2025-11-25 handshake. All eight accept 2025-11-25, so any current MCP client connects.

---

#### Install It as a Skill

The repository is also a Claude Code plugin marketplace. Install the `google-workspace-mcp` skill:

```
/plugin marketplace add xbill9/workspace-mcp-claude
/plugin install google-workspace-mcp@workspace-mcp-claude
```

Then ask Claude Code something like *"connect my Gmail and Drive to Claude Code"*. The skill checks what is already set up, runs the scripts it bundles, points at the console steps, and finishes with the test. The manifests and the skill validate:

```bash
claude plugin validate .
claude plugin validate plugin
claude plugin validate plugin/skills
```

```
Validating marketplace manifest: /home/xbill/workspace-mcp-claude/.claude-plugin/marketplace.json

✔ Validation passed
Validating plugin manifest: /home/xbill/workspace-mcp-claude/plugin/.claude-plugin/plugin.json

✔ Validation passed
Validating components in: /home/xbill/workspace-mcp-claude/plugin/skills

✔ Validation passed
```

The scripts at the repository root are wrappers around the skill's copies in `plugin/skills/google-workspace-mcp/scripts/`, so a plain clone works the same way.

---

#### Known Issue: Sign-Ins Last About an Hour

Google issues these sign-ins without a refresh token, so Claude Code cannot renew them. Every Workspace entry in Claude Code's credential store has an access token and an expiry one hour after sign-in, and no refresh token.

The authorization URL Claude Code builds carries `response_type`, `client_id`, PKCE, `redirect_uri`, `state`, `scope` and `resource`. Google issues a refresh token only when the request also asks for offline access (`access_type=offline`), and Claude Code's `oauth` settings (`clientId`, `callbackPort`, `scopes`, `authServerMetadataUrl`) have no field that adds it.

Plan for a fresh sign-in each working hour. `mcp_status.sh` shows the minutes left.

---

#### Known Issue: A Repeat People Sign-In Revokes the Others

Signing People in again makes Google revoke the token of every server signed in before it, while those tokens still have most of their hour left. Sign-ins for the other seven revoke nothing. Each row below was checked with Google's token-info endpoint:

| Sign-in order | Tokens Google accepts afterwards |
| :--- | :--- |
| All eight, People last, first sign-in for each | 8 of 8 ✅ |
| People again | People only ❌ |
| All eight again, People last | 7 valid until People, then People only ❌ |
| People first, then the other seven | 8 of 8 ✅ |

People's repeat sign-in shows one extra step: a "Sign in to Workspace MCP Servers" page with your name and profile picture, and a `profile` scope added to the grant. Why Google revokes the other tokens is unconfirmed.

A revoked server is hard to spot. `claude mcp list` still shows it `✔ Connected`, the stored expiry still shows minutes left, and in a session its tools are simply missing. Claude Code's debug log has the reason:

```
[DEBUG] MCP server "slides": Connection error: Unauthorized
[ERROR] MCP server "slides" Failed to fetch tools: Unauthorized
```

`mcp_status.sh --verify` reports such a token as `revoked`. `bootstrap.sh` and the skill sign People in first.

---

#### 🔎 Tip: ✔ Connected Means the Server Answered

All eight servers list their tools without any token, and seven of them accept Claude Code's connection without one too. So `claude mcp list` shows those seven `✔ Connected` before you sign in and after a token is revoked. People asks Claude Code for a sign-in and shows `! Needs authentication`.

Use `mcp_status.sh --verify` for sign-in state and `mcp_test.sh` for working tools.

---

#### 🔎 Tip: Pin the Scopes

Each server publishes the scopes it accepts. Gmail's list has 11, starting with `https://mail.google.com/`, full mailbox access. Without pinned scopes, Claude Code requests what the server's metadata or a `401` response suggests.

`claude_setup.sh` pins the scopes from Google's guide for every server. Gmail exposes 23 tools against the 10 the guide lists, and the extra trash, spam and label-editing tools need scopes outside the pinned set. They fail with `insufficient_scope` until you widen that server's entry and sign it in again.

---

#### 🔎 Tip: The Account Chooser Ignores Its First Click

When Claude drives the sign-in through Chrome, Google's "Choose an account" page often stays put after the first click on the account. Click the account and press Enter, and repeat once if the chooser is still showing.

Chat's consent page lists five permissions and puts **Allow** below the fold, so scroll first. The skill's `references/quirks.md` lists every quirk seen during setup.

---

#### 🔎 Tip: Keep the Client Secret Out of the Transcript

Claude Code's auto mode refuses to read the client secret from the console or from its downloaded file, and refuses to click **Add secret**. Allowing the tool in `/permissions` leaves that check in place.

So the secret takes one human step: you download it, and `bootstrap.sh` copies it into `~/client_secret.txt` without printing it. Delete the downloaded JSON afterwards.

---

#### Compare and Contrast

| | Gemini CLI | Antigravity CLI | Claude Code |
| :--- | :--- | :--- | :--- |
| Server config | `.gemini/settings.json`, `httpUrl` | `mcp_config.json`, `serverUrl` | `claude mcp add-json`, `type: http` |
| Client secret | `${CLIENT_SECRET}` from the environment | written into the config file (no variable substitution) | Claude Code's credential store |
| Redirect URI | see the Gemini CLI article | `https://antigravity.google/oauth-callback` | `http://localhost:8765/callback` |
| Scopes | listed per server | listed per server | pinned per server in `oauth.scopes` |
| Sign-in | `/mcp auth <server>` | `/mcp` → Authenticate | `/mcp`, `claude mcp login`, or `mcp_login.sh` |

claude.ai and Claude Desktop take the same eight URLs as custom connectors (**Settings → Connectors → Add custom connector**), with the OAuth client ID and secret under **Advanced settings** and `https://claude.ai/api/mcp/auth_callback` as the redirect URI.

---

#### So, Which One?

For terminal work in Claude Code, the `google-workspace-mcp` skill. It registers all eight servers with pinned scopes, keeps the secret out of config files, signs People in first, and proves the result with a read-only test.

Plan around the hourly sign-in. `mcp_status.sh --verify` at the start of a session tells you which servers need it, and People first keeps one sign-in from undoing the others.

---

#### Summary

The goal of this article was to connect Claude Code to Google's eight remote Workspace MCP servers and package the setup as a Claude Code skill. The key to the solution was scripting every step that has an API, documenting the console steps that do not, and grading the result from tool calls. The results were:

- 🟢 **8 of 8 servers pass** a read-only test from a headless Claude Code session, graded from the tool results.
- 🟢 **59 tools** across the eight servers; seven advertise the 2026-07-28 MCP specification and all eight accept 2025-11-25.
- 🟢 **One command registers everything** with pinned scopes, and the client secret stays out of every config file.
- 🟢 **Installable as a plugin** from the repository, with manifests and skill that validate.
- ⚠️ **Sign-ins last about an hour**, with no refresh token issued.
- ❌ **A repeat People sign-in revokes the other seven tokens**; signing People in first avoids it.

Scope: one Google Workspace account in the Developer Preview, one Google Cloud project with an Internal consent screen and one Web application OAuth client shared by all eight servers, Claude Code 2.1.289 on Linux, checked on 2026-10-04 and 2026-10-05. The revocation was reproduced twice with Google's token-info endpoint; its cause on Google's side is unconfirmed. Separate OAuth clients per server and claude.ai connectors were not tested.

The strategy for using MCP with Google Workspace from Claude Code was validated with an incremental step by step approach.

---

#### References

* [workspace-mcp-claude | GitHub](https://github.com/xbill9/workspace-mcp-claude)
* [Configure the Google Workspace MCP servers | Google for Developers](https://developers.google.com/workspace/guides/configure-mcp-servers)
* [Google Workspace Developer Preview Program | Google for Developers](https://developers.google.com/workspace/preview)
* [Connect Claude Code to tools via MCP | Claude Code Docs](https://code.claude.com/docs/en/mcp)
* [The 2026-07-28 MCP Specification | Model Context Protocol Blog](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
* [MCP Configuration for Google Workspace with Antigravity CLI | dev.to](https://dev.to/gde/mcp-configuration-for-google-workspace-with-antigravity-cli-3f34)
* [MCP Configuration for Google Workspace with Gemini CLI | Medium](https://medium.com/google-cloud/mcp-configuration-for-google-workspace-with-gemini-cli-ead9ebdc5903)
* [Google Cloud MCP known issues | Google Cloud Documentation](https://docs.cloud.google.com/mcp/known-issues)
