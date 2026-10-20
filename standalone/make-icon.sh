#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
temporary=$(mktemp -d "$PWD/build/app-icon.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
iconset="$temporary/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" standalone/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" standalone/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o standalone/Resources/AppIcon.icns
