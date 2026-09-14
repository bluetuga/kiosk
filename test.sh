#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

ROOT="$(pwd)"
ISO="$ROOT/output/cercifaf-kiosk-amd64.iso"

[[ -f "$ISO" ]] || { echo "ISO not found: $ISO"; exit 1; }

if [[ "$(uname -s)" == "Darwin" ]]; then
  # macOS: use QEMU from Homebrew, without KVM (Apple Silicon)
  command -v qemu-system-x86_64 >/dev/null || {
    echo "Install qemu via Homebrew: brew install qemu"
    exit 1
  }
  exec qemu-system-x86_64 \
    -m 4096 \
    -smp 2 \
    -cdrom "$ISO" \
    -boot d
else
  # Linux (native): use KVM if available
  command -v qemu-system-x86_64 >/dev/null || {
    echo "Install qemu-system-x86: apt install qemu-system-x86"
    exit 1
  }
  exec qemu-system-x86_64 \
    -enable-kvm \
    -m 4096 \
    -smp 2 \
    -cdrom "$ISO" \
    -boot d
fi