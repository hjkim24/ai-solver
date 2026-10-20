#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/Clipboard AI Solver.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/ClipboardModuleCache
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  Sources/AISolver/Models.swift Sources/AISolver/OpenAIClient.swift Sources/AISolver/JobController.swift Sources/AISolver/CapsLockLED.swift \
  standalone/Sources/*.swift -o "$app/Contents/MacOS/ClipboardAISolver" \
  -framework AppKit -framework Security -framework ImageIO -framework IOKit -framework PDFKit
cp standalone/Resources/Info.plist "$app/Contents/Info.plist"
cp standalone/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
python3 scripts/sign-app.py "$app"
printf '%s\n' "$app"
