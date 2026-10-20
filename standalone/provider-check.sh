#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ClipboardModuleCache
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  Sources/AISolver/Models.swift standalone/Tests/ProviderConfigurationCheck.swift -o build/provider-config-check
./build/provider-config-check
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  Sources/AISolver/Models.swift standalone/Sources/ModelCatalog.swift standalone/Tests/CatalogCheck.swift -o build/catalog-check
./build/catalog-check
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  Sources/AISolver/Models.swift Sources/AISolver/OpenAIClient.swift standalone/Sources/ClipboardInput.swift \
  standalone/Sources/ImageQuestionReader.swift standalone/Sources/ClaudeClient.swift standalone/Sources/ClaudeMaterials.swift \
  standalone/Tests/ClaudeCheck.swift -o build/claude-check -framework AppKit -framework ImageIO -framework PDFKit
./build/claude-check
