#!/bin/bash
set -e

# Patch debootstrap functions to add --overwrite and partial/ fallback AND pre-create directories for each package
python3 << 'PYEOF'
import re

with open("/usr/share/debootstrap/functions", "r") as f:
    content = f.read()

pattern = r'extract_dpkg_deb_data\s*\(\)\s*\{[^}]+\}'
replacement = '''extract_dpkg_deb_data () {
\tlocal pkg="$1"
\tif [ ! -f "$pkg" ] && [ -f "${pkg%/*}/partial/${pkg##*/}" ]; then
\t\tpkg="${pkg%/*}/partial/${pkg##*/}"
\tfi
\t# Pre-create all directories from the package to avoid QEMU permission issues
\tfor dir in $(dpkg-deb -c "$pkg" | awk '/^d/ {print $NF}' | sed 's|/$||'); do
\t\tmkdir -p "$TARGET/$dir"
\tdone
\tdpkg-deb --fsys-tarfile "$pkg" | tar --overwrite -xf - || error 1 FILEEXIST "Tried to extract package, but tar failed. Exit..."
}'''
content = re.sub(pattern, replacement, content)

with open("/usr/share/debootstrap/functions", "w") as f:
    f.write(content)

print("Patched extract_dpkg_deb_data with --overwrite, partial/ fallback, and directory pre-creation")
PYEOF

# Patch debian-common script to fix libpam-runtime symlink issue before unpack phase
python3 << 'PYEOF'
import re

with open("/usr/share/debootstrap/scripts/debian-common", "r") as f:
    content = f.read()

# Fix 1: libpam-runtime symlink issue before unpack required packages
pattern1 = r'(info UNPACKREQ "Unpacking required packages\.\.\.")'
replacement1 = r'''# Fix libpam-runtime broken symlink issue (pam.7.gz -> PAM.7.gz)
\trm -f "$TARGET/usr/share/man/man7/pam.7.gz"
\ttouch "$TARGET/usr/share/man/man7/PAM.7.gz"
\1'''
content = re.sub(pattern1, replacement1, content)

