# /bin/bash

set -ex

export GO111MODULE=on
export CGO_ENABLED=0

GIT_COMMIT=$(git rev-parse --short HEAD)

LDFLAGS=(
  "-w -s"
)

cd ./addons/js-interposer

go build -o ./.tmp/joystick-server -ldflags "${LDFLAGS[*]}" .
