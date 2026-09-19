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
mkdir -p config/package-lists config/includes.chroot config/hooks/live config/includes.binary output config/includes.chroot/opt/cercifaf config/auto config/includes.chroot/usr/local/bin config/includes.chroot/home/kiosk config/includes.chroot/etc/systemd/system/getty@tty1.service.d config/includes.chroot/etc/systemd/system config/hooks/live config/hooks/chroot config/hooks/binary config/includes.chroot/etc/plymouth/themes/cercifaf

# Verify critical directories exist
for d in config/auto config/package-lists config/includes.chroot; do
  [[ -d "$d" ]] || { echo "ERRO: diretório $d não foi criado"; exit 1; }
done

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
  --bootloader syslinux \
  --debian-installer false \
  --archive-areas "main contrib non-free non-free-firmware" \
  --apt-recommends false \
  --apt-secure true \
  --initsystem systemd \
  --memtest none \
  --source false \
  --mirror-bootstrap http://deb.debian.org/debian \
  --mirror-binary http://deb.debian.org/debian \
  --mirror-chroot http://deb.debian.org/debian \
  --security false \
  --apt-indices false \
  --firmware-chroot false \
  --firmware-binary false \
  --linux-packages linux-image
EOF
chmod +x config/auto/config

# Hook to fix security repository in sources.list (Debian 13 uses debian-security suite)
mkdir -p config/hooks/chroot
cat > config/hooks/chroot/99-fix-security-repo.hook.chroot <<'EOF'
#!/bin/bash
set -e
# Replace old security repo with correct Debian 13 security repo
sed -i 's|http://security.debian.org trixie/updates|http://security.debian.org/debian-security trixie-security|g' /etc/apt/sources.list
sed -i 's|http://security.debian.org/debian-security trixie/updates|http://security.debian.org/debian-security trixie-security|g' /etc/apt/sources.list
apt-get update
EOF
chmod +x config/hooks/chroot/99-fix-security-repo.hook.chroot

# Hook to set up syslinux files during chroot phase (runs in both native and Docker)
# This ensures isolinux.bin and modules are available for binary_syslinux later
# Debian 13 (trixie) syslinux 6.x: mbr.bin in /usr/lib/SYSLINUX/, ldlinux.c32 in modules/bios/
mkdir -p config/hooks/chroot
cat > config/hooks/chroot/99-setup-syslinux.hook.chroot <<'EOF'
#!/bin/bash
set -e
echo "Setting up syslinux files in chroot..."
mkdir -p /usr/lib/syslinux
# Create /root/isolinux symlink to /usr/lib/syslinux where live-build looks
ln -sf /usr/lib/syslinux /root/isolinux

# syslinux 6.x (Debian 13): use mbr.bin as isolinux.bin (hybrid MBR)
if [ -f "/usr/lib/SYSLINUX/mbr.bin" ] && [ ! -f "/usr/lib/syslinux/isolinux.bin" ]; then
    cp /usr/lib/SYSLINUX/mbr.bin /usr/lib/syslinux/isolinux.bin
    echo "Copied /usr/lib/SYSLINUX/mbr.bin -> /usr/lib/syslinux/isolinux.bin"
fi

# syslinux 6.x: use ldlinux.c32 as ldlinux.sys
if [ -f "/usr/lib/syslinux/modules/bios/ldlinux.c32" ] && [ ! -f "/usr/lib/syslinux/ldlinux.sys" ]; then
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /usr/lib/syslinux/ldlinux.sys
    echo "Copied ldlinux.c32 -> /usr/lib/syslinux/ldlinux.sys"
fi

# Copy COM32 modules from installed packages to where live-build expects them
for f in vesamenu.c32 libcom32.c32 libutil.c32 menu.c32; do
  if [ ! -f "/usr/lib/syslinux/$f" ]; then
    for src in /usr/share/syslinux/$f /usr/lib/ISOLINUX/$f /usr/lib/syslinux/modules/bios/$f /usr/lib/syslinux/bios/$f; do
      if [ -f "$src" ]; then
        cp "$src" /usr/lib/syslinux/
        break
      fi
    done
  fi
