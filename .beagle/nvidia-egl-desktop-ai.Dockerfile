ARG BASE_IMAGE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-desktop-latest
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
RUN echo "Install ComfyUI" && \
    bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET && \
    curl -ko $HOME/ComfyUI_0.3.43_install.sh https://www.bc-cloud.com/maas/api/static/software/ComfyUI0.3.43/install.sh && bash  $HOME/ComfyUI_0.3.43_install.sh /usr/loca/lib
