#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.1.0"
  exit 64
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_FILE="$ROOT_DIR/Casks/agentbar.rb"
URL="https://github.com/varenyzc1/agentbar/releases/download/v${VERSION}/AgentBar-macos.zip"

SHA256="$(curl -fL "$URL" | shasum -a 256 | awk '{print $1}')" || {
  echo "Error: failed to download $URL" >&2
  exit 1
}

perl -0pi -e "s/version \"[^\"]+\"/version \"${VERSION}\"/" "$CASK_FILE"
perl -0pi -e "s/sha256 (?::no_check|\"[0-9a-f]{64}\")/sha256 \"${SHA256}\"/" "$CASK_FILE"

echo "Updated $CASK_FILE"
echo "version: $VERSION"
echo "sha256:  $SHA256"
