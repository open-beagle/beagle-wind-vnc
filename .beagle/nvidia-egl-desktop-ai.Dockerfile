ARG BASE_IMAGE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-desktop-latest
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
RUN echo "Install ComfyUI" && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /usr/local/lib/ComfyUI && \
    # 修正文件权限
    chown -R 1000:1000 /usr/local/lib/ComfyUI && \
    # 安装ComfyUI
    cd /usr/local/lib/ComfyUI && \
    python3 -m venv venv && \
    . venv/bin/activate && \
    pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn && \
    mkdir -p /home/ubuntu/Desktop && \
    # 修正Here Document格式（EOF顶格）
    cat <<EOF > $HOME/Desktop/Comfyui.desktop
[Desktop Entry]
Name=ComfyUI
Comment=Stable Diffusion GUI
Exec=bash -c 'source /usr/local/lib/ComfyUI/venv/bin/activate && cd /usr/local/lib/ComfyUI && python main.py --listen 0.0.0.0 --port 8082'
Icon=/usr/local/lib/comfyui.png
Terminal=true
Type=Application
Categories=Graphics;AI;
StartupNotify=true
EOF

COPY --chown=1000:1000 ./.beagle/icon/comfyui.png /usr/local/lib/comfyui.png
