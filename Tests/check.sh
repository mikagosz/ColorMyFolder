#!/bin/bash
# Headless check of ColorMyFolder's logic — no windows, no Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/check"
swiftc -o "$OUT" ColorMyFolder/Logic.swift Tests/main.swift -module-name Check 2>&1 | grep -v "^$" || true
"$OUT"
