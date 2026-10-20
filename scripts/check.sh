#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash standalone/check.sh
bash standalone/provider-check.sh
bash standalone/interface-check.sh
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  Sources/AISolver/Models.swift Sources/AISolver/NativeMessaging.swift \
  Sources/AISolver/OpenAIClient.swift Sources/AISolver/JobController.swift Sources/AISolver/CapsLockLED.swift \
  Tests/SelfCheck.swift Tests/JobCheck.swift Tests/ModeCheck.swift Tests/LEDCheck.swift -o build/shared-selfcheck -framework AppKit -framework ImageIO -framework IOKit
./build/shared-selfcheck
