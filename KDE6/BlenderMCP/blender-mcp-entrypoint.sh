#!/bin/bash
set -euo pipefail

. /etc/beagle-wind-vnc/runtime-env.sh

: "${INSTANCE_ID:?INSTANCE_ID is required}"
: "${WORKSPACE_ROOT:=/workspace}"
: "${BLENDER_MCP_TOKEN_FILE:=/run/user/1000/blender-mcp-token}"

# Reuse the KDE6 base entrypoint's device, DBus, runtime-directory and
# machine-id preparation, but pass a no-op command so it does not start the
# generic desktop command.  The Blender supervisor below owns this instance.
/etc/beagle-wind-vnc/entrypoint.sh true

mkdir -p "${XDG_RUNTIME_DIR}" "${WORKSPACE_ROOT}"/{project,inbox,exports,checkpoints,cache}
chmod 700 "${XDG_RUNTIME_DIR}" "${WORKSPACE_ROOT}"/{project,inbox,exports,checkpoints,cache}

if [ ! -s "${BLENDER_MCP_TOKEN_FILE}" ]; then
    if [ "${BLENDER_MCP_DEV_GENERATE_TOKEN:-false}" != "true" ]; then
        echo "[blender-mcp] token file is missing; inject a Secret or set BLENDER_MCP_DEV_GENERATE_TOKEN=true for local smoke tests" >&2
        exit 78
    fi
    umask 077
    mkdir -p "$(dirname "${BLENDER_MCP_TOKEN_FILE}")"
    python3 - <<'PY' >"${BLENDER_MCP_TOKEN_FILE}"
import secrets
print(secrets.token_urlsafe(32))
PY
fi
chmod 600 "${BLENDER_MCP_TOKEN_FILE}"

test -r /etc/beagle-wind-vnc/kde6-blender-mcp.lock
test -x /usr/local/bin/blender
test -f /opt/beagle/blender-mcp/mcp-bridge/bridge.py
test -f /opt/beagle/blender-mcp/blender-mcp-plugin/register.py

exec "$@"
