# Workspace MCP servers

Source: [Configure the Google Workspace MCP servers](https://developers.google.com/workspace/guides/configure-mcp-servers)
(Developer Preview). All use Streamable HTTP and OAuth 2.0 with
`https://accounts.google.com/` as the authorization server.

| Server | URL | API / MCP service |
|---|---|---|
| gmail | `https://gmailmcp.googleapis.com/mcp/v1` | `gmail` / `gmailmcp` |
| drive | `https://drivemcp.googleapis.com/mcp/v1` | `drive` / `drivemcp` |
| docs | `https://docsmcp.googleapis.com/mcp/v1` | `docs` / `docsmcp` |
| sheets | `https://sheetsmcp.googleapis.com/mcp/v1` | `sheets` / `sheetsmcp` |
| slides | `https://slidesmcp.googleapis.com/mcp/v1` | `slides` / `slidesmcp` |
| calendar | `https://calendarmcp.googleapis.com/mcp/v1` | `calendar-json` / `calendarmcp` |
| chat | `https://chatmcp.googleapis.com/mcp/v1` | `chat` / `chatmcp` |
| people | `https://people.googleapis.com/mcp/v1` | `people` (no separate MCP service) |
| workspace-developer | `https://workspace-developer.goog/mcp` | public docs search, no OAuth |

Each `<name>.googleapis.com` service is enabled in the project.

## Scopes

Prefix every scope with `https://www.googleapis.com/auth/`. 21 distinct scopes in total.

| Server | Scopes |
|---|---|
| gmail | `gmail.readonly`, `gmail.compose` |
| drive | `drive.readonly`, `drive.file` |
| docs | `drive.readonly`, `drive.file`, `documents.readonly`, `documents` |
| sheets | `drive.readonly`, `drive.file`, `spreadsheets.readonly`, `spreadsheets` |
| slides | `drive.readonly`, `drive.file`, `presentations.readonly`, `presentations` |
| calendar | `calendar.calendarlist.readonly`, `calendar.events.freebusy`, `calendar.events.readonly` |
| chat | `chat.spaces.readonly`, `chat.memberships.readonly`, `chat.messages.readonly`, `chat.messages.create`, `chat.users.readstate` |
| people | `directory.readonly`, `userinfo.profile`, `contacts.readonly` |

Comma-separated, for pasting into the consent screen:

```
https://www.googleapis.com/auth/gmail.readonly, https://www.googleapis.com/auth/gmail.compose, https://www.googleapis.com/auth/drive.readonly, https://www.googleapis.com/auth/drive.file, https://www.googleapis.com/auth/documents.readonly, https://www.googleapis.com/auth/documents, https://www.googleapis.com/auth/spreadsheets.readonly, https://www.googleapis.com/auth/spreadsheets, https://www.googleapis.com/auth/presentations.readonly, https://www.googleapis.com/auth/presentations, https://www.googleapis.com/auth/calendar.calendarlist.readonly, https://www.googleapis.com/auth/calendar.events.freebusy, https://www.googleapis.com/auth/calendar.events.readonly, https://www.googleapis.com/auth/chat.spaces.readonly, https://www.googleapis.com/auth/chat.memberships.readonly, https://www.googleapis.com/auth/chat.messages.readonly, https://www.googleapis.com/auth/chat.messages.create, https://www.googleapis.com/auth/chat.users.readstate, https://www.googleapis.com/auth/directory.readonly, https://www.googleapis.com/auth/userinfo.profile, https://www.googleapis.com/auth/contacts.readonly
```

These are the guide's scopes. Some tools the servers list need more: Gmail's
trash, spam and label-editing tools, and Calendar's create, update, delete and
respond tools. Such a call fails with `insufficient_scope`; widen the server's
entry in `scripts/claude_setup.sh` and the consent screen, re-run the script,
and sign that server in again.

## Tools

Lists change; `scripts/mcp_probe.sh` prints the live ones (tools/list answers
without a token).

| Server | Tools |
|---|---|
| gmail | create_draft, list_drafts, get_draft, get_thread, get_message, search_threads, label_thread, unlabel_thread, apply_sensitive_thread_label, trash_thread, untrash_thread, mark_thread_spam, unmark_thread_spam, list_labels, label_message, update_message_labels, unlabel_message, apply_sensitive_message_label, trash_message, untrash_message, mark_message_spam, unmark_message_spam, create_label |
| drive | copy_file, create_file, download_file_content, get_file_metadata, get_file_permissions, list_recent_files, read_file_content, search_files |
| docs | read_doc, update_doc |
| sheets | get_values, get_spreadsheet, update_spreadsheet, update_values, update_formulas, insert_dimension |
| slides | read_presentation, read_slide_page, read_slide_page_thumbnail, update_presentation |
| calendar | list_events, get_event, list_calendars, suggest_time, create_event, update_event, delete_event, respond_to_event, search_events |
| chat | list_messages, search_messages, search_conversations, send_message |
| people | search_directory_people, search_contacts, get_user_profile |

## MCP protocol versions

`mcp_probe.sh` on 2026-10-04: gmail, drive, docs, sheets, slides, calendar and
chat advertise the stateless 2026-07-28 spec through `server/discover` (which
requires the `Mcp-Method: server/discover` header) alongside 2024-11-05 through
2025-11-25. people does not answer `server/discover`. All eight negotiate
2025-11-25 over `initialize`.
