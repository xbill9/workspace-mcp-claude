#!/bin/bash

SERVERS="gmail drive docs sheets slides calendar chat people"

echo "Claude Code"
echo "==========="
echo "Register the servers:  source ./save_oauth.sh && ./claude_setup.sh"
echo "Then authenticate each one (or use /mcp inside Claude Code):"
echo ""
for s in $SERVERS; do
    echo "  claude mcp login $s"
done
echo ""
echo "Verify: claude mcp list"
echo ""
echo "Gemini CLI"
echo "=========="
echo "Run these inside Gemini CLI and follow the browser prompts:"
echo ""
for s in $SERVERS; do
    echo "  /mcp auth $s"
done
echo ""
echo "Verify: /mcp list"
