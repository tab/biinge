#!/usr/bin/env bash
# Installs the pinned SwiftLint release (keep it in step with the version developers run locally)
set -euo pipefail

version=0.65.1
tmp="$(mktemp -d)"

curl -fsSL -o "$tmp/swiftlint.zip" "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip"
unzip -q -o "$tmp/swiftlint.zip" -d "$tmp"
sudo install "$tmp/swiftlint" /usr/local/bin/swiftlint
swiftlint version
