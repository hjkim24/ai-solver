#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/Canvas RAG Solver.app"
mkdir -p "$app/Contents/MacOS" build/ModuleCache
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ModuleCache -parse-as-library \
  Sources/AISolver/*.swift -o "$app/Contents/MacOS/CanvasRAGSolver" \
  -framework AppKit -framework Security -framework ImageIO -framework IOKit
if [[ ! -f "$app/Contents/Info.plist" ]]; then cp Resources/Info.plist "$app/Contents/Info.plist"; fi
codesign --force --sign - "$app" 2>build/codesign.log
printf '%s\n' "$app"