# Fix 2: Create core directories before base system unpack (avoids QEMU permission issues)
pattern2 = r'(info UNPACKBASE "Unpacking the base system\.\.\.")'
replacement2 = r'''# Fix: pre-create core directories that dpkg may fail to create under QEMU on Apple Silicon
\ttouch /test_unpackbase_reached
\tmkdir -p "$TARGET/usr/share/doc"
\tmkdir -p "$TARGET/usr/share/doc/libsystemd-shared"
\tmkdir -p "$TARGET/usr/share/doc/libapparmor1"
\tmkdir -p "$TARGET/usr/share/doc/libext2fs2t64"
\tmkdir -p "$TARGET/usr/share/doc/libss2"
\tmkdir -p "$TARGET/usr/share/doc/dctrl-tools"
\tmkdir -p "$TARGET/etc/binfmt.d"
\tmkdir -p "$TARGET/usr/share/man/man7"
\tmkdir -p "$TARGET/etc"
\tmkdir -p "$TARGET/etc/ssl"
\tmkdir -p "$TARGET/etc/ca-certificates"
\tmkdir -p "$TARGET/usr/lib/x86_64-linux-gnu/systemd"
\tmkdir -p "$TARGET/etc/credstore"
\tmkdir -p "$TARGET/etc/credstore.encrypted"
\tmkdir -p "$TARGET/etc/kernel/install.d"
\tmkdir -p "$TARGET/etc/modules-load.d"
\tmkdir -p "$TARGET/etc/ssh"
\tmkdir -p "$TARGET/etc/ssh/ssh_config.d"
\tmkdir -p "$TARGET/etc/systemd"
\tmkdir -p "$TARGET/etc/systemd/network"
\tmkdir -p "$TARGET/etc/systemd/system"
\tmkdir -p "$TARGET/etc/systemd/user"
\tmkdir -p "$TARGET/etc/systemd/journald.conf.d"
\tmkdir -p "$TARGET/etc/systemd/logind.conf.d"
\tmkdir -p "$TARGET/etc/systemd/sleep.conf.d"
\tmkdir -p "$TARGET/etc/systemd/resolved.conf.d"
\tmkdir -p "$TARGET/etc/systemd/timesyncd.conf.d"
\tmkdir -p "$TARGET/etc/systemd/coredump.conf.d"
\tmkdir -p "$TARGET/etc/systemd/oomd.conf.d"
\tmkdir -p "$TARGET/etc/tmpfiles.d"
\tmkdir -p "$TARGET/etc/sysctl.d"
\tmkdir -p "$TARGET/etc/modprobe.d"
\tmkdir -p "$TARGET/etc/kernel"
\tmkdir -p "$TARGET/etc/kernel/postinst.d"
\tmkdir -p "$TARGET/etc/kernel/postrm.d"
\tmkdir -p "$TARGET/etc/kernel/preinst.d"
\tmkdir -p "$TARGET/etc/kernel/prerm.d"
\tmkdir -p "$TARGET/etc/xdg"
\tmkdir -p "$TARGET/etc/xdg/autostart"
\tmkdir -p "$TARGET/etc/xdg/session"
\tmkdir -p "$TARGET/etc/xdg/systemd"
\tmkdir -p "$TARGET/etc/polkit-1"
\tmkdir -p "$TARGET/etc/polkit-1/rules.d"
\tmkdir -p "$TARGET/etc/dbus-1"
\tmkdir -p "$TARGET/etc/dbus-1/system.d"
\tmkdir -p "$TARGET/etc/dbus-1/session.d"
\tmkdir -p "$TARGET/etc/security"
\tmkdir -p "$TARGET/etc/security/pam.d"
\tmkdir -p "$TARGET/etc/initramfs-tools"
\tmkdir -p "$TARGET/usr/lib/environment.d"
\tmkdir -p "$TARGET/usr/lib/tmpfiles.d"
\tmkdir -p "$TARGET/usr/lib/sysusers.d"
\tmkdir -p "$TARGET/usr/lib/binfmt.d"
\tmkdir -p "$TARGET/usr/lib/sysctl.d"
\tmkdir -p "$TARGET/usr/lib/modules-load.d"
\tmkdir -p "$TARGET/usr/lib/kernel/install.d"
\tmkdir -p "$TARGET/usr/lib/modprobe.d"
\tmkdir -p "$TARGET/usr/lib/systemd"
\tmkdir -p "$TARGET/usr/lib/systemd/system"
\tmkdir -p "$TARGET/usr/lib/systemd/user"
\tmkdir -p "$TARGET/usr/lib/systemd/system-generators"
\tmkdir -p "$TARGET/usr/lib/systemd/user-generators"
\tmkdir -p "$TARGET/usr/lib/systemd/system-sleep"
\tmkdir -p "$TARGET/usr/lib/systemd/scripts"
\tmkdir -p "$TARGET/usr/lib/kernel"
\tmkdir -p "$TARGET/usr/lib/kernel/install.d"
\tmkdir -p "$TARGET/usr/lib/pam.d"
\tmkdir -p "$TARGET/usr/lib/pcrlock.d"
\tmkdir -p "$TARGET/usr/lib/pcrlock.d/400-secureboot-separator.pcrlock.d"
\tmkdir -p "$TARGET/usr/lib/pcrlock.d/500-separator.pcrlock.d"
\tmkdir -p "$TARGET/usr/lib/pcrlock.d/700-action-efi-exit-boot-services.pcrlock.d"
\tmkdir -p "$TARGET/usr/lib/os-release.d"
\tmkdir -p "$TARGET/usr/lib/xdg"
\tmkdir -p "$TARGET/usr/lib/systemd/catalog"
\tmkdir -p "$TARGET/usr/lib/systemd/journald.conf.d"
\tmkdir -p "$TARGET/usr/lib/systemd/network"
\tmkdir -p "$TARGET/usr/lib/systemd/profile.d"
\tmkdir -p "$TARGET/usr/lib/systemd/ssh_config.d"
\tmkdir -p "$TARGET/usr/lib/systemd/system-preset"
\tmkdir -p "$TARGET/usr/lib/systemd/user-environment-generators"
\tmkdir -p "$TARGET/usr/lib/systemd/user.conf.d"
\tmkdir -p "$TARGET/usr/lib/systemd/system.conf.d"
\tmkdir -p "$TARGET/usr/lib/systemd/user-preset"
\tmkdir -p "$TARGET/usr/lib/sysusers.d"
\tmkdir -p "$TARGET/usr/lib/udev"
\tmkdir -p "$TARGET/usr/lib/udev/rules.d"
\tmkdir -p "$TARGET/usr/lib/dbus-1.0"
\tmkdir -p "$TARGET/usr/lib/firmware"
\tmkdir -p "$TARGET/usr/lib/dracut"
\tmkdir -p "$TARGET/usr/lib/klibc"
\tmkdir -p "$TARGET/usr/share/bash-completion/completions"
\tmkdir -p "$TARGET/usr/share/bug/systemd"
\tmkdir -p "$TARGET/usr/share/dbus-1/services"
\tmkdir -p "$TARGET/usr/share/dbus-1/system-services"
\tmkdir -p "$TARGET/usr/share/dbus-1/system.d"
\tmkdir -p "$TARGET/usr/share/doc"
\tmkdir -p "$TARGET/usr/share/doc/systemd"
\tmkdir -p "$TARGET/usr/share/doc/libdbus-1-3"
\tmkdir -p "$TARGET/usr/share/doc/dbus-bin"
\tmkdir -p "$TARGET/usr/share/doc/libexpat1"
\tmkdir -p "$TARGET/usr/share/doc/dbus-daemon"
\tmkdir -p "$TARGET/usr/share/doc/dbus-system-bus-common"
\tmkdir -p "$TARGET/usr/share/doc/linux-base"
\tmkdir -p "$TARGET/usr/share/doc/initramfs-tools-bin"
\tmkdir -p "$TARGET/usr/share/doc/libklibc"
\tmkdir -p "$TARGET/usr/share/lintian/overrides"
\tmkdir -p "$TARGET/usr/share/mime/packages"
\tmkdir -p "$TARGET/usr/share/polkit-1"
\tmkdir -p "$TARGET/usr/share/polkit-1/actions"
\tmkdir -p "$TARGET/usr/share/polkit-1/rules.d"
\tmkdir -p "$TARGET/usr/share/systemd"
\tmkdir -p "$TARGET/usr/share/zsh/vendor-completions"
\tmkdir -p "$TARGET/var/lib/systemd"

\t# Common directories that many packages need
\tmkdir -p "$TARGET/etc/cron.d"
\tmkdir -p "$TARGET/etc/cron.daily"
\tmkdir -p "$TARGET/etc/cron.weekly"
\tmkdir -p "$TARGET/etc/cron.monthly"
\tmkdir -p "$TARGET/etc/cron.hourly"
\tmkdir -p "$TARGET/etc/cron.yearly"
\tmkdir -p "$TARGET/etc/sudoers.d"
\tmkdir -p "$TARGET/etc/logrotate.d"
\tmkdir -p "$TARGET/etc/periodic"
\tmkdir -p "$TARGET/etc/periodic/daily"
\tmkdir -p "$TARGET/etc/periodic/weekly"
\tmkdir -p "$TARGET/etc/periodic/monthly"
\tmkdir -p "$TARGET/etc/init.d"
\tmkdir -p "$TARGET/etc/rc0.d"
\tmkdir -p "$TARGET/etc/rc1.d"
\tmkdir -p "$TARGET/etc/rc2.d"
\tmkdir -p "$TARGET/etc/rc3.d"
\tmkdir -p "$TARGET/etc/rc4.d"
\tmkdir -p "$TARGET/etc/rc5.d"
\tmkdir -p "$TARGET/etc/rc6.d"
\tmkdir -p "$TARGET/etc/rcS.d"
\tmkdir -p "$TARGET/usr/share/info"
\tmkdir -p "$TARGET/usr/share/man/man1"
\tmkdir -p "$TARGET/usr/share/man/man5"
\tmkdir -p "$TARGET/usr/share/man/man8"
\tmkdir -p "$TARGET/var/log"
\tmkdir -p "$TARGET/var/spool/cron"
\tmkdir -p "$TARGET/var/spool/cron/crontabs"
\tmkdir -p "$TARGET/var/lib/dpkg"
\tmkdir -p "$TARGET/var/lib/apt/lists"
\tmkdir -p "$TARGET/var/cache/apt/archives"
\tmkdir -p "$TARGET/var/cache/adduser"

\t# Systemd directories from error logs
\tmkdir -p "$TARGET/usr/lib/systemd/system/getty.target.wants"
\tmkdir -p "$TARGET/usr/lib/systemd/system/user-.slice.d"
\tmkdir -p "$TARGET/usr/lib/systemd/system/user@0.service.d"
\tmkdir -p "$TARGET/usr/lib/systemd/system/timers.target.wants"
\tmkdir -p "$TARGET/usr/lib/systemd/system.conf.d"
\tmkdir -p "$TARGET/usr/lib/systemd/user-preset"
\tmkdir -p "$TARGET/usr/share/doc/systemd"
\tmkdir -p "$TARGET/usr/share/locale/kab"
\tmkdir -p "$TARGET/usr/share/doc/systemd-sysv"
\tmkdir -p "$TARGET/usr/share/doc/adduser"
\tmkdir -p "$TARGET/usr/share/doc/adduser/examples"
\tmkdir -p "$TARGET/usr/share/doc/adduser/examples/adduser.local.conf.examples"
\tmkdir -p "$TARGET/usr/share/doc/adduser/examples/adduser.local.conf.examples/skel"
\tmkdir -p "$TARGET/usr/share/doc/adduser/examples/adduser.local.conf.examples/skel.other"
\tmkdir -p "$TARGET/etc/cron.d"
\tmkdir -p "$TARGET/usr/share/doc/libcom-err2"
\tmkdir -p "$TARGET/usr/share/doc/cron-daemon-common"

\t# Comprehensive systemd directories
\tfor d in \
\t\tsystemd-ask-password-console.service.d \
\t\tsystemd-ask-password-wall.service.d \
\t\tsystemd-binfmt.service.d \
\t\tsystemd-fsck-root.service.d \
\t\tsystemd-fsck@.service.d \
\t\tsystemd-hibernate-resume.service.d \
\t\tsystemd-homed.service.d \
\t\tsystemd-importd.service.d \
\t\tsystemd-journal-flush.service.d \
\t\tsystemd-journald.service.d \
\t\tsystemd-logind.service.d \
\t\tsystemd-machine-id-commit.service.d \
\t\tsystemd-modules-load.service.d \
\t\tsystemd-network-generator.service.d \
\t\tsystemd-networkd-wait-online.service.d \
\t\tsystemd-networkd.service.d \
\t\tsystemd-oomd.service.d \
\t\tsystemd-pstore.service.d \
\t\tsystemd-random-seed.service.d \
\t\tsystemd-remount-fs.service.d \
\t\tsystemd-resolved.service.d \
\t\tsystemd-rfkill.service.d \
\t\tsystemd-sysctl.service.d \
\t\tsystemd-sysusers.service.d \
\t\tsystemd-timesyncd.service.d \
\t\tsystemd-tmpfiles-clean.service.d \
\t\tsystemd-tmpfiles-setup.service.d \
\t\tsystemd-tmpfiles-setup-dev.service.d \
\t\tsystemd-udev-trigger.service.d \
\t\tsystemd-udevd.service.d \
\t\tsystemd-update-done.service.d \
\t\tsystemd-update-utmp.service.d \
\t\tsystemd-update-utmp-runlevel.service.d \
\t\tsystemd-user-sessions.service.d \
\t\tsystemd-vconsole-setup.service.d \
\t\tdbus-org.freedesktop.hostname1.service.d \
\t\tdbus-org.freedesktop.locale1.service.d \
\t\tdbus-org.freedesktop.login1.service.d \
\t\tdbus-org.freedesktop.machine1.service.d \
\t\tdbus-org.freedesktop.network1.service.d \
\t\tdbus-org.freedesktop.resolve1.service.d \
\t\tdbus-org.freedesktop.timedate1.service.d \
\t\tdisplay-manager.service.d \
\t\tkvm.service.d \
\t\trescue.service.d \
\t\temergency.service.d \
\t\tssh.service.d \
\t\tsshd.service.d \
\t\trc-local.service.d \
\t\tsystemd-localed.service.d \
\t\tuser@.service.d \
\t\tuser@0.service.d \
\t\tuser@1.service.d \
\t\tuser@2.service.d \
\t\tuser@3.service.d \
\t\tuser@4.service.d \
\t\tuser@5.service.d \
\t\tuser@6.service.d \
\t\tuser@7.service.d \
\t\tuser@8.service.d \
\t\tuser@8.service.d \
\t\tuser@9.service.d \
\t\tuser-.slice.d \
\t\tuser-runtime-dir@.service.d \
\t; do
\t\tmkdir -p "$TARGET/usr/lib/systemd/system/$d"
\tdone

\t# System .wants directories
\tfor d in \
\t\tgetty.target.wants \
\t\tinitrd.target.wants \
\t\tlocal-fs.target.wants \
\t\tmulti-user.target.wants \
\t\tsockets.target.wants \
\t\tsysinit.target.wants \
\t\ttimers.target.wants \
\t\tbasic.target.wants \
\t\tbluetooth.target.wants \
\t\tcryptsetup.target.wants \
\t\tdefault.target.wants \
\t\temergency.target.wants \
\t\tgraphical.target.wants \
\t\thalt.target.wants \
\t\thibernate.target.wants \
\t\thybrid-sleep.target.wants \
\t\tkexec.target.wants \
\t\tnetwork-online.target.wants \
\t\tnss-lookup.target.wants \
\t\tnss-user-lookup.target.wants \
\t\tpaths.target.wants \
\t\tpoweroff.target.wants \
\t\tprinter.target.wants \
\t\treboot.target.wants \
\t\tremote-fs.target.wants \
\t\trescue.target.wants \
\t\trpcbind.target.wants \
\t\trunlevel2.target.wants \
\t\trunlevel3.target.wants \
\t\trunlevel4.target.wants \
\t\trunlevel5.target.wants \
\t\tshutdown.target.wants \
\t\tsleep.target.wants \
\t\tsmartcard.target.wants \
\t\tsuspend.target.wants \
\t\tumount.target.wants \
\t; do
\t\tmkdir -p "$TARGET/usr/lib/systemd/system/$d"
\tdone

\t# User directories
\tfor d in \
\t\tapp.slice.d \
\t\tbasic.target.wants \
\t\tbluetooth.target.wants \
\t\tdefault.target.wants \
\t\texit.target.wants \
\t\tgraphical-session.target.wants \
\t\tgraphical-session-pre.target.wants \
\t\tsockets.target.wants \
\t\tsound.target.wants \
\t\tsysinit.target.wants \
\t\ttimers.target.wants \
\t\twayland-session.target.wants \
\t\txdg-desktop-autostart.target.wants \
\t\tdbus-org.freedesktop.impl.portal.Portal1.service.d \
\t\tdbus-org.freedesktop.impl.portal.desktop.gtk.service.d \
\t\tdbus-org.freedesktop.portal.Access.service.d \
\t\tdbus-org.freedesktop.portal.Background.service.d \
\t\tdbus-org.freedesktop.portal.Camera.service.d \
\t\tdbus-org.freedesktop.portal.Desktop.service.d \
\t\tdbus-org.freedesktop.portal.FileChooser.service.d \
\t\tdbus-org.freedesktop.portal.Location.service.d \
\t\tdbus-org.freedesktop.portal.NetworkMonitor.service.d \
\t\tdbus-org.freedesktop.portal.Print.service.d \
\t\tdbus-org.freedesktop.portal.RemoteDesktop.service.d \
\t\tdbus-org.freedesktop.portal.Screenshot.service.d \
\t\tdbus-org.freedesktop.portal.Secrets.service.d \
\t\tdbus-org.freedesktop.portal.Settings.service.d \
\t\tdbus-org.freedesktop.portal.Wallpaper.service.d \
\t\tpipewire-session-manager.service.d \
\t\tpipewire.service.d \
\t\tpipewire-pulse.service.d \
\t\tpipewire-media-session.service.d \
\t; do
\t\tmkdir -p "$TARGET/usr/lib/systemd/user/$d"
\tdone

\t# Locale directories (common ones)
\tfor lang in \
\t\taf am ar as ast az be bg bn br bs ca cs cy da de el en_GB eo es et eu fa fi fr fur ga gd gl gu he hi hr hu hy id is it ja ka kk km kn ko lt lv mk ml mr nb ne nl nn oc or pa pl ps pt pt_BR ro ru si sk sl sq sr sv ta te th tl tr uk vi zh_CN zh_TW be@latin kab \
\t; do
\t\tmkdir -p "$TARGET/usr/share/locale/$lang/LC_MESSAGES"
\tdone

\t# Man page directories
\tfor sect in 1 2 3 4 5 6 7 8; do
\t\tmkdir -p "$TARGET/usr/share/man/man$sect"
\tdone

\t# Man page locale directories (common ones)
\tfor lang in \
\t\tde fr it es pt ru zh_CN zh_TW ja ko pl nl cs hu ro \
\t; do
\t\tfor sect in 1 2 3 4 5 6 7 8; do
\t\t\tmkdir -p "$TARGET/usr/share/man/$lang/man$sect"
\t\tdone
\tdone

\t# Zsh directories
\tmkdir -p "$TARGET/usr/share/zsh/site-functions"
\tmkdir -p "$TARGET/usr/share/zsh/vendor-completions"

\t# Var lib systemd directories
\tmkdir -p "$TARGET/var/lib/systemd/catalog"
\tmkdir -p "$TARGET/var/lib/systemd/clock"
\tmkdir -p "$TARGET/var/lib/systemd/coredump"
\tmkdir -p "$TARGET/var/lib/systemd/linger"
\tmkdir -p "$TARGET/var/lib/systemd/random-seed"
\tmkdir -p "$TARGET/var/lib/systemd/timers"
\tmkdir -p "$TARGET/var/lib/systemd/timesync"
\tmkdir -p "$TARGET/var/lib/systemd/tpm2"
\tmkdir -p "$TARGET/var/lib/systemd/user"

\1'''
content = re.sub(pattern2, replacement2, content)

