#!/bin/bash
set -euo pipefail

# One-click: build zip + create tag + push tag + create GitHub Release (via gh CLI)
#
# Usage:
#   ./release.sh            # tag + push + release
#   ./release.sh --dry-run  # show what would happen
#   ./release.sh --force    # overwrite existing tag/release (dangerous)

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

DRY_RUN=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    *)
      echo "Unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: $ROOT_DIR" >&2
  exit 1
fi

if [ -n "$(git status --porcelain=v1)" ]; then
  echo "Working tree not clean. Commit your changes before releasing." >&2
  git status --porcelain=v1 >&2
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

TAG="v${VERSION}"
ZIP_PATH="$(./make_release.sh)"

# Create annotated tag (local)
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  if [ "$FORCE" -eq 1 ]; then
    [ "$DRY_RUN" -eq 1 ] || git tag -d "$TAG" >/dev/null
  else
    echo "Tag already exists: $TAG (use --force to overwrite)" >&2
    exit 1
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN"
  echo "- Would tag: $TAG"
  echo "- Would build: $ZIP_PATH"
  echo "- Would push tag to origin"
  echo "- Would create GitHub release and upload zip"
  exit 0
fi

git tag -a "$TAG" -m "Release $TAG"

# Push tag
if [ "$FORCE" -eq 1 ]; then
  git push origin ":refs/tags/$TAG" >/dev/null 2>&1 || true
  git push --force origin "$TAG"
else
  git push origin "$TAG"
fi

# Create GitHub release + upload asset
if ! command -v gh >/dev/null 2>&1; then
  echo "Built $ZIP_PATH and pushed tag $TAG. Install gh to auto-create a GitHub Release." >&2
  exit 0
fi

# Make sure gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
  echo "Built $ZIP_PATH and pushed tag $TAG. Run: gh auth login" >&2
  exit 0
fi

# If release exists, handle --force
if gh release view "$TAG" >/dev/null 2>&1; then
  if [ "$FORCE" -eq 1 ]; then
    gh release delete "$TAG" -y || true
  else
    echo "GitHub Release already exists: $TAG (use --force to overwrite)" >&2
    exit 1
  fi
fi

# Use generate-notes to avoid hand-writing changelog
# Title includes plugin name for readability.
gh release create "$TAG" "$ZIP_PATH" \
  --title "${NAME} ${TAG}" \
  --generate-notes

echo "Release created: $TAG"
