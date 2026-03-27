#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILE="tbs5580"
KVER="${KVER:-$(uname -r)}"
KDIR="${KDIR:-/lib/modules/$KVER/build}"
PACKAGE="$BASE_DIR/out/dist/$PROFILE-k$KVER.tar.xz"

log() {
  printf '[rebuild-tbs5580] %s\n' "$*"
}

if [ ! -d "$KDIR" ]; then
  log "missing kernel build dir: $KDIR"
  log "install headers first: sudo apt-get install linux-headers-$KVER"
  exit 2
fi

log "building $PROFILE for kernel $KVER"
make -C "$BASE_DIR" package PROFILE="$PROFILE" KVER="$KVER" KDIR="$KDIR"

log "package ready: $PACKAGE"
log "reload modules: sudo $BASE_DIR/out/$PROFILE/load-tbs5580.sh"
log "or restart service: sudo systemctl restart tbs5580-modules.service"
