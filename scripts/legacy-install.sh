#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 ]]; then
  printf '%s\n' 'Usage: bash scripts/legacy-install.sh EXTENSION_ID /absolute/browser-user-data/NativeMessagingHosts' >&2
  exit 2
fi
python3 scripts/register-host.py "$1" "$2"
