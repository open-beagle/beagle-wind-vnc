#!/bin/bash
if [ -f "/tools/bgctl" ]; then
  cp -r /tools/bgctl /usr/local/bin/bgctl && chmod +x /usr/local/bin/bgctl
  bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET
fi

if [ -f "/usr/local/lib/ComfyUI-0.3.43/Comfyui.desktop" ]; then
  cp /usr/local/lib/ComfyUI-0.3.43/Comfyui.desktop $HOME/Desktop/
fi