#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# OS Detection
if [[ "$(uname -s)" == "Darwin" ]]; then
  # macOS: skip lb clean --purge (not available in host)
  rm -rf output cache chroot binary config/bootstrap config/build config/chroot
else
  # Linux (native): keep original behavior
  [[ $EUID -eq 0 ]] || { echo "Run as root: sudo ./clean.sh"; exit 1; }
  lb clean --purge || true
  rm -rf output cache chroot binary
fi