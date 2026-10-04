#!/bin/bash

# Register the Google Workspace remote MCP servers with Claude Code.
#
# Claude Code keeps the OAuth client secret in its credential store, never in
# .mcp.json, so the servers are added with `claude mcp add-json --client-secret`
# rather than from a checked-in config file.
#
# Environment (all optional):
#   CLIENT_ID, CLIENT_SECRET  OAuth web client (default: ~/client_id.txt, ~/client_secret.txt)
#   CALLBACK_PORT             local OAuth callback port (default: 8765)
#   MCP_SCOPE                 local | project | user (default: local)
#
# The OAuth client must list http://localhost:$CALLBACK_PORT/callback
# under Authorized redirect URIs.

if ! command -v claude > /dev/null 2>&1; then
    echo "Error: claude (Claude Code) not found on PATH."
    exit 1
fi

CLIENT_ID=${CLIENT_ID:-$(cat "$HOME/client_id.txt" 2>/dev/null)}
CLIENT_SECRET=${CLIENT_SECRET:-$(cat "$HOME/client_secret.txt" 2>/dev/null)}
CALLBACK_PORT=${CALLBACK_PORT:-8765}
MCP_SCOPE=${MCP_SCOPE:-local}

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "Error: OAuth client not set. Run 'source ./save_oauth.sh' first."
    exit 1
fi

G=https://www.googleapis.com/auth
DRIVE="$G/drive.readonly $G/drive.file"

# name|url|scopes  (scopes from developers.google.com/workspace/guides/configure-mcp-servers)
SERVERS=(
    "gmail|https://gmailmcp.googleapis.com/mcp/v1|$G/gmail.readonly $G/gmail.compose"
    "drive|https://drivemcp.googleapis.com/mcp/v1|$DRIVE"
    "docs|https://docsmcp.googleapis.com/mcp/v1|$DRIVE $G/documents.readonly $G/documents"
    "sheets|https://sheetsmcp.googleapis.com/mcp/v1|$DRIVE $G/spreadsheets.readonly $G/spreadsheets"
    "slides|https://slidesmcp.googleapis.com/mcp/v1|$DRIVE $G/presentations.readonly $G/presentations"
    "calendar|https://calendarmcp.googleapis.com/mcp/v1|$G/calendar.calendarlist.readonly $G/calendar.events.freebusy $G/calendar.events.readonly"
    "chat|https://chatmcp.googleapis.com/mcp/v1|$G/chat.spaces.readonly $G/chat.memberships.readonly $G/chat.messages.readonly $G/chat.messages.create $G/chat.users.readstate"
    "people|https://people.googleapis.com/mcp/v1|$G/directory.readonly $G/userinfo.profile $G/contacts.readonly"
)

echo "Adding Workspace MCP servers to Claude Code (scope: $MCP_SCOPE)"
echo "Redirect URI required on the OAuth client: http://localhost:$CALLBACK_PORT/callback"
echo ""

for entry in "${SERVERS[@]}"; do
    IFS='|' read -r NAME URL SCOPES <<< "$entry"
    JSON=$(printf '{"type":"http","url":"%s","oauth":{"clientId":"%s","callbackPort":%s,"scopes":"%s"}}' \
        "$URL" "$CLIENT_ID" "$CALLBACK_PORT" "$SCOPES")
    claude mcp remove "$NAME" -s "$MCP_SCOPE" > /dev/null 2>&1
    MCP_CLIENT_SECRET="$CLIENT_SECRET" claude mcp add-json --client-secret -s "$MCP_SCOPE" "$NAME" "$JSON"
done

# Workspace developer docs server: public, no OAuth
claude mcp remove workspace-developer -s "$MCP_SCOPE" > /dev/null 2>&1
claude mcp add --transport http -s "$MCP_SCOPE" workspace-developer https://workspace-developer.goog/mcp

echo ""
echo "Next: sign in to each server, either inside Claude Code with /mcp,"
echo "or from the shell:"
echo ""
for entry in "${SERVERS[@]}"; do
    echo "  claude mcp login ${entry%%|*}"
done
echo ""
echo "Then check with: claude mcp list"
