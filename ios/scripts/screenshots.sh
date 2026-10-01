#!/usr/bin/env bash
# Real screenshots, taken on a simulator. Needs macOS with Xcode — there is no way to fake
# these, which is exactly why this repository does not contain any.
#
#   bash ios/scripts/screenshots.sh "iPhone 16 Pro"
set -euo pipefail

DEVICE="${1:-iPhone 16 Pro}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/screenshots"
BUNDLE_ID="com.sentinellabs.sentinelwallet"
mkdir -p "$OUT"

cd "$ROOT"
xcodegen generate
xcodebuild -project SentinelWallet.xcodeproj -scheme SentinelWallet \
  -destination "platform=iOS Simulator,name=$DEVICE" -configuration Debug build

xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
APP="$(xcodebuild -project SentinelWallet.xcodeproj -scheme SentinelWallet \
  -destination "platform=iOS Simulator,name=$DEVICE" -showBuildSettings \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/SentinelWallet.app"
xcrun simctl install booted "$APP"
xcrun simctl launch booted "$BUNDLE_ID"
sleep 4

xcrun simctl io booted screenshot "$OUT/01-lock.png"
echo "captured 01-lock.png"
echo "Unlock the app and capture the rest by hand:"
echo "  portfolio, wallets, scan results, address lookup, drawer"
