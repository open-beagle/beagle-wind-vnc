ARG BASE
FROM $BASE

ARG S3_URL
ARG S3_ACCESS_KEY
ARG S3_ACCESS_SECRET


RUN bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET && \
    echo "Install cuda-toolkit && cudnn" && \
    curl -s -ko /tmp/cuda_toolkit_12.8_install.sh https://www.bc-cloud.com/maas/api/static/software/cuda_toolkit12.8/install.sh && \
    bash /tmp/cuda_toolkit_12.8_install.sh  && \
    rm -f /tmp/cuda_toolkit_12.8_install.sh && \
    echo "Install IsaacGym" && \
    curl -s -ko /tmp/IsaacGym_4.5.0_install.sh https://www.bc-cloud.com/maas/api/static/software/IsaacGym4.5.0/install.sh && \
    bash  /tmp/IsaacGym_4.5.0_install.sh /usr/local/lib && \
    rm -f /tmp/IsaacGym_4.5.0_install.sh && \
    echo "Install IsaacSim" && \
    curl -s -ko /tmp/IsaacSim_4.5.0_install.sh https://www.bc-cloud.com/maas/api/static/software/IsaacSim4.5.0/install.sh && \
    bash /tmp/IsaacSim_4.5.0_install.sh /usr/local/lib && \
    rm -f /tmp/IsaacSim_4.5.0_install.sh && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

ENV PATH="/usr/local/cuda-12.8/bin:$PATH"
ENV HF_ENDPOINT=https://hf-mirror.com