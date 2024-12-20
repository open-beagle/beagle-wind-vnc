#!/bin/bash

# Set the locale
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Generate self-signed certificate
winpr-makecert -r -pe -n "CN=localhost" -b 01/01/2000 -e 01/01/2036 -sv /opt/privatekey.pem -ic /opt/cacert.pem /opt/certificate.pem

# Start dbus
dbus-run-session --exit-with-session xrdp-sesman &

# Start Weston
weston &

# Keep the container running
tail -f /dev/null