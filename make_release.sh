#!/bin/bash
set -euo pipefail

# Build a clean zip for GitHub Releases.
# Output: dist/ssh_authlog-v<version>.zip

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

if [ ! -f "info.json" ]; then
  echo "info.json not found" >&2
  exit 1
fi

NAME="$(python3 - <<'PY'
import json
with open('info.json','r',encoding='utf-8') as f:
  data=json.load(f)
print(str(data.get('name','ssh_authlog')).strip())
PY
)"
VERSION="$(python3 - <<'PY'
import json
with open('info.json','r',encoding='utf-8') as f:
    data=json.load(f)
print(str(data.get('versions','')).strip())
PY
)"

if [ -z "$VERSION" ]; then
  echo "Could not read versions from info.json" >&2
  exit 1
fi

OUT_DIR="dist"
OUT_FILE="$OUT_DIR/${NAME}-v${VERSION}.zip"

mkdir -p "$OUT_DIR"
rm -f "$OUT_FILE"

# Prefer git archive if available (ensures no untracked files get in)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git archive --format=zip --output "$OUT_FILE" --prefix "${NAME}/" HEAD
else
  # Fallback: zip current folder excluding common junk
  if ! command -v zip >/dev/null 2>&1; then
    echo "zip command not found" >&2
    exit 1
  fi
  zip -r "$OUT_FILE" . \
    -x "./.git/*" \
    -x "./__pycache__/*" \
    -x "./dist/*" \
    -x "./*.pyc" \
    -x "./.pytest_cache/*" \
    -x "./.venv/*" \
    -x "./make_release.sh"
fi

echo "$OUT_FILE"
