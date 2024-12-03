#!/bin/bash

if [ "$(echo ${KASMVNC_ENABLE} | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  /etc/kasmvnc-entrypoint.sh
else
  sleep infinity
fi
