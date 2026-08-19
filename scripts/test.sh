#!/bin/bash
# Unit tests via Xcode.app (same toolchain as AGENTS.md / BUILDING.md).
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
"$DEVELOPER_DIR/usr/bin/xcodebuild" test \
  -project Prism.xcodeproj \
  -scheme Prism \
  -testPlan PrismTests \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug
