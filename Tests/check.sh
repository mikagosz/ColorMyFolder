#!/bin/bash
# Headless check of ColorMyFolder's logic and list file — no windows, no Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/check"
swiftc -o "$OUT" ColorMyFolder/Logic.swift ColorMyFolder/Store.swift ColorMyFolder/UpdateSupport.swift Tests/main.swift -module-name Check 2>&1 | grep -v "^$" || true
"$OUT"
