#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec bash standalone/build.sh
