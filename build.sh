#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# OS Detection
if [[ "$(uname -s)" == "Darwin" ]]; then
  BUILD_IN_DOCKER=true
else
  BUILD_IN_DOCKER=false
fi

# Pre-requisites validation
if [[ "$BUILD_IN_DOCKER" == true ]]; then
  # macOS (Docker)
  command -v docker >/dev/null || { echo "Missing Docker. Install: brew install --cask docker"; exit 1; }
  docker info >/dev/null 2>&1 || { echo "Docker daemon not running. Please start Docker Desktop."; exit 1; }
else
  # Linux (native)
  [[ $EUID -eq 0 ]] || { echo "Run as root: sudo ./build.sh"; exit 1; }
  command -v lb >/dev/null || { echo "Missing live-build. Install: apt install live-build"; exit 1; }
fi

mkdir -p output assets

download() {
  local url="$1" dest="$2"
  echo "Downloading $url"
  curl --fail --location --retry 3 --connect-timeout 15 --output "$dest" "$url"
}

rm -f assets/wallpaper.png assets/screensaver.webm assets/screensaver.mp4

download "https://cercifaf.org.pt/kiosk/wallpapers/wallpaper.png" "assets/wallpaper.png"

if curl --fail --location --retry 3 --connect-timeout 15     --output assets/screensaver.webm     "https://cercifaf.org.pt/kiosk/screensaver/screensaver.webm"; then
  rm -f assets/screensaver.mp4
  echo "Using WEBM screensaver."
else
  echo "WEBM unavailable; trying MP4."
  download "https://cercifaf.org.pt/kiosk/screensaver/screensaver.mp4"           "assets/screensaver.mp4"
fi

# Clean previous build artifacts
rm -rf config cache chroot binary bootstrap.log build.log

# Create directories (FIXED: added config/includes.chroot/opt/cercifaf)
mkdir -p config/package-lists config/includes.chroot config/hooks/live config/includes.binary output config/includes.chroot/opt/cercifaf

# Copy assets to chroot
cp assets/wallpaper.png config/includes.chroot/opt/cercifaf/wallpaper.png
if [[ -f assets/screensaver.webm ]]; then
  cp assets/screensaver.webm config/includes.chroot/opt/cercifaf/screensaver.webm
else
  cp assets/screensaver.mp4 config/includes.chroot/opt/cercifaf/screensaver.mp4
fi

# Package list
cat > config/package-lists/cercifaf.list.chroot <<'EOF'
systemd
systemd-sysv
dbus
udev
network-manager
curl
ca-certificates
tzdata
locales
sudo
cage
chromium
chromium-sandbox
plymouth
plymouth-themes
fonts-liberation
fonts-noto
xwayland
swayidle
mpv
mesa-vulkan-drivers
EOF

# Auto config
cat > config/auto/config <<'EOF'
#!/usr/bin/env bash
set -e

lb config \
  --mode debian \
  --distribution trixie \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloaders grub-efi,grub-pc \
  --debian-installer live \
  --debian-installer-gui true \
  --debian-installer-distribution trixie \
  --archive-areas "main contrib non-free non-free-firmware" \
  --apt-recommends false \
  --apt-secure true \
  --initsystem systemd \
  --memtest none \
  --image-name cercifaf-kiosk-amd64 \
  --iso-application "CERCIFAF Kiosk" \
  --iso-publisher "CERCIFAF" \
  --iso-volume "CERCIFAF-KIOSK" \
  --source false \
  --updates true
EOF
chmod +x config/auto/config

# REMOVED: cp config/auto/config /tmp/cercifaf-auto-config (unnecessary backup)

# Getty autologin
mkdir -p config/includes.chroot/etc/systemd/system/getty@tty1.service.d
cat > config/includes.chroot/etc/systemd/system/getty@tty1.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kiosk --noclear %I $TERM
Type=idle
EOF

# Kiosk user home
mkdir -p config/includes.chroot/home/kiosk
cat > config/includes.chroot/home/kiosk/.bash_profile <<'EOF'
#!/bin/sh
if [ "$(tty)" = "/dev/tty1" ]; then
    exec /usr/local/bin/cercifaf-kiosk-session
fi
EOF

# Kiosk session
cat > config/includes.chroot/usr/local/bin/cercifaf-kiosk-session <<'EOF'
#!/bin/sh
set -eu

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

exec /usr/bin/cage -d -- /usr/local/bin/cercifaf-browser
EOF
chmod +x config/includes.chroot/usr/local/bin/cercifaf-kiosk-session

# Browser launcher
cat > config/includes.chroot/usr/local/bin/cercifaf-browser <<'EOF'
#!/bin/sh
set -eu

