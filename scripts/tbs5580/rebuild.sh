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
log ""
log "This is the tarball fallback for hosts without DKMS."
log "On a DKMS host nothing needs reloading: the modules are rebuilt"
log "automatically on every kernel update. See README.en.md,"
log "'Automating the rebuild (DKMS)'."
log ""
log "Tarball route, only if DKMS is not in use -- the load and unload"
log "commands for this build are in:"
log "  $BASE_DIR/out/$PROFILE/INSTALL.txt"
