#!/usr/bin/env python3
"""Local MCP proxy that signs requests to the Google Workspace MCP servers.

Claude Code connects to http://127.0.0.1:$PROXY_PORT/<label>/mcp/v1 with no
credentials. The proxy adds "Authorization: Bearer <access token>" from
token_header.access_token(<label>), forwards the request to the Google server
and streams the answer back. When Google answers 401 it refreshes the token and
retries once, so a stale stored token heals inside the request.

  PROBE_DIR=~/.cache/oauth-probe python3 token_proxy.py

Each request is logged to stderr as time, label, JSON-RPC method and status;
token values and message bodies are never logged.
"""
import http.server, json, os, sys, time, urllib.error, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from token_header import access_token

PORT = int(os.environ.get("PROXY_PORT", "8790"))
UPSTREAM = {
    "gmail": "https://gmailmcp.googleapis.com/mcp/v1",
    "drive": "https://drivemcp.googleapis.com/mcp/v1",
    "docs": "https://docsmcp.googleapis.com/mcp/v1",
    "sheets": "https://sheetsmcp.googleapis.com/mcp/v1",
    "slides": "https://slidesmcp.googleapis.com/mcp/v1",
    "calendar": "https://calendarmcp.googleapis.com/mcp/v1",
    "chat": "https://chatmcp.googleapis.com/mcp/v1",
    "people": "https://people.googleapis.com/mcp/v1",
}
PASS_UP = ("content-type", "accept", "mcp-session-id", "mcp-protocol-version", "last-event-id")
PASS_DOWN = ("content-type", "mcp-session-id", "cache-control")


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # close-delimited bodies, so SSE streams need no re-chunking

    def log_message(self, *args):
        pass

    def note(self, label, rpc, status, extra=""):
        print(f"{time.strftime('%H:%M:%S')} {label} {self.command} {rpc} -> {status} {extra}".rstrip(),
              file=sys.stderr, flush=True)

    def handle_any(self):
        label, _, rest = self.path.lstrip("/").partition("/")
        if label not in UPSTREAM or not ("/" + rest).startswith("/mcp/v1"):
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)) or None
        try:
            rpc = json.loads(body).get("method", "-") if body else "-"
        except (ValueError, AttributeError):
            rpc = "batch"
        headers = {k: v for k, v in self.headers.items() if k.lower() in PASS_UP}
        for attempt in (0, 1):
            try:
                headers["Authorization"] = f"Bearer {access_token(label, force=attempt == 1)}"
            except RuntimeError as e:
                self.note(label, rpc, 502, str(e))
                self.send_error(502, str(e))
                return
            req = urllib.request.Request(UPSTREAM[label], data=body, headers=headers, method=self.command)
            try:
                resp = urllib.request.urlopen(req, timeout=120)
            except urllib.error.HTTPError as e:
                resp = e
            if resp.status == 401 and attempt == 0:
                resp.close()
                self.note(label, rpc, 401, "refreshing and retrying")
                continue
            break
        self.note(label, rpc, resp.status)
        self.send_response(resp.status)
        for k, v in resp.headers.items():
            if k.lower() in PASS_DOWN:
                self.send_header(k, v)
        self.end_headers()
        while chunk := resp.read1(65536) if hasattr(resp, "read1") else resp.read(65536):
            self.wfile.write(chunk)
            self.wfile.flush()
        resp.close()

    do_GET = do_POST = do_DELETE = handle_any


if __name__ == "__main__":
    print(f"listening on http://127.0.0.1:{PORT}/<label>/mcp/v1", file=sys.stderr, flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Proxy).serve_forever()
