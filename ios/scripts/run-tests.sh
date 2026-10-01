#!/usr/bin/env bash
# The core is Foundation-only, so its 90-odd tests run on macOS and Linux alike.
#
#   bash ios/scripts/run-tests.sh            # swift test
#   bash ios/scripts/run-tests.sh sentinel   # tests, then a live scan with the CLI
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --parallel
if [ "${1:-}" = "sentinel" ]; then
  swift build
  ./.build/debug/sentinel scan bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu
fi
