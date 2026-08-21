#!/usr/bin/env bash
# Reject forbidden production logging / error-presentation patterns.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

hits=$(grep -R --include='*.swift' -n -E '^\s*(print|debugPrint)\(' Sources || true)
if [[ -n "$hits" ]]; then
  echo "Forbidden print/debugPrint in Sources:"
  echo "$hits"
  fail=1
fi

hits=$(grep -R --include='*.swift' -n 'informativeText = error.localizedDescription' Sources || true)
if [[ -n "$hits" ]]; then
  echo "Forbidden NSAlert localizedDescription assignment:"
  echo "$hits"
  fail=1
fi

hits=$(grep -R --include='*.swift' -n 'Text(error.localizedDescription)' Sources || true)
if [[ -n "$hits" ]]; then
  echo "Forbidden SwiftUI alert localizedDescription:"
  echo "$hits"
  fail=1
fi

hits=$(grep -R --include='*.swift' -n 'onLog:' Sources || true)
if [[ -n "$hits" ]]; then
  echo "Remaining onLog diagnostics closures:"
  echo "$hits"
  fail=1
fi

hits=$(grep -R --include='*.swift' -n 'log: (String) -> Void' Sources || true)
if [[ -n "$hits" ]]; then
  echo "Remaining untyped log callbacks:"
  echo "$hits"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "lint-logging: ok"
