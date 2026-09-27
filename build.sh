#!/bin/bash
# Builds ColorMyFolder (Release), installs it and starts it.
#
# Installs to ~/Applications unless the untracked file .install-dir names another folder
# (one line, a path). Signs with the identity set in the Xcode project when that certificate
# is in your keychain, otherwise ad hoc. CODE_SIGN_IDENTITY in the environment overrides both.
set -euo pipefail
cd "$(dirname "$0")"

TARGET="$HOME/Applications"
if [ -f .install-dir ]; then TARGET="$(head -n 1 .install-dir)"; fi

./Tests/check.sh
SIGN=()
PROJECT_ID="$(grep -m1 -o 'CODE_SIGN_IDENTITY = [0-9A-F]*' ColorMyFolder.xcodeproj/project.pbxproj | cut -d' ' -f3)"
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
  SIGN=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY")
# No -v: find-identity -v hides self-signed certificates.
elif ! security find-identity -p codesigning | grep -q "$PROJECT_ID"; then
  echo "Signing certificate from the project not found — signing ad hoc."
  SIGN=(CODE_SIGN_IDENTITY=-)
fi
LOG="$(mktemp)"
# ${SIGN[@]+...}: macOS bash 3.2 treats an empty array as unbound under set -u.
if ! xcodebuild -project ColorMyFolder.xcodeproj -scheme ColorMyFolder -configuration Release \
     -derivedDataPath build/dd build ${SIGN[@]+"${SIGN[@]}"} > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" || tail -20 "$LOG"
  echo "Build failed — nothing installed. Full log: $LOG"
  exit 1
fi
grep -E "BUILD SUCCEEDED" "$LOG"
APP="build/dd/Build/Products/Release/ColorMyFolder.app"

pkill -x ColorMyFolder || true
mkdir -p "$TARGET/ColorMyFolder.app"
rsync -a --delete "$APP/" "$TARGET/ColorMyFolder.app/"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# The quick action opens the app by bundle ID — keep only the installed copy registered.
"$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
"$LSREGISTER" -f "$TARGET/ColorMyFolder.app"
/System/Library/CoreServices/pbs -update
open "$TARGET/ColorMyFolder.app"
echo "Installed: $TARGET/ColorMyFolder.app"
codesign -dvv "$TARGET/ColorMyFolder.app" 2>&1 | grep -m1 -E "^Authority=|^Signature=adhoc" || true
