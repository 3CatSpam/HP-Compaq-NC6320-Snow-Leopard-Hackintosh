#!/bin/bash
# Builds the TLS 1.2 files (Security + securityd) and puts them in Extra/tls/.
# Run this on a Mac OS X 10.6.8 build machine (Xcode 4.1, 10.6 SDK, llvm-gcc-4.2), NOT on the nc6320 stick.
# Usage: bash build_tls.sh /path/to/tls12-snow-leopard-merge
# Get that folder on another computer: https://github.com/startergo/tls12-snow-leopard-merge  (Code > Download ZIP),
# unzip it and copy it over. Snow Leopard 10.6.8 cannot open GitHub itself.
set -e
SRC="${1:-}"; HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SRC/build-consistent-framework.sh" ] || { echo "Usage: bash build_tls.sh /path/to/tls12-snow-leopard-merge"; exit 1; }
[ "$(sw_vers -productVersion 2>/dev/null)" = "10.6.8" ] || { echo "This must run on Mac OS X 10.6.8."; exit 1; }
command -v llvm-gcc-4.2 >/dev/null || { echo "llvm-gcc-4.2 not found: install Xcode 4.1 (see the project's BUILDING.md)."; exit 1; }
cd "$SRC"
VM="$(pwd)" STAGE=bootstrap bash build-consistent-framework.sh
VM="$(pwd)" STAGE=all ARCHES='x86_64 i386' bash build-consistent-framework.sh
mkdir -p "$HERE/Extra/tls"
cp Security.fat.new "$HERE/Extra/tls/Security"
cp dst-securityd-fat/securityd "$HERE/Extra/tls/securityd"
cp vendor/anchors/ssl_anchors.pem "$HERE/Extra/tls/ssl_anchors.pem"
echo "Done. Files are in Extra/tls/. This script does NOT install them on this machine."
shasum -a 256 "$HERE/Extra/tls/Security" "$HERE/Extra/tls/securityd"
