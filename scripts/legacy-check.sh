#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache
for source in extension/*.js extension/tests/*.cjs; do node --check "$source"; done
python3 -m json.tool extension/manifest.json >/dev/null
node extension/tests/background-check.cjs
python3 -B Tests/InstallerCheck.py
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ModuleCache -parse-as-library \
  Sources/AISolver/Models.swift Sources/AISolver/NativeMessaging.swift \
  Sources/AISolver/OpenAIClient.swift Sources/AISolver/JobController.swift Sources/AISolver/CapsLockLED.swift \
  Tests/SelfCheck.swift Tests/JobCheck.swift Tests/ModeCheck.swift Tests/LEDCheck.swift -o build/selfcheck -framework AppKit -framework ImageIO -framework IOKit
./build/selfcheck
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ModuleCache -parse-as-library \
  Sources/AISolver/ApplicationMenu.swift Tests/EditingCheck.swift -o build/editing-check -framework AppKit
./build/editing-check