done
echo "Syslinux files setup complete"
ls -la /usr/lib/syslinux/
ls -la /root/isolinux/
EOF
chmod +x config/hooks/chroot/99-setup-syslinux.hook.chroot

# Binary hook to ensure syslinux files are in place for binary_syslinux stage
# This runs during the binary phase, before iso creation
# Debian 13 (trixie) syslinux 6.x: mbr.bin in /usr/lib/SYSLINUX/, ldlinux.c32 in modules/bios/
mkdir -p config/hooks/binary
cat > config/hooks/binary/99-ensure-syslinux.hook.binary <<'EOF'
#!/bin/bash
set -e
echo "Ensuring syslinux files for binary stage..."
mkdir -p /usr/lib/syslinux
ln -sf /usr/lib/syslinux /root/isolinux

# syslinux 6.x (Debian 13): use mbr.bin as isolinux.bin (hybrid MBR)
if [ -f "/usr/lib/SYSLINUX/mbr.bin" ] && [ ! -f "/usr/lib/syslinux/isolinux.bin" ]; then
    cp /usr/lib/SYSLINUX/mbr.bin /usr/lib/syslinux/isolinux.bin
    echo "Copied /usr/lib/SYSLINUX/mbr.bin -> /usr/lib/syslinux/isolinux.bin"
fi

# syslinux 6.x: use ldlinux.c32 as ldlinux.sys
if [ -f "/usr/lib/syslinux/modules/bios/ldlinux.c32" ] && [ ! -f "/usr/lib/syslinux/ldlinux.sys" ]; then
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /usr/lib/syslinux/ldlinux.sys
    echo "Copied ldlinux.c32 -> /usr/lib/syslinux/ldlinux.sys"
fi

for f in isolinux.bin vesamenu.c32 libcom32.c32 libutil.c32 menu.c32; do
  if [ ! -f "/usr/lib/syslinux/$f" ]; then
    for src in /usr/share/syslinux/$f /usr/lib/ISOLINUX/$f /usr/lib/syslinux/modules/bios/$f /usr/lib/syslinux/bios/$f; do
      if [ -f "$src" ]; then
        cp "$src" /usr/lib/syslinux/
        break
      fi
    done
  fi
done
ls -la /usr/lib/syslinux/
ls -la /root/isolinux/
EOF
chmod +x config/hooks/binary/99-ensure-syslinux.hook.binary

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

# Start swayidle for screensaver management
exec /usr/local/bin/cercifaf-screensaver-manager
EOF
chmod +x config/includes.chroot/usr/local/bin/cercifaf-kiosk-session

# Screensaver manager - manages swayidle + mpv for screensaver
cat > config/includes.chroot/usr/local/bin/cercifaf-screensaver-manager <<'EOF'
#!/bin/sh
set -eu

SCREENSAVER_WEBM="/opt/cercifaf/screensaver.webm"
SCREENSAVER_MP4="/opt/cercifaf/screensaver.mp4"
URL="https://cercifaf.org.pt/"

# Find screensaver file
if [ -f "$SCREENSAVER_WEBM" ]; then
    SCREENSAVER_FILE="$SCREENSAVER_WEBM"
elif [ -f "$SCREENSAVER_MP4" ]; then
    SCREENSAVER_FILE="$SCREENSAVER_MP4"
else
    echo "No screensaver file found, disabling screensaver"
    SCREENSAVER_FILE=""
fi

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Function to launch browser
launch_browser() {
    PROFILE="/tmp/cercifaf-chromium-$$"
    rm -rf "$PROFILE"
    mkdir -p "$PROFILE"
    exec /usr/bin/chromium \
        --kiosk \
        --no-first-run \
        --no-default-browser-check \
        --disable-session-crashed-bubble \
        --disable-infobars \
        --disable-translate \
        --disable-features=Translate,MediaRouter \
        --password-store=basic \
        --disk-cache-dir=/tmp/cercifaf-chromium-cache \
        --user-data-dir="$PROFILE" \
        "$URL"
}

