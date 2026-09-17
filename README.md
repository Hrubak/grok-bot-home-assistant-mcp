# Connect Grok Bot / Cursor to Home Assistant via MCP

Full instructions for wiring an AI assistant (Grok Bot, Cursor, Claude Desktop, etc.) to a Home Assistant instance using **[ha-mcp](https://github.com/homeassistant-ai/ha-mcp)** over **stdio**.

This matches how **Nexus** (Jonathan’s Grok Bot homelab agent) reaches Home Assistant in production: a long-lived access token + `uvx ha-mcp@latest`, not the official Home Assistant `/api/mcp` Streamable HTTP endpoint, and not `mcp-proxy`.

> **Do not commit tokens.** Use environment variables or your host’s secret store.

---

## Architecture

```
┌─────────────────────┐         stdio MCP          ┌──────────────────┐
│  Grok Bot / Cursor  │ ──── command + env ───────► │  uvx ha-mcp      │
│  (MCP client)       │ ◄─── tools / results ────── │  (MCP server)    │
└─────────────────────┘                             └────────┬─────────┘
                                                             │ HTTPS REST +
                                                             │ WebSocket API
                                                             ▼
                                                    ┌──────────────────┐
                                                    │  Home Assistant  │
                                                    │  (your URL)      │
                                                    └──────────────────┘
```

- The MCP server runs **on the assistant’s machine** (Grok Bot’s computer, or your laptop for Claude Desktop / Cursor).
- It calls Home Assistant’s normal API with `HOMEASSISTANT_URL` + `HOMEASSISTANT_TOKEN`.
- You do **not** need the Home Assistant MCP Server integration (`/api/mcp`) for this path.
- Run **one** ha-mcp install method only (stdio **or** HA App **or** in-process custom component — not several at once).

Official ha-mcp docs: [Linux](https://homeassistant-ai.github.io/ha-mcp/guide-linux/) · [macOS](https://homeassistant-ai.github.io/ha-mcp/guide-macos/) · [FAQ](https://homeassistant-ai.github.io/ha-mcp/faq/)

---

## Prerequisites

1. **Home Assistant** reachable over HTTPS (or HTTP on a trusted LAN) from the machine that will run `ha-mcp`.
   - Grok Bot agents run on a remote Linux “box.” Your HA URL must be reachable **from the internet or a tunnel** (Nabu Casa, reverse proxy, WireGuard, Cloudflare Tunnel, etc.). `http://homeassistant.local:8123` only works if the MCP process is on the same LAN.
2. **`uv` / `uvx`** on that machine ([Astral uv](https://docs.astral.sh/uv/)).
3. **Python 3.13** available to uv (`uv python install 3.13` if needed). Current ha-mcp expects 3.13.x.
4. A **long-lived access token** from a Home Assistant user that should own the agent’s actions (prefer a dedicated limited user for production).

---

## Step 1 — Create a Home Assistant long-lived access token

1. Open Home Assistant in a browser and sign in.
2. Click your **profile** (user icon, lower left).
3. Open the **Security** tab.
4. Under **Long-lived access tokens**, create a token (name it e.g. `grok-bot-ha-mcp`).
5. **Copy it once** — HA will not show it again.
6. Store it in a password manager / secret store. Never paste it into a git repo, screenshot, or public chat.

Recommended: use a dedicated HA user with only the permissions the assistant needs (not your full admin account), when practical.

---

## Step 2 — Confirm the URL from the agent host

From the machine that will run `ha-mcp`, the URL must respond. Example:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $HOMEASSISTANT_TOKEN" \
  "$HOMEASSISTANT_URL/api/"
```

Expect `200`. Common failures:

| Symptom | Likely cause |
|--------|----------------|
| Timeout / connection refused | HA not exposed to that host; firewall; wrong host/port |
| `401` | Bad or revoked token |
| TLS errors | Self-signed cert without trust, or wrong hostname vs cert |

---

## Step 3A — Grok Bot (custom MCP server)

Grok Bot has no catalog plugin for Home Assistant today. Add a **custom stdio MCP server** on the shared bot computer.

### Option A — Direct `uvx` (simplest)

Ask the bot (or use the product’s “add MCP server” flow) with roughly:

| Field | Value |
|-------|--------|
| **Name** | `home-assistant` (becomes something like `user-home-assistant`) |
| **Command** | `uvx` (or absolute path `/usr/local/bin/uvx` if PATH is thin) |
| **Args** | `--python`, `3.13`, `ha-mcp@latest` |
| **Env** | `HOMEASSISTANT_URL=https://YOUR-HA-HOST` |
| **Env** | `HOMEASSISTANT_TOKEN=<paste via secret input, not chat>` |

In Grok Bot, prefer the **secure secret input** (masked card) so the token becomes an environment variable for new processes and never lands in the chat transcript.

Equivalent conceptual config:

```json
{
  "mcpServers": {
    "home-assistant": {
      "command": "uvx",
      "args": ["--python", "3.13", "ha-mcp@latest"],
      "env": {
        "HOMEASSISTANT_URL": "https://YOUR-HA-HOST",
        "HOMEASSISTANT_TOKEN": "YOUR_LONG_LIVED_TOKEN"
      }
    }
  }
}
```

Tools appear on the **next** agent turn after the server is added successfully.

### Option B — Thin wrapper script (what Nexus uses)

Useful if you want a single entrypoint, a default URL, and a clear error when the token is missing:

```sh
#!/bin/sh
# Example: /home/box/.local/bin/ha-mcp-grok
set -eu
if [ -z "${HOMEASSISTANT_TOKEN:-}" ]; then
  echo "HOMEASSISTANT_TOKEN is not set in this process" >&2
  exit 1
fi
export HOMEASSISTANT_URL="${HOMEASSISTANT_URL:-https://YOUR-HA-HOST}"
exec /usr/local/bin/uvx ha-mcp@latest
```

```bash
chmod +x /path/to/ha-mcp-grok
```

Register MCP with:

| Field | Value |
|-------|--------|
| **Command** | `/path/to/ha-mcp-grok` |
| **Args** | _(empty)_ |
| **Env** | `HOMEASSISTANT_TOKEN` (required), optional `HOMEASSISTANT_URL` override |

Nexus’s wrapper defaults `HOMEASSISTANT_URL` and always requires `HOMEASSISTANT_TOKEN` from the host secret store.

---

## Step 3B — Cursor IDE / Claude Desktop (local laptop)

Same env vars; config file shape matches ha-mcp’s docs.

**Claude Desktop** (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "Home Assistant": {
      "command": "uvx",
      "args": ["--python", "3.13", "ha-mcp@latest"],
      "env": {
        "HOMEASSISTANT_URL": "http://homeassistant.local:8123",
        "HOMEASSISTANT_TOKEN": "YOUR_LONG_LIVED_TOKEN"
      }
    }
  }
}
```

On Linux, prefer the **absolute path** to `uvx` (`which uvx`) because GUI apps often lack your shell `PATH`.

Then fully quit and reopen the app.

---

## Step 4 — Verify

Ask the assistant to:

1. List MCP status / confirm `home-assistant` is **connected** with a non-zero tool count.
2. Call a read-only tool (examples vary by ha-mcp version), e.g. overview / search / get state for `sun.sun`.
3. Confirm HA version and entity counts look right.

If tools = 0 or the server is disconnected, re-check URL reachability, token, and Python 3.13 via `uvx --python 3.13 ha-mcp@latest` in a terminal.

Smoke-test without your HA (public demo from ha-mcp docs):

```bash
HOMEASSISTANT_URL=https://ha-mcp-demo-server.qc-h.net \
HOMEASSISTANT_TOKEN=demo \
uvx --python 3.13 ha-mcp@latest
```

---

## What the assistant can do once connected

ha-mcp exposes a large tool surface (dozens of tools). Typical capabilities Nexus uses:

| Area | Examples |
|------|----------|
| Inventory | Search entities, areas, overview, system health |
| State | Get / history for sensors, lights, etc. |
| Automations | Get / set / remove automation YAML via API |
| Helpers / scripts / scenes / dashboards | Config get/set where enabled |
| Control | Call services, bulk control (use sparingly) |
| Backups | Per-edit snapshots and full HA snapshots (when enabled) |
| Best practices | Skill guide gate before writing automations |

Exact tool names depend on ha-mcp version. After connect, inspect the MCP tool list rather than hard-coding old names.

---

## Paths we intentionally did **not** use

### Official Home Assistant MCP Server (`/api/mcp`)

HA can expose Streamable HTTP MCP at `/api/mcp` with a bearer token and optional `mcp-proxy` for stdio-only clients. That is a valid alternative for Claude Desktop, but:

- It is a **different** stack from ha-mcp’s rich automation/config tools.
- Grok Bot’s working setup for Nexus is **ha-mcp stdio**, not `/api/mcp`.

Docs: [Home Assistant MCP Server integration](https://www.home-assistant.io/integrations/mcp_server/)

### `mcp-proxy` in front of HA

We tried `mcp-proxy` as a bridge and hit a hard dependency failure (`ImportError: cannot import name 'request_ctx' from 'mcp.server.lowlevel.server'`). Fix was to **drop mcp-proxy** and run `uvx ha-mcp@latest` directly. Prefer that unless you specifically need HA’s built-in `/api/mcp`.

### OpenCode inside Home Assistant

Separate from MCP: OpenCode is an HA App that runs coding agents **inside** Home Assistant. Nexus can also talk to HA over MCP from Grok Bot. Friends can use either or both; do not confuse OpenCode model settings with MCP connectivity.

---

## Security checklist

- [ ] Token never committed to git, Discord, Slack, or email.
- [ ] Prefer HTTPS with a real cert for any internet-exposed HA.
- [ ] Prefer a dedicated HA user + token for the assistant.
- [ ] Treat automation writes as **high impact**: snapshot / edit-backup before apply; human approves live changes.
- [ ] Never expose the HA admin UI to the public internet without auth (Nabu Casa / SSO / VPN).
- [ ] Rotate the token if it was pasted into chat by mistake.
- [ ] Disable or tightly scope tools that can restart HA, delete devices, or push YAML if the client cannot enforce approval.

Nexus operating rules (homelab): no SSH to live hosts from the agent, no unapproved Git push, no untested live YAML without a recovery point, flag WAN-exposed admin / disabled auth / heat lockouts.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `HOMEASSISTANT_TOKEN is not set` | Secret not injected into the MCP process; re-add env / secret card |
| Tools missing after add | New turn / restart client; confirm server status connected |
| Old Python / install fails | `uv python install 3.13` and pass `--python 3.13` |
| Flaky or empty tools | `uvx --refresh --python 3.13 ha-mcp@latest`; check ha-mcp release notes |
| Works on laptop, fails on Grok Bot | Bot cannot reach `homeassistant.local`; use public HTTPS URL or VPN into the house |
| Assistant “forgets” safety | Put standing rules in the agent profile (approve before apply, backup first) |

---

## Minimal copy-paste for a friend

1. Create HA long-lived token (Profile → Security).
2. Install `uv` on the machine running the assistant.
3. Ensure `https://your-ha` is reachable from that machine.
4. Add MCP:

```text
command: uvx
args:    --python 3.13 ha-mcp@latest
env:     HOMEASSISTANT_URL=https://your-ha
env:     HOMEASSISTANT_TOKEN=<secret>
```

5. Ask the assistant to read `sun.sun` and list a few automations before allowing any writes.

---

## Repo contents

| File | Purpose |
|------|---------|
| `README.md` | This guide |
| `examples/ha-mcp-grok.sh` | Example wrapper script |
| `examples/mcp.example.json` | Example MCP client config (placeholders only) |

---

## References

- [ha-mcp GitHub](https://github.com/homeassistant-ai/ha-mcp)
- [ha-mcp Linux guide](https://homeassistant-ai.github.io/ha-mcp/guide-linux/)
- [ha-mcp FAQ](https://homeassistant-ai.github.io/ha-mcp/faq/)
- [Home Assistant MCP Server (official `/api/mcp`)](https://www.home-assistant.io/integrations/mcp_server/)

---

*Documented from the Nexus / Grok Bot production path. Update URLs and paths for your environment. No secrets belong in this repository.*
