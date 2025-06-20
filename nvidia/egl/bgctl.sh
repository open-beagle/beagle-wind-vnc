#!/bin/bash
if [ -f "/tools/bgctl" ]; then
    cp -r /tools/bgctl /usr/local/bin/bgctl && chmod +x /usr/local/bin/bgctl
    bgctl alias set default $S3_URL $S3_ACCESS_KEY $S3_ACCESS_SECRET
fi