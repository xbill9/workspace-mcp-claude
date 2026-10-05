#!/bin/bash
# Wrapper: the script lives in the google-workspace-mcp skill.
exec "$(dirname "$0")/plugin/skills/google-workspace-mcp/scripts/mcp_probe.sh" "$@"
