#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 0 ]]; then
  printf '%s\n' 'Usage: bash scripts/install.sh (브라우저 확장 등록은 더 이상 필요하지 않습니다.)' >&2
  exit 2
fi
mkdir -p build/ClipboardModuleCache
swift -module-cache-path build/ClipboardModuleCache scripts/quit-app.swift com.hjkim24.clipboard-ai-solver com.hjkim24.canvas-rag-solver
bash scripts/build.sh
python3 scripts/install-app.py
open '/Applications/Clipboard AI Solver.app'
