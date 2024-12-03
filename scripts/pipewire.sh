#!/bin/bash

until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do
  sleep 0.5
done

dbus-run-session -- /usr/bin/pipewire