# Function to launch screensaver (mpv loop)
launch_screensaver() {
    if [ -n "$SCREENSAVER_FILE" ]; then
        exec /usr/bin/mpv --loop=inf --fullscreen --no-input-default-bindings --no-osc --no-terminal "$SCREENSAVER_FILE"
    fi
}

# Start swayidle to manage idle detection
# After 300s (5 min): stop chromium, start mpv
# On activity: stop mpv, restart chromium
if [ -n "$SCREENSAVER_FILE" ]; then
    /usr/bin/swayidle -w \
        timeout 300 '/usr/local/bin/cercifaf-screensaver-activate' \
        resume '/usr/local/bin/cercifaf-screensaver-deactivate' \
        before-sleep '/usr/local/bin/cercifaf-screensaver-activate' &
    SWAYIDLE_PID=$!
fi

# Launch initial browser
launch_browser

# If swayidle was started, wait for it (should not return unless error)
if [ -n "${SWAYIDLE_PID:-}" ]; then
    wait $SWAYIDLE_PID
fi
EOF
chmod +x config/includes.chroot/usr/local/bin/cercifaf-screensaver-manager

# Screensaver activate - called by swayidle on idle timeout
cat > config/includes.chroot/usr/local/bin/cercifaf-screensaver-activate <<'EOF'
#!/bin/sh
set -eu

# Kill chromium to free resources
pkill -f "chromium.*--kiosk" 2>/dev/null || true

# Start mpv screensaver
SCREENSAVER_WEBM="/opt/cercifaf/screensaver.webm"
SCREENSAVER_MP4="/opt/cercifaf/screensaver.mp4"

if [ -f "$SCREENSAVER_WEBM" ]; then
    SCREENSAVER_FILE="$SCREENSAVER_WEBM"
elif [ -f "$SCREENSAVER_MP4" ]; then
    SCREENSAVER_FILE="$SCREENSAVER_MP4"
else
    exit 0
fi

# Launch mpv in background, store PID
/usr/bin/mpv --loop=inf --fullscreen --no-input-default-bindings --no-osc --no-terminal "$SCREENSAVER_FILE" &
echo $! > /tmp/cercifaf-mpv.pid
EOF
chmod +x config/includes.chroot/usr/local/bin/cercifaf-screensaver-activate

# Screensaver deactivate - called by swayidle on activity resume
cat > config/includes.chroot/usr/local/bin/cercifaf-screensaver-deactivate <<'EOF'
#!/bin/sh
set -eu

# Kill mpv screensaver
if [ -f /tmp/cercifaf-mpv.pid ]; then
    kill "$(cat /tmp/cercifaf-mpv.pid)" 2>/dev/null || true
    rm -f /tmp/cercifaf-mpv.pid
fi
pkill -f "mpv.*--loop=inf" 2>/dev/null || true

# Relaunch chromium (fresh session)
/usr/local/bin/cercifaf-kiosk-session &
EOF
chmod +x config/includes.chroot/usr/local/bin/cercifaf-screensaver-deactivate

# Browser launcher (used by cercifaf-kiosk-session for initial launch)
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

# Hook to clean up .dpkg-new files after chroot package installation
mkdir -p config/hooks/normal
cat > config/hooks/normal/99-clean-dpkg-new.hook.chroot <<'EOF'
#!/bin/bash
set -e
echo "Running 99-clean-dpkg-new hook"
find / -name "*.dpkg-new" -ls 2>/dev/null | head -20
find / -name "*.dpkg-new" -exec rm -f {} \; 2>/dev/null || true
echo "Finished 99-clean-dpkg-new hook"
EOF
chmod +x config/hooks/normal/99-clean-dpkg-new.hook.chroot

