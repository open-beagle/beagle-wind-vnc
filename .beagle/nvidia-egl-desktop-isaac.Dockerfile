ARG BASE
FROM $BASE

ARG S3_URL
ARG S3_ACCESS_KEY
ARG S3_ACCESS_SECRET


RUN bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET && \
    echo "Install cuda-toolkit" && \
    bgctl cp default/cache/cuda/cuda-ubuntu2404.pin /tmp/ && \
    sudo mv /tmp/cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600 && \
    bgctl cp default/cache/cuda/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb /tmp/ && \
    sudo dpkg -i /tmp/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb && \
    sudo cp /var/cuda-repo-ubuntu2404-12-8-local/cuda-*-keyring.gpg /usr/share/keyrings/ && \
    sudo apt-get update && \
    sudo apt-get -y install cuda-toolkit-12-8 && \
    export PATH=/usr/local/cuda-12.8/bin:$PATH && \
    rm -f /tmp/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb && \
    echo "Install cudnn" && \
    bgctl cp default/cache/cuda/cudnn-local-repo-ubuntu2404-9.10.2_1.0-1_amd64.deb /tmp/  && \
    sudo dpkg -i /tmp/cudnn-local-repo-ubuntu2404-9.10.2_1.0-1_amd64.deb && \
    sudo cp /var/cudnn-local-repo-ubuntu2404-9.10.2/cudnn-*-keyring.gpg /usr/share/keyrings/ && \
    sudo apt-get update && \
    sudo apt-get -y install cudnn && \
    rm -f /tmp/cudnn-local-repo-ubuntu2404-9.10.2_1.0-1_amd64.debecho  && \
    echo "Install IsaacSim" && \
    curl -s -ko /tmp/IsaacSim_4.5.0_install.sh https://www.bc-cloud.com/maas/api/static/software/IsaacSim4.5.0/install.sh && \
    bash /tmp/IsaacSim_4.5.0_install.sh /usr/local/lib && \
    rm -f /tmp/IsaacSim_4.5.0_install.sh && \
    echo "Install IsaacGym" && \
    curl -s -ko /tmp/IsaacGym_4.5.0_install.sh https://www.bc-cloud.com/maas/api/static/software/IsaacGym4.5.0/install.sh && \
    bash  /tmp/IsaacGym_4.5.0_install.sh /usr/local/lib && \
    rm -f /tmp/IsaacGym_4.5.0_install.sh

ENV PATH="/usr/local/cuda-12.8/bin:$PATH"