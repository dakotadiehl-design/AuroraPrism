#!/usr/bin/env bash
# Regenerate Aurora.xcodeproj from project.yml (requires xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate
echo "Generated Aurora.xcodeproj from project.yml"
