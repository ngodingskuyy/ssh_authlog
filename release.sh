#!/bin/bash
set -euo pipefail

# One-click: build zip + create tag + push tag + create GitHub Release (via gh CLI)
#
# Usage:
#   ./release.sh            # tag + push + release
#   ./release.sh --dry-run  # show what would happen
#   ./release.sh --force    # overwrite existing tag/release (dangerous)
 #   ./release.sh --ref main # release based on a ref (default: main)

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

DRY_RUN=0
FORCE=0
REF="main"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --ref)
      echo "Use: --ref=<git-ref>" >&2
      exit 2
      ;;
    --ref=*)
      REF="${arg#*=}"
      if [ -z "$REF" ]; then
        echo "--ref requires a value" >&2
        exit 2
      fi
      ;;
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
  echo "Working tree not clean. Commit/stash changes before releasing." >&2
  git status --porcelain=v1 >&2
  exit 1
fi

if ! git rev-parse -q --verify "$REF" >/dev/null 2>&1; then
  echo "Invalid ref: $REF" >&2
  exit 1
fi

INFO_PAYLOAD="$(git show "${REF}:info.json" 2>/dev/null || true)"
if [ -z "$INFO_PAYLOAD" ]; then
  echo "Could not read info.json from ref: $REF" >&2
  exit 1
fi

NAME="$(python3 - <<'PY'
import json,sys
data=json.loads(sys.stdin.read())
print(str(data.get('name','ssh_authlog')).strip())
PY
<<<"$INFO_PAYLOAD"
)"

VERSION="$(python3 - <<'PY'
import json,sys
data=json.loads(sys.stdin.read())
print(str(data.get('versions','')).strip())
PY
<<<"$INFO_PAYLOAD"
)"

if [ -z "$VERSION" ]; then
  echo "Could not read versions from info.json" >&2
  exit 1
fi

TAG="v${VERSION}"
ZIP_PATH="$(./make_release.sh --ref "$REF")"

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
  echo "- Would target ref: $REF"
  echo "- Would push tag to origin"
  echo "- Would create GitHub release and upload zip"
  exit 0
fi

git tag -a "$TAG" -m "Release $TAG" "$REF"

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
  --target "$REF" \
  --generate-notes

echo "Release created: $TAG"
