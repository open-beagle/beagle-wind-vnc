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
    echo "Install ComfyUI" && \
    curl -s -ko /tmp/ComfyUI_0.3.43_install.sh https://www.bc-cloud.com/maas/api/static/software/ComfyUI0.3.43/install.sh && \
    bash /tmp/ComfyUI_0.3.43_install.sh /usr/local/lib && \
    rm -f /tmp/ComfyUI_0.3.43_install.sh && \
    echo "Install StableDiffusion" && \
    curl -s -ko /tmp/StableDiffusion_V1.0.0_install.sh https://www.bc-cloud.com/maas/api/static/software/StableDiffusionV1.0.0/install.sh && \
    bash  /tmp/StableDiffusion_V1.0.0_install.sh /usr/local/lib && \
    rm -f /tmp/StableDiffusion_V1.0.0_install.sh && \
    echo "Install Rope" && \
    curl -s -ko /tmp/Rope_24.05.27_install.sh https://www.bc-cloud.com/maas/api/static/software/Rope24.05.27/install.sh && \
    bash  /tmp/Rope_24.05.27_install.sh /usr/local/lib && \
    rm -f /tmp/Rope_24.05.27_install.sh && \
    echo "Install Blender" && \
    curl -s -ko /tmp/Blender_4.4.3_install.sh https://www.bc-cloud.com/maas/api/static/software/Blender4.4.3/install.sh && \
    bash  /tmp/Blender_4.4.3_install.sh /usr/local/lib && \
    rm -f /tmp/Blender_4.4.3_install.sh

    
ENV PATH="/usr/local/cuda-12.8/bin:$PATH"
ENV HF_ENDPOINT=https://hf-mirror.com