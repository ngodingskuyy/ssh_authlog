#!/bin/bash
set -euo pipefail

# Build a clean zip for GitHub Releases.
# Output: dist/ssh_authlog-v<version>.zip

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

REF="HEAD"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      REF="${2:-}";
      if [ -z "$REF" ]; then
        echo "--ref requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --ref=*)
      REF="${1#*=}"
      if [ -z "$REF" ]; then
        echo "--ref requires a value" >&2
        exit 2
      fi
      shift 1
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

INFO_JSON="info.json"
INFO_PAYLOAD=""

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  INFO_PAYLOAD="$(git show "${REF}:${INFO_JSON}" 2>/dev/null || true)"
fi

if [ -z "${INFO_PAYLOAD//[$'\t\r\n ']/}" ]; then
  if [ ! -f "$INFO_JSON" ]; then
    echo "info.json not found" >&2
    exit 1
  fi
  INFO_PAYLOAD="$(cat "$INFO_JSON")"
fi

NAME="$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(str(data.get("name","ssh_authlog")).strip())' <<<"$INFO_PAYLOAD")"

VERSION="$(python3 -c 'import json,sys; data=json.loads(sys.stdin.read()); print(str(data.get("versions","")).strip())' <<<"$INFO_PAYLOAD")"

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
  git archive --format=zip --output "$OUT_FILE" --prefix "${NAME}/" "$REF"
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
    -x "./make_release.sh" \
    -x "./release.sh"
fi

echo "$OUT_FILE"
