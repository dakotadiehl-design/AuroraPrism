#!/usr/bin/env bash
# Fail if a Sources catch site is missing from docs/Diagnostics/ErrorCatchAudit.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ROOT/docs/Diagnostics/ErrorCatchAudit.md"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

python3 - "$ROOT" "$tmp" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1]) / "Sources"
out = pathlib.Path(sys.argv[2])
rows = []
for path in root.rglob("*.swift"):
    text = path.read_text(errors="replace").splitlines()
    rel = path.relative_to(root.parent).as_posix()
    for i, line in enumerate(text, 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if "catch" in stripped and ("catch {" in line or "catch let" in line or stripped.startswith("} catch")):
            rows.append(f"{rel}:{i}")
out.write_text("\n".join(rows) + "\n")
print(f"found {len(rows)} catch sites")
PY

missing=0
while IFS= read -r site; do
  [[ -z "$site" ]] && continue
  file="${site%:*}"
  line="${site##*:}"
  if ! grep -q "| \`${file}\` | ${line} |" "$AUDIT"; then
    echo "missing from audit: $site"
    missing=1
  fi
done < "$tmp"

if grep -E '\| pending \|' "$AUDIT" >/dev/null; then
  echo "audit still contains pending rows"
  missing=1
fi

if grep -E '\| see classification \|' "$AUDIT" >/dev/null; then
  echo "audit still contains placeholder classification cells"
  missing=1
fi

if grep -E '\| Handled in the logging pass\. \|' "$AUDIT" >/dev/null; then
  echo "audit still contains generic migration notes"
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
echo "verify-catch-audit: ok"