# Hook to configure locale and timezone
mkdir -p config/hooks/chroot
cat > config/hooks/chroot/99-locale-timezone.hook.chroot <<'EOF'
#!/bin/bash
set -e
# Set timezone to Europe/Lisbon
ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
echo "Europe/Lisbon" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Set locale to pt_PT.UTF-8
sed -i 's/^# *pt_PT.UTF-8/pt_PT.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=pt_PT.UTF-8 LC_ALL=pt_PT.UTF-8
EOF
chmod +x config/hooks/chroot/99-locale-timezone.hook.chroot

# Plymouth theme for CERCIFAF
mkdir -p config/includes.chroot/etc/plymouth/themes/cercifaf
cat > config/includes.chroot/etc/plymouth/themes/cercifaf/cercifaf.plymouth <<'EOF'
[Plymouth Theme]
Name=CERCIFAF
Description=CERCIFAF Kiosk Theme
ModuleName=script

[script]
ImageDir=/opt/cercifaf
ScriptFile=/opt/cercifaf/cercifaf.script
EOF

cat > config/includes.chroot/opt/cercifaf/cercifaf.script <<'EOF'
# CERCIFAF Plymouth theme script
wallpaper = Image("wallpaper.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

# Scale wallpaper to fill screen maintaining aspect ratio
img_width = wallpaper.GetWidth();
img_height = wallpaper.GetHeight();

if (img_width / screen_width > img_height / screen_height) {
    scale = screen_width / img_width;
} else {
    scale = screen_height / img_height;
}

new_width = img_width * scale;
new_height = img_height * scale;

wallpaper_scaled = wallpaper.Scale(new_width, new_height);

x = (screen_width - new_width) / 2;
y = (screen_height - new_height) / 2;

sprite = Sprite();
sprite.SetImage(wallpaper_scaled);
sprite.SetPosition(x, y, -100);
EOF

# Set plymouth theme to cercifaf
mkdir -p config/includes.chroot/etc/plymouth
cat > config/includes.chroot/etc/plymouth/plymouthd.conf <<'EOF'
[Daemon]
Theme=cercifaf
ShowDelay=0
EOF

# Ensure project-controlled assets are not accidentally omitted.
test -f config/includes.chroot/opt/cercifaf/wallpaper.png

# Create dummy Contents-amd64.gz in live-build cache BEFORE lb build
# (lb_chroot_linux-image downloads this to find kernel packages; 404 on trixie)
mkdir -p cache/binary_debian-installer
echo "dummy" | gzip > cache/binary_debian-installer/Contents-amd64.gz

# Build phase
if [[ "$BUILD_IN_DOCKER" == true ]]; then
  # macOS (Docker) — usa --platform linux/amd64 para cross-compile via QEMU do Docker Desktop
  echo "Starting live-build in Docker (linux/amd64 via --platform)..."
  docker run --rm \
    --name cercifaf-kiosk-build \
    --privileged \
    --platform linux/amd64 \
    -v "${PROJECT_DIR}:/workspace" \
    -w /workspace \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -e DEBIAN_FRONTEND=noninteractive \
    debian:13-slim \
    bash -c '
      set -x
      apt-get update

      # Install ONLY syslinux-common via apt (provides COM32 modules)
      # syslinux and syslinux-utils have problematic postinst - extract manually
      apt-get install -y --no-install-recommends syslinux-common

      # Extract needed files from syslinux .deb and syslinux-utils .deb manually
      mkdir -p /tmp/syslinux-extract
      cd /tmp/syslinux-extract

      # Extract mbr.bin from syslinux .deb
      apt-get download syslinux
      dpkg-deb -x syslinux_*.deb .
      if [ -f "usr/lib/SYSLINUX/mbr.bin" ]; then
          cp usr/lib/SYSLINUX/mbr.bin /usr/lib/SYSLINUX/mbr.bin
          echo "Extracted mbr.bin from syslinux deb"
      fi

      # Extract isohybrid from syslinux-utils .deb
      apt-get download syslinux-utils
      dpkg-deb -x syslinux-utils_*.deb .
      if [ -f "usr/bin/isohybrid" ]; then
          cp usr/bin/isohybrid /usr/bin/isohybrid
          chmod +x /usr/bin/isohybrid
          echo "Extracted isohybrid from syslinux-utils deb"
      fi

      cd /workspace

      # Set up syslinux files for live-build binary stage
      mkdir -p /usr/lib/syslinux
      ln -sf /usr/lib/syslinux /root/isolinux

      # Copy modules from syslinux-common (already installed)
      # syslinux 6.x (Debian 13): modules are in /usr/lib/syslinux/modules/bios/
      for f in vesamenu.c32 libcom32.c32 libutil.c32 menu.c32 ldlinux.c32; do
          if [ -f "/usr/lib/syslinux/modules/bios/$f" ]; then
              cp "/usr/lib/syslinux/modules/bios/$f" /usr/lib/syslinux/
              echo "Copied $f to /usr/lib/syslinux/"
          fi
      done
      # Use mbr.bin as isolinux.bin (hybrid MBR)
      if [ -f "/usr/lib/SYSLINUX/mbr.bin" ]; then
          cp /usr/lib/SYSLINUX/mbr.bin /usr/lib/syslinux/isolinux.bin
          cp /usr/lib/SYSLINUX/mbr.bin /root/isolinux/isolinux.bin
          echo "Copied mbr.bin as isolinux.bin"
      fi
      # Use ldlinux.c32 as ldlinux.sys
      if [ -f "/usr/lib/syslinux/modules/bios/ldlinux.c32" ]; then
          cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /usr/lib/syslinux/ldlinux.sys
          cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /root/isolinux/ldlinux.sys
          echo "Copied ldlinux.c32 as ldlinux.sys"
      fi

      # Verify isohybrid is available
      which isohybrid || (echo "isohybrid not found!" && exit 1)
      isohybrid --version

      # Now install remaining packages
      apt-get install -y --no-install-recommends \
        live-build debootstrap squashfs-tools xorriso \
        mtools dosfstools \
        curl python3 binutils xz-utils qemu-user-static

      # Force dpkg overwrite for chroot stage (fixes QEMU permission issues)
      mkdir -p /etc/dpkg/dpkg.cfg.d
      echo "force-overwrite" > /etc/dpkg/dpkg.cfg.d/force-overwrite

      # Patch debootstrap ANTES de qualquer bootstrap:
      # 1. extract_dpkg_deb_data com --overwrite (evita falha em symlinks quebrados no first-stage)
      # 2. debian-common para corrigir libpam-runtime symlink e libsystemd-shared dir ANTES do unpack
      ./patch-debootstrap-tar.sh

      ./config/auto/config
      echo "Running lb build..."
      lb build --verbose
      echo "lb build exit code: $?"

      # Clean up .dpkg-new files before chown to avoid permission issues
      echo "Cleaning up .dpkg-new files..."
      find /workspace -name "*.dpkg-new" -ls 2>/dev/null | head -20
      find /workspace -name "*.dpkg-new" -exec rm -f {} \; 2>/dev/null || true
      find /workspace -name "*.dpkg-new" -ls 2>/dev/null | head -20

      # Skip chown if it fails due to .dpkg-new permission issues
      echo "Running chown..."
      chown -R ${HOST_UID}:${HOST_GID} /workspace 2>/dev/null || echo "Warning: chown failed, files remain owned by root"
      echo "chown done"
    ' || true
else
  # Linux (native) - syslinux files set up by chroot hook during lb build
  echo "Starting live-build (native)..."
  # Verify isohybrid is available (needed for iso-hybrid binary stage)
  which isohybrid || (echo "isohybrid not found! Install syslinux-utils" && exit 1)
  isohybrid --version
  ./config/auto/config
  ./patch-debootstrap-tar.sh
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