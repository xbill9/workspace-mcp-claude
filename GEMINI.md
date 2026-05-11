# Workspace MCP Developer Mandates

You are an expert developer specializing in building and managing Model Context Protocol (MCP) agents within a Google Cloud environment. This workspace is optimized for GCP-hosted MCP servers.

## Architecture Overview

- **Cloud Core:** The workspace relies on Google Cloud Platform (GCP) for identity, API access, and agent runtime.
- **MCP Integration:** Agents interact with Google Workspace (Gmail, Drive, Calendar) via MCP servers.
- **State Management:** Local environment configuration is managed via `.env` files, which are generated and updated by workspace scripts.
- **Identity:** Authentication is handled through `gcloud` and Application Default Credentials (ADC).

## Mandatory Workflows

1. **Environment Setup:** Before starting any development or execution, ensure the environment is initialized.
   - Run `./init.sh` for first-time setup or project changes.
   - Run `./set_env.sh` to refresh the local configuration.
   - Run `./mcp_setup.sh` to view instructions for authorizing MCP services in the Gemini CLI.
2. **Authentication:** If tool calls fail with 401/403 errors, always check ADC.
   - **Instruction:** Source the ADC setup script: `source ./set_adc.sh`.
3. **API Management:** When adding features requiring new Google Cloud APIs:
   - Update `init.sh` to include the `gcloud services enable` command for both the underlying API and the corresponding MCP API.
4. **Credential Safety:** Never hardcode Project IDs or Secrets. Use the scripts to manage them in `~/` or `.env`.

## Conventions

- **Project ID:** The source of truth for the active GCP project is the `.env` file (`GOOGLE_CLOUD_PROJECT`).
- **Tooling:** Prefer using the `adk` CLI for agent-related tasks (e.g., `adk --version`).
- **Memory:** Use the private project memory (`/home/xbill/.gemini/tmp/workspace-mcp/memory/MEMORY.md`) for persistent local notes about specific GCP project configurations or transient issues.

## Tech Stack

- **Platform:** Google Cloud (Vertex AI / Agent Engine).
- **Protocol:** Model Context Protocol (MCP).

## refs

https://codelabs.developers.google.com/google-workspace-mcp-gemini-cli#0
https://developers.google.com/workspace/guides/configure-mcp-servers


