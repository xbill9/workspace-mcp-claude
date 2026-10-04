#!/bin/bash

# Prompt for (or reload) the project ID and OAuth client, and export them.
# Source it so CLIENT_ID / CLIENT_SECRET reach your shell:
#   source ./save_oauth.sh

# Check if gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "Error: No active gcloud account found."
    echo "Please run 'gcloud auth login' and try again."
    return 1 2>/dev/null || exit 1
fi

if [ -f "$HOME/project_id.txt" ]; then
    PROJECT_ID=$(cat "$HOME/project_id.txt")
else
    read -p "Enter Project ID: " PROJECT_ID
    echo "$PROJECT_ID" > "$HOME/project_id.txt"
fi

if [ -f "$HOME/client_id.txt" ]; then
    CLIENT_ID=$(cat "$HOME/client_id.txt")
else
    read -p "Enter Client ID: " CLIENT_ID
    echo "$CLIENT_ID" > "$HOME/client_id.txt"
fi

if [ -f "$HOME/client_secret.txt" ]; then
    CLIENT_SECRET=$(cat "$HOME/client_secret.txt")
else
    read -s -p "Enter Client Secret: " CLIENT_SECRET
    echo ""
    (umask 077; echo "$CLIENT_SECRET" > "$HOME/client_secret.txt")
fi

export PROJECT_ID CLIENT_ID CLIENT_SECRET
echo "Exported PROJECT_ID, CLIENT_ID and CLIENT_SECRET."
