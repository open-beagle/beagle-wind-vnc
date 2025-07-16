ARG BASE
FROM $BASE

ARG S3_URL
ARG S3_ACCESS_KEY
ARG S3_ACCESS_SECRET


RUN echo "Install cuda-toolkit" && \
    wget -q -P /tmp https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin && \
    sudo mv /tmp/cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600 && \
    wget -q -P /tmp https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb && \
    sudo dpkg -i /tmp/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb && \
    sudo cp /var/cuda-repo-ubuntu2404-12-8-local/cuda-*-keyring.gpg /usr/share/keyrings/ && \
    sudo apt-get update && \
    sudo apt-get -y install cuda-toolkit-12-8 && \
    export PATH=/usr/local/cuda-12.8/bin:$PATH && \
    rm -f /tmp/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb && \
    echo "Install cudnn" && \
    wget -q -P /tmp https://developer.download.nvidia.com/compute/cudnn/9.10.2/local_installers/cudnn-local-repo-ubuntu2404-9.10.2_1.0-1_amd64.deb && \
    sudo dpkg -i /tmp/cudnn-local-repo-ubuntu2404-9.10.2_1.0-1_amd64.deb && \
    sudo cp /var/cudnn-local-repo-ubuntu2404-9.10.2/cudnn-*-keyring.gpg /usr/share/keyrings/ && \
    sudo apt-get update && \
    sudo apt-get -y install cudnn && \
    rm -f /tmp/cudnn-local-repo-ubuntu2404-9.10.2_1.0-1_amd64.debecho  && \
    echo "Install ComfyUI" && \
    bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET && \
    curl -s -ko /tmp/ComfyUI_0.3.43_install.sh https://www.bc-cloud.com/maas/api/static/software/ComfyUI0.3.43/install.sh && \
    bash /tmp/ComfyUI_0.3.43_install.sh /usr/local/lib && \
    rm -f /tmp/ComfyUI_0.3.43_install.sh && \
    echo "Install StableDiffusion" && \
    bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET && \
    curl -s -ko /tmp/StableDiffusion_V1.0.0_install.sh https://www.bc-cloud.com/maas/api/static/software/StableDiffusionV1.0.0/install.sh && \
    bash  /tmp/StableDiffusion_V1.0.0_install.sh /usr/local/lib && \
    rm -f /tmp/StableDiffusion_V1.0.0_install.sh
    echo "Install Rope" && \
    bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET && \
    curl -s -ko /tmp/Rope_24.05.27_install.sh https://www.bc-cloud.com/maas/api/static/software/Rope_24.05.27_install.sh/install.sh && \
    bash  /tmp/Rope_24.05.27_install.sh /usr/local/lib && \
    rm -f /tmp/Rope_24.05.27_install.sh

ENV PATH="/usr/local/cuda-12.8/bin:$PATH"