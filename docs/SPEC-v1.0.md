# CERCIFAF Kiosk Linux — Technical Specification v1.0

## Target
- Debian 13 Trixie
- amd64
- UEFI + legacy BIOS boot media
- USB bootable ISO
- Debian Installer live mode
- Wayland + Cage
- Chromium kiosk
- Europe/Lisbon

## Site
https://cercifaf.org.pt/

## Schedule
Monday-Friday:
- 09:00 start window
- 17:00 poweroff

Saturday/Sunday:
- powered off

A hardware RTC/UEFI wake schedule is required for a machine that is physically powered off. Linux only handles the shutdown and out-of-hours guard.

## Visual
- Plymouth uses the CERCIFAF wallpaper.
- Wallpaper is downloaded at build time and stored locally.
- Chromium runs fullscreen.
- Browser profile is temporary.

## Screensaver
Target timeout: 5 minutes.
Preferred asset: WEBM.
Fallback: MP4.

Idle detection is implemented with `swayidle`. After 5 minutes, Chromium is stopped and `mpv` plays the local video fullscreen in loop. On user activity, mpv is stopped and Chromium is relaunched at the CERCIFAF URL. This intentionally creates a fresh browser session after the screensaver.

## Installation
The ISO includes Debian Installer with `--debian-installer live`, which installs the live system itself to disk. This is the supported live-build mechanism for an installable live system.

## Recovery
- tty1 autologin as `kiosk`
- Cage launches Chromium
- Chromium profile is recreated at session start
- systemd schedule guard powers off outside the valid window
- weekday timer powers off at 17:00

## Security boundary
This is a public web kiosk, not a secure browsing appliance. The user can navigate arbitrary websites. Browser isolation and profile reset are used to avoid persistent user data.
