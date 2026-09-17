#!/bin/sh
# Example wrapper for Grok Bot / Cursor custom MCP (stdio).
# Copy to a stable path, chmod +x, and point the MCP "command" at it.
set -eu
if [ -z "${HOMEASSISTANT_TOKEN:-}" ]; then
  echo "HOMEASSISTANT_TOKEN is not set in this process" >&2
  exit 1
fi
# Override per-host if needed: export HOMEASSISTANT_URL=https://ha.example.com
export HOMEASSISTANT_URL="${HOMEASSISTANT_URL:-https://YOUR-HA-HOST}"
# Prefer absolute uvx when the MCP host has a thin PATH
UVX_BIN="${UVX_BIN:-uvx}"
exec "$UVX_BIN" --python 3.13 ha-mcp@latest
