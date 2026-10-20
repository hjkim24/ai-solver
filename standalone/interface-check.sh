#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ClipboardModuleCache
fixture_dir=$(mktemp -d "$PWD/build/interface-fixture.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
fixture_app="$fixture_dir/Interface Fixture.app"
mkdir -p "$fixture_app/Contents/MacOS"
python3 - "$fixture_app/Contents/Info.plist" <<'PYPLIST'
import pathlib, plistlib, sys, uuid
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "com.hjkim24.clipboard-interface-fixture." + uuid.uuid4().hex,
    "CFBundleName": "Interface Fixture", "CFBundleExecutable": "InterfaceFixture",
    "CFBundlePackageType": "APPL", "LSUIElement": True,
}))
PYPLIST
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/ClipboardModuleCache -parse-as-library \
  Sources/AISolver/Models.swift Sources/AISolver/OpenAIClient.swift Sources/AISolver/JobController.swift Sources/AISolver/CapsLockLED.swift \
  standalone/Sources/App.swift standalone/Sources/AppInterface.swift standalone/Sources/ApplicationMenu.swift \
  standalone/Sources/ClaudeClient.swift standalone/Sources/ClaudeMaterials.swift standalone/Sources/ModelCatalog.swift \
  standalone/Sources/ClipboardInput.swift standalone/Sources/ImageQuestionReader.swift standalone/Tests/InterfaceCheck.swift \
  -o "$fixture_app/Contents/MacOS/InterfaceFixture" -framework AppKit -framework Security -framework ImageIO -framework IOKit -framework PDFKit
"$fixture_app/Contents/MacOS/InterfaceFixture" "$@"
