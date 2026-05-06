#!/bin/bash

until [ "$(echo ${XDG_RUNTIME_DIR}/pipewire-*.lock)" != "${XDG_RUNTIME_DIR}/pipewire-*.lock" ]; do
  sleep 0.5
done

dbus-run-session -- /usr/bin/wireplumber