URL="https://cercifaf.org.pt/"
PROFILE="/tmp/cercifaf-chromium"

rm -rf "$PROFILE"
mkdir -p "$PROFILE"

exec /usr/bin/chromium   --kiosk   --no-first-run   --no-default-browser-check   --disable-session-crashed-bubble   --disable-infobars   --disable-translate   --disable-features=Translate,MediaRouter   --password-store=basic   --disk-cache-dir=/tmp/cercifaf-chromium-cache   --user-data-dir="$PROFILE"   "$URL"
EOF
chmod +x config/includes.chroot/usr/local/bin/cercifaf-browser

# Systemd services and timers
mkdir -p config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/etc/systemd/system/cercifaf-schedule.service <<'EOF'
[Unit]
Description=CERCIFAF kiosk schedule guard
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cercifaf-schedule-check
EOF

cat > config/includes.chroot/etc/systemd/system/cercifaf-schedule.timer <<'EOF'
[Unit]
Description=CERCIFAF kiosk schedule guard timer

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=5s
Persistent=false

[Install]
WantedBy=timers.target
EOF

cat > config/includes.chroot/usr/local/bin/cercifaf-schedule-check <<'EOF'
#!/bin/sh
set -eu

day="$(date +%u)"
hour="$(date +%H)"
minute="$(date +%M)"
now=$((10#$hour * 60 + 10#$minute))

# Monday-Friday, 09:00 <= time < 17:00.
if [ "$day" -ge 1 ] && [ "$day" -le 5 ] && [ "$now" -ge 540 ] && [ "$now" -lt 1020 ]; then
    exit 0
fi

# Do not shut down during the last second before 17:00 race or while booting
# into the valid window. Outside the schedule, power off.
/usr/bin/systemctl poweroff
EOF
chmod +x config/includes.chroot/usr/local/bin/cercifaf-schedule-check

cat > config/includes.chroot/etc/systemd/system/cercifaf-shutdown.service <<'EOF'
[Unit]
Description=Shutdown CERCIFAF kiosk at 17:00

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl poweroff
EOF

cat > config/includes.chroot/etc/systemd/system/cercifaf-shutdown.timer <<'EOF'
[Unit]
Description=CERCIFAF weekday shutdown timer

[Timer]
OnCalendar=Mon..Fri 17:00:00
Persistent=false
AccuracySec=1s
Unit=cercifaf-shutdown.service

[Install]
WantedBy=timers.target
EOF

# Hook to enable timers (ADDED per plan)
mkdir -p config/hooks/live
cat > config/hooks/live/99-enable-timers.hook.chroot <<'EOF'
#!/bin/bash
set -e
systemctl enable cercifaf-schedule.timer
systemctl enable cercifaf-shutdown.timer
EOF
chmod +x config/hooks/live/99-enable-timers.hook.chroot

# Ensure project-controlled assets are not accidentally omitted.
test -f config/includes.chroot/opt/cercifaf/wallpaper.png

# Build phase
if [[ "$BUILD_IN_DOCKER" == true ]]; then
  # macOS (Docker)
  echo "Starting live-build in Docker (linux/amd64)..."
  docker run --rm \
    --name cercifaf-kiosk-build \
    --privileged \
    --platform linux/amd64 \
    -v "${PROJECT_DIR}:/workspace" \
    -w /workspace \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    debian:13-slim \
    bash -c "\
      apt-get update && \
      apt-get install -y --no-install-recommends \
        live-build debootstrap squashfs-tools xorriso \
        grub-pc-bin grub-efi-amd64-bin mtools dosfstools curl && \
      ./config/auto/config && \
      lb build 2>&1 | tee build.log && \
      chown -R ${HOST_UID}:${HOST_GID} /workspace"
else
  # Linux (native)
  echo "Starting live-build (native)..."
  ./config/auto/config
  lb build 2>&1 | tee build.log
fi

# Post-build (same for both)
ISO="$(find . -maxdepth 1 -type f -name 'cercifaf-kiosk-amd64.iso' -print -quit)"
if [[ -z "$ISO" ]]; then
  ISO="$(find . -maxdepth 1 -type f -name '*.iso' -print -quit)"
fi

[[ -n "$ISO" ]] || { echo "ISO not found"; exit 1; }

mkdir -p output
cp -f "$ISO" output/cercifaf-kiosk-amd64.iso
sha256sum output/cercifaf-kiosk-amd64.iso > output/cercifaf-kiosk-amd64.iso.sha256

echo
echo "BUILD OK"
echo "ISO: output/cercifaf-kiosk-amd64.iso"
echo "SHA256: output/cercifaf-kiosk-amd64.iso.sha256"