# Fix 3: Pre-create directories for ALL packages in apt cache AFTER setup_available but BEFORE predeps loop
pattern3 = r'(while predep=\$\(get_next_predep\); do)'
replacement3 = r'''# Pre-create directories for ALL packages in apt cache to avoid QEMU permission issues during dpkg --install (predeps)
\ttouch /test_precreate_before_predeps
\tfor deb in "$TARGET/var/cache/apt/archives/"*.deb; do
\t\tif [ -f "$deb" ]; then
\t\t\tfor dir in $(dpkg-deb -c "$deb" 2>/dev/null | awk '/^d/ {print $NF}' | sed 's|/$||'); do
\t\t\t\tmkdir -p "$TARGET/$dir"
\t\t\t\tdone
\t\tfi
\tdone

\1'''
content = re.sub(pattern3, replacement3, content, flags=re.MULTILINE)

# Fix 4: Pre-create directories for ALL packages in apt cache AFTER predeps loop but BEFORE base unpack
pattern4 = r'(^\s*if \[ -n "\$base" \]; then)'
replacement4 = r'''# Pre-create directories for ALL packages in apt cache to avoid QEMU permission issues during dpkg --unpack (base)
\ttouch /test_precreate_loop
\tfor deb in "$TARGET/var/cache/apt/archives/"*.deb; do
\t\tif [ -f "$deb" ]; then
\t\t\tfor dir in $(dpkg-deb -c "$deb" 2>/dev/null | awk '/^d/ {print $NF}' | sed 's|/$||'); do
\t\t\t\tmkdir -p "$TARGET/$dir"
\t\t\t\tdone
\t\tfi
\tdone

\1'''
content = re.sub(pattern4, replacement4, content, flags=re.MULTILINE)

