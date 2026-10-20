#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ClipboardModuleCache
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  Sources/AISolver/Models.swift Sources/AISolver/OpenAIClient.swift Sources/AISolver/JobController.swift \
  standalone/Sources/ClipboardInput.swift standalone/Sources/ImageQuestionReader.swift \
  standalone/Tests/ClipboardCheck.swift -o build/clipboard-check -framework AppKit -framework ImageIO
./build/clipboard-check
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  standalone/Sources/ApplicationMenu.swift Tests/EditingCheck.swift -o build/clipboard-editing-check -framework AppKit
./build/clipboard-editing-check
