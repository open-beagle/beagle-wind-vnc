ARG BASE
FROM $BASE

ARG S3_URL
ARG S3_ACCESS_KEY
ARG S3_ACCESS_SECRET

SHELL ["/bin/bash", "-c"]

RUN bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET && \
    echo "Install cuda-toolkit && cudnn" && \
    curl -s -ko /tmp/cuda_toolkit_12.8_install.sh https://www.bc-cloud.com/maas/api/static/software/cuda_toolkit12.8/install.sh && \
    bash /tmp/cuda_toolkit_12.8_install.sh  && \
    rm -f /tmp/cuda_toolkit_12.8_install.sh && \
    echo "Install Miniconda3" && \
    bgctl cp "default/maas-public/software/IsaacGym4.5.0/Miniconda3-latest-Linux-x86_64.sh" /usr/local/lib && \
    cd /usr/local/lib && \
    chmod +x Miniconda3-latest-Linux-x86_64.sh && \
    bash ./Miniconda3-latest-Linux-x86_64.sh -b -p /usr/local/lib/miniconda && \
    rm Miniconda3-latest-Linux-x86_64.sh && \
    echo "Miniconda 安装完成"
ENV PATH="/usr/local/cuda-12.8/bin:/usr/local/lib/miniconda/bin:$PATH"

RUN echo "Install IsaacGym" && \
    curl -s -ko /tmp/IsaacGym_4.5.0_install.sh https://www.bc-cloud.com/maas/api/static/software/IsaacGym4.5.0/install.sh && \
    bash  /tmp/IsaacGym_4.5.0_install.sh /usr/local/lib && \
    rm -f /tmp/IsaacGym_4.5.0_install.sh && \
    echo "Install IsaacSim" && \
    curl -s -ko /tmp/IsaacSim_4.5.0_install.sh https://www.bc-cloud.com/maas/api/static/software/IsaacSim4.5.0/install.sh && \
    bash /tmp/IsaacSim_4.5.0_install.sh /usr/local/lib && \
    rm -f /tmp/IsaacSim_4.5.0_install.sh && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

ENV HF_ENDPOINT=https://hf-mirror.com