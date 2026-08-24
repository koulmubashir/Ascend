#!/bin/bash
# Builds a scheme, working around a signing failure on incremental builds.
#
# The problem: on any incremental build, Xcode leaves AscendWatchWidget.appex
# unsigned, and validation then fails with "Embedded binary is not signed with
# the same certificate as the parent app". The stale unsigned appex persists, so
# every later build fails identically until it is removed. This affects the
# Ascend scheme too, because the phone app embeds the Watch app which embeds the
# complication.
#
# Tried and did not help: a non-empty entitlements file on the extension,
# CODE_SIGN_IDENTITY[sdk=watchsimulator*] = "-", and CODE_SIGNING_REQUIRED=YES.
# Root cause not established; this removes the stale artifact so the next build
# re-signs it.
#
#   ./build.sh                 # phone app, iPhone 17 Pro simulator
#   ./build.sh AscendWatch     # watch app, Ultra 3 simulator
set -euo pipefail

SCHEME="${1:-Ascend}"
case "$SCHEME" in
  AscendWatch*) DEST="platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)" ;;
  *)            DEST="platform=iOS Simulator,name=iPhone 17 Pro" ;;
esac

find ~/Library/Developer/Xcode/DerivedData/Ascend-*/Build/Products \
  -name "AscendWatchWidget.appex" -exec rm -rf {} + 2>/dev/null || true

xcodebuild -project Ascend.xcodeproj -scheme "$SCHEME" -destination "$DEST" build
