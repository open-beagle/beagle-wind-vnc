ARG KDE6_BASE_IMAGE=registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc
ARG KDE6_BASE_DIGEST=sha256:407b8da960cb236c98369dde05ee1e67a3dd86d21445eea9991f2e1b8316b0b3
FROM ${KDE6_BASE_IMAGE}@${KDE6_BASE_DIGEST}

ARG KDE6_BASE_DIGEST
ARG BLENDER_VERSION=4.5.14
ARG BLENDER_URL=https://download.blender.org/release/Blender4.5/blender-4.5.14-linux-x64.tar.xz
ARG BLENDER_SHA256=9ba871ff2ecd36526b77432745980b7e6664ecd0c7ca11c48849073dcfe06da3
ARG BLENDER_MCP_VERSION=0.1.0

LABEL maintainer="https://github.com/open-beagle" \
      org.opencontainers.image.title="Beagle Wind KDE6 Blender MCP" \
      org.opencontainers.image.description="App-only Blender 4.5 LTS with a policy-bound MCP bridge" \
      org.opencontainers.image.version="${BLENDER_MCP_VERSION}" \
      blender.version="${BLENDER_VERSION}" \
      blender.mcp.version="${BLENDER_MCP_VERSION}" \
      kde6.base.digest="${KDE6_BASE_DIGEST}" \
      blender.mcp.lock="/etc/beagle-wind-vnc/kde6-blender-mcp.lock"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
RUN test -n "${BLENDER_SHA256}" && \
    mkdir -p /opt/blender && \
    curl --retry 4 --retry-delay 2 -fsSL "${BLENDER_URL}" -o /tmp/blender.tar.xz && \
    echo "${BLENDER_SHA256}  /tmp/blender.tar.xz" | sha256sum -c - && \
    tar -xJf /tmp/blender.tar.xz --strip-components=1 -C /opt/blender && \
    rm -f /tmp/blender.tar.xz && \
    test -x /opt/blender/blender && \
    ln -sf /opt/blender/blender /usr/local/bin/blender && \
    /opt/blender/blender --version | grep -F "${BLENDER_VERSION}" && \
    mkdir -p /opt/beagle/blender-mcp /workspace/project /workspace/inbox /workspace/exports /workspace/checkpoints /workspace/cache /run/user/1000 && \
    chown -R beagle:beagle /opt/beagle/blender-mcp /workspace /run/user/1000

COPY KDE6/BlenderMCP/ /opt/beagle/blender-mcp/
COPY .beagle/kde6-blender-mcp.lock /etc/beagle-wind-vnc/kde6-blender-mcp.lock

RUN chmod +x /opt/beagle/blender-mcp/*.sh /opt/beagle/blender-mcp/mcp-bridge/bridge.py && \
    chown -R beagle:beagle /opt/beagle/blender-mcp /etc/beagle-wind-vnc/kde6-blender-mcp.lock

USER beagle
WORKDIR /home/beagle
ENV BLENDER_VERSION="${BLENDER_VERSION}" \
    BLENDER_MCP_VERSION="${BLENDER_MCP_VERSION}" \
    BLENDER_MCP_ADAPTER_SOCKET="/run/user/1000/blender-mcp-adapter.sock" \
    BLENDER_MCP_LISTEN_HOST="0.0.0.0" \
    BDWIND_PORT_NGINX="48083" \
    BLENDER_MCP_PORT="48084" \
    BLENDER_FILE_AGENT_PORT="48085" \
    BLENDER_MCP_MAX_BODY_BYTES="1048576" \
    BLENDER_MCP_REQUEST_TIMEOUT_MS="10000" \
    BLENDER_MCP_JOB_TIMEOUT_MS="600000" \
    BDWIND_ENABLE_WEBRTC="true" \
    BDWIND_KDE6_MODE="nested-smithay"

EXPOSE 48083 48084 48085

ENTRYPOINT ["/opt/beagle/blender-mcp/blender-mcp-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/opt/beagle/blender-mcp/supervisord-blender.conf"]
