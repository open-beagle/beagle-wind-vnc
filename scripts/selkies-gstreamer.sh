#!/bin/bash

if [ "$(echo ${KASMVNC_ENABLE} | tr '[:upper:]' '[:lower:]')" != "true" ]; then
  /etc/selkies-gstreamer-entrypoint.sh
else
  sleep infinity
fi
