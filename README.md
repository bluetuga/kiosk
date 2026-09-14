# CERCIFAF Kiosk Linux v1.0

Debian 13 (trixie) amd64 kiosk image for CERCIFAF.

## Requirements
- Debian 13 amd64 build host recommended
- root/sudo
- internet access during build
- UEFI/BIOS x86_64 target
- wallpaper and screensaver URLs must be reachable at build time

## Build
```bash
sudo apt update
sudo apt install -y live-build debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools qemu-system-x86
git clone /path/to/this/project cercifaf-kiosk
cd cercifaf-kiosk
sudo ./build.sh
```

Output:
`output/cercifaf-kiosk-amd64.iso`

## Build no macOS

Build the ISO on macOS using Docker Desktop:

```bash
brew install --cask docker
open -a Docker         # aguardar daemon iniciar
./build.sh              # build.sh deteta macOS, usa Docker (sem sudo)
```

## Test
```bash
sudo ./test.sh
```

The ISO contains Debian Installer in `live` mode, so it can boot as a live system and install the same live system to a local disk.

## Important
The build downloads:
- https://cercifaf.org.pt/kiosk/wallpapers/wallpaper.png
- https://cercifaf.org.pt/kiosk/screensaver/screensaver.webm
- fallback: https://cercifaf.org.pt/kiosk/screensaver/screensaver.mp4

The build intentionally fails if the wallpaper cannot be downloaded. For the screensaver, WEBM is preferred and MP4 is accepted as fallback.