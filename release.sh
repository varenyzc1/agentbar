#!/usr/bin/env bash
set -euo pipefail

# Create and push a version tag. GitHub Actions does the build, release upload,
# and Homebrew cask update after the tag reaches origin.
#
# Usage:
#   ./release.sh 0.2.0
#   ./release.sh v0.2.0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>  (e.g. 0.2.0 or v0.2.0)"
  exit 64
fi

VERSION="${1#v}"
TAG="v${VERSION}"

if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: $1"
  echo "Expected a semantic version such as 0.2.0 or v0.2.0"
  exit 64
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before releasing."
  git status --short
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists locally."
else
  echo "Creating tag ${TAG}..."
  git tag "$TAG"
fi

echo "Pushing ${TAG} to origin..."
git push origin "$TAG"

echo ""
echo "Release started:"
echo "https://github.com/varenyzc1/agentbar/actions/workflows/release.yml"
