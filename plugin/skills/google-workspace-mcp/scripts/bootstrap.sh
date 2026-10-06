#!/bin/bash

# One-command setup of the Google Workspace MCP servers for Claude Code.
#
#   ./bootstrap.sh [client_secret.json] [--no-apis] [--no-login]
#
# 1. Enables the Workspace APIs and MCP services (needs gcloud auth).
# 2. Installs the OAuth client from the JSON file the console's
#    "Download JSON" button saves (default: newest ~/Downloads/client_secret_*.json).
#    The ID and secret go to ~/client_id.txt and ~/client_secret.txt (mode 600)
#    and are never printed.
# 3. Registers the servers with Claude Code (claude_setup.sh).
# 4. Signs in to each server (claude mcp login), then lists them.
#
# One-time console steps it cannot do (no public API): the OAuth consent
# screen scopes, the OAuth client itself, and the Chat app configuration.
# See references/console-setup.md in the google-workspace-mcp skill.
#
# Servers are registered for every project (MCP_SCOPE=user). With
# MCP_SCOPE=local, run it from the project that should get them.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CLIENT_JSON=""
DO_APIS=1
DO_LOGIN=1
for arg in "$@"; do
    case "$arg" in
        --no-apis) DO_APIS=0 ;;
        --no-login) DO_LOGIN=0 ;;
        *) CLIENT_JSON="$arg" ;;
    esac
done

# Signs in all eight in one pass. Signing a working server in again revokes
# every server's token (references/known-issues.md), so they go together.
SERVERS="people gmail drive docs sheets slides calendar chat"

# --- 1. APIs ---------------------------------------------------------------
if [ "$DO_APIS" = 1 ]; then
    if ! gcloud auth print-access-token > /dev/null 2>&1; then
        echo "gcloud auth expired or not found. Initializing login..."
        gcloud auth login || exit 1
    fi

    if [ -f "$HOME/project_id.txt" ]; then
        PROJECT_ID=$(cat "$HOME/project_id.txt")
    else
        read -p "Enter Project ID: " PROJECT_ID
        echo "$PROJECT_ID" > "$HOME/project_id.txt"
    fi
    gcloud config set project "$PROJECT_ID"

    echo "Enabling Workspace APIs and MCP services on $PROJECT_ID"
    gcloud services enable gmail.googleapis.com drive.googleapis.com \
        docs.googleapis.com sheets.googleapis.com slides.googleapis.com \
        calendar-json.googleapis.com chat.googleapis.com people.googleapis.com \
        gmailmcp.googleapis.com drivemcp.googleapis.com docsmcp.googleapis.com \
        sheetsmcp.googleapis.com slidesmcp.googleapis.com \
        calendarmcp.googleapis.com chatmcp.googleapis.com \
        --project="$PROJECT_ID" || exit 1
fi

# --- 2. OAuth client -------------------------------------------------------
if [ -z "$CLIENT_JSON" ]; then
    # ~/Downloads, or ChromeOS Downloads once shared with Linux
    CLIENT_JSON=$(ls -t "$HOME"/Downloads/client_secret_*.json \
        /mnt/chromeos/MyFiles/Downloads/client_secret_*.json 2>/dev/null | head -1)
fi

if [ -n "$CLIENT_JSON" ]; then
    echo "Installing OAuth client from $CLIENT_JSON"
    python3 - "$CLIENT_JSON" "$HOME" <<'EOF' || exit 1
import json, os, sys
path, home = sys.argv[1], sys.argv[2]
data = json.load(open(path))
client = data.get("web") or data.get("installed")
if not client or "client_id" not in client or "client_secret" not in client:
    sys.exit(f"Error: {path} is not an OAuth client JSON (no web/installed client).")
redirects = client.get("redirect_uris", [])
port = os.environ.get("CALLBACK_PORT", "8765")
want = f"http://localhost:{port}/callback"
if "web" in data and want not in redirects:
    print(f"Warning: {want} is not an authorized redirect URI on this client.")
old = os.umask(0o077)
for name in ("client_id", "client_secret"):
    with open(os.path.join(home, f"{name}.txt"), "w") as f:
        f.write(client[name] + "\n")
os.umask(old)
print(f"Saved client {client['client_id'].split('-')[0]}-… to ~/client_id.txt and ~/client_secret.txt")
EOF
elif [ ! -f "$HOME/client_id.txt" ] || [ ! -f "$HOME/client_secret.txt" ]; then
    echo "Error: no OAuth client found."
    echo "Download the client JSON from Google Auth Platform > Clients and re-run,"
    echo "or pass its path: ./bootstrap.sh path/to/client_secret.json"
    echo "On ChromeOS, share Downloads with Linux (Files app: right-click Downloads >"
    echo "Share with Linux) or move the file into Linux files."
    exit 1
else
    echo "Using the OAuth client already saved in ~/client_id.txt"
fi

# --- 3. Register with Claude Code -------------------------------------------
"$SCRIPT_DIR/claude_setup.sh" || exit 1

# --- 4. Sign in --------------------------------------------------------------
if [ "$DO_LOGIN" = 1 ]; then
    for s in $SERVERS; do
        echo ""
        echo "=== Sign in: $s"
        claude mcp login "$s" || echo "Sign-in for $s did not finish; retry with: claude mcp login $s"
    done
fi

echo ""
claude mcp list 2>&1 | grep -E "^($(echo $SERVERS | tr ' ' '|')|workspace-developer):"