# Fix 5: Pre-create directories for ALL packages in apt cache AFTER base unpack but BEFORE configure
pattern5 = r'(info CONFBASE "Configuring the base system\.\.\.")'
replacement5 = r'''# Pre-create directories for ALL packages in apt cache to avoid QEMU permission issues during dpkg --configure/--install (base configure)
\ttouch /test_precreate_before_configure
\tfor deb in "$TARGET/var/cache/apt/archives/"*.deb; do
\t\tif [ -f "$deb" ]; then
\t\t\tfor dir in $(dpkg-deb -c "$deb" 2>/dev/null | awk '/^d/ {print $NF}' | sed 's|/$||'); do
\t\t\t\tmkdir -p "$TARGET/$dir"
\t\t\t\tdone
\t\tfi
\tdone

\1'''
content = re.sub(pattern5, replacement5, content, flags=re.MULTILINE)

# Fix 6: Clean up .dpkg-new files after BASESUCCESS to avoid cache save issues
pattern6 = r'(info BASESUCCESS "Base system installed successfully\.\.")'
replacement6 = r'''# Clean up .dpkg-new files to avoid cache save permission issues
\tfind "$TARGET" -name "*.dpkg-new" -delete 2>/dev/null || true

\1'''
content = re.sub(pattern6, replacement6, content, flags=re.MULTILINE)
content = re.sub(pattern5, replacement5, content, flags=re.MULTILINE)

with open("/usr/share/debootstrap/scripts/debian-common", "w") as f:
    f.write(content)

print("Patched debian-common to fix libpam-runtime and libsystemd-shared issues")
PYEOF

echo "Debootstrap patched successfully"

# Test that current directory is writable
touch test_patch_ran
echo "Patch script ran successfully" > patch_test.log