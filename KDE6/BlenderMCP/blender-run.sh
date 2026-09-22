#!/bin/bash
set -euo pipefail

. /etc/beagle-wind-vnc/runtime-env.sh

until [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; do
    sleep 0.2
done

set +e
blender --factory-startup --python /opt/beagle/blender-mcp/blender-startup.py
result=$?
set -e

# A user closing Blender closes the whole single-application instance.  The
# supervisor is still responsible for ordered process cleanup.
supervisorctl -s unix:///tmp/supervisor.sock shutdown >/dev/null 2>&1 || true
exit "${result}"
