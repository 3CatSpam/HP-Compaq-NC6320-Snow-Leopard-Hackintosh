#!/bin/bash
# Same as make_stick.sh, for Linux (any live USB will do, even one booted on the nc6320 itself).
#
#     sudo bash make_stick_linux.sh            (lists the removable drives and asks which one)
#     sudo bash make_stick_linux.sh /dev/sdX
#
# Needs: parted, hfsprogs (mkfs.hfsplus), rsync, perl, python3, bsdtar (libarchive-tools), and
# a kernel with HFS+ support (Ubuntu, Debian, Fedora, Arch all have it).
#   Debian/Ubuntu:  sudo apt install parted hfsprogs rsync libarchive-tools
# Put Mac_OS_X_10.6_Snow_Leopard_Retail.iso next to this script. Everything on the chosen drive is erased.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EX="$HERE/Extra"
ISO_NAME="Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
DISK="${1:-}"
MIN_BYTES=15000000000
MAX_BYTES=130000000000
TMP="$(mktemp -d)"
ISO_MNT="$TMP/iso"; VOL="$TMP/stick"
APPLY="perl $EX/tools/applypatch.pl"

die() { trap - ERR; echo "" >&2; echo "ERROR: $*" >&2; exit 1; }
cleanup() {
  cd /
  mountpoint -q "$ISO_MNT" 2>/dev/null && umount "$ISO_MNT" || true
  mountpoint -q "$VOL" 2>/dev/null && umount "$VOL" || true
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'die "A command failed (line $LINENO). Stopping."' ERR

[ "$(id -u)" = "0" ] || die "Run with sudo:  sudo bash make_stick_linux.sh"
[ "$(uname)" = "Linux" ] || die "This script runs on Linux. On a Mac use make_stick.sh."
for t in parted mkfs.hfsplus rsync perl python3 bsdtar dd lsblk losetup; do
  command -v "$t" >/dev/null 2>&1 || die "Missing tool: $t  (Debian/Ubuntu: sudo apt install parted hfsprogs rsync libarchive-tools)"
done
grep -qw hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null || true
grep -qw hfsplus /proc/filesystems || die "This kernel has no HFS+ support (module hfsplus)."

# ---------- files of this repository ----------
for f in chameleon/boot0 chameleon/boot1h chameleon/boot menu/s1.bin menu/stage2.bin menu/bank.bin install.sh prewarm.sh \
         patches/dsmos_stick.patch patches/dsmos.patch patches/bcm5701.patch patches/osinstall.patch patches/security_tea.patch tools/applypatch.pl; do
  [ -f "$EX/$f" ] || die "Missing file in this repository: Extra/$f"
done
sha() { sha256sum "$1" | awk '{print $1}'; }
[ "$(sha "$EX/chameleon/boot0")"  = "aef3f382ab29f00638293c8cead390a1c22d5df889e59e278037e7a747bb8ce8" ] || die "Extra/chameleon/boot0 is not the expected file."
[ "$(sha "$EX/chameleon/boot1h")" = "117820df0bd319a1849421a3260e912c1796368dd4c092a06c000a183790cbee" ] || die "Extra/chameleon/boot1h is not the expected file."
[ "$(sha "$EX/chameleon/boot")"   = "aeda83fb84196443c1e3425d7592a067154c3dfcb5d5527469fefbde75c8c5fd" ] || die "Extra/chameleon/boot is not the expected file."
[ "$(stat -c %s "$EX/menu/s1.bin")" = "440" ] || die "menu/s1.bin has the wrong size."

# ---------- the ISO ----------
ISO="$HERE/$ISO_NAME"
if [ ! -f "$ISO" ]; then
  FOUND="$(ls "$HERE"/*.iso 2>/dev/null | head -1 || true)"
  if [ -n "$FOUND" ]; then ISO="$FOUND"; else die "$ISO_NAME not found next to this script. Download it, see the README."; fi
fi
echo ">> Disc image: $ISO"
# the retail image carries an Apple partition map: find the HFS+ volume inside it
OFFSET="$(python3 - "$ISO" <<'PY'
import struct, sys
f = open(sys.argv[1], 'rb')
def find(bs):
    # partition map entries start at block 1 (block size bs): 'PM', ..., start(4) size(4) name(32) type(32)
    for i in range(1, 64):
        f.seek(i * bs); e = f.read(512)
        if e[:2] != b'PM': break
        start, size = struct.unpack('>II', e[8:16])
        typ = e[48:80].split(b'\0')[0]
        if typ == b'Apple_HFS' or typ == b'Apple_HFSX':
            return start * bs
    return None
f.seek(0); d = f.read(512)
bs = struct.unpack('>H', d[2:4])[0] if d[:2] == b'ER' else 512
r = find(bs) or find(512) or find(2048)
print(r if r is not None else '')
PY
)"
mkdir -p "$ISO_MNT" "$VOL"
if [ -n "$OFFSET" ]; then mount -t hfsplus -o ro,loop,offset="$OFFSET" "$ISO" "$ISO_MNT" || die "Could not mount the HFS+ volume of the image."
else mount -t hfsplus -o ro,loop "$ISO" "$ISO_MNT" || die "Could not mount the image (no Apple partition map found)."; fi
[ -d "$ISO_MNT/System/Installation/Packages" ] || die "This image does not look like a Mac OS X install disc."
SV="$ISO_MNT/System/Library/CoreServices/SystemVersion.plist"
grep -q '<string>10.6</string>' "$SV" && grep -q '<string>10A432</string>' "$SV" \
  || die "This is not Snow Leopard 10.6 build 10A432. The patches in this repository only fit the archive.org retail disc."
echo "   Mac OS X 10.6 (10A432): OK"

OSI="System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework/Versions/A/OSInstall"
DSM="System/Library/Extensions/Dont Steal Mac OS X.kext/Contents/MacOS/Dont Steal Mac OS X"
$APPLY "$EX/patches/osinstall.patch"   "$ISO_MNT/$OSI" "$TMP/OSInstall.new"  >/dev/null || die "The OSInstall patch does not fit this image."
$APPLY "$EX/patches/dsmos_stick.patch" "$ISO_MNT/$DSM" "$TMP/dsmos_stick.new" >/dev/null || die "The dsmos patch does not fit this image."
echo "   Patches fit this image: OK"

echo ">> Extracting Apple's installer tool from BSD.pkg..."
mkdir -p "$TMP/bsd"
( cd "$TMP/bsd" && bsdtar -xf "$ISO_MNT/System/Installation/Packages/BSD.pkg" Payload \
  && gunzip -c Payload | bsdtar -xf - ./usr/sbin/installer ) || true
[ -f "$TMP/bsd/usr/sbin/installer" ] || die "Could not extract the installer tool from BSD.pkg."
chmod 755 "$TMP/bsd/usr/sbin/installer"; rm -f "$TMP/bsd/Payload"

HAVE_TLS=0
if [ -f "$EX/tls/Security" ] && [ -f "$EX/tls/securityd" ]; then
  $APPLY "$EX/patches/security_tea.patch" "$EX/tls/Security" "$TMP/Security.new" >/dev/null || die "Extra/tls/Security is not the build the TLS patch was made for (see README)."
  HAVE_TLS=1; echo "   TLS 1.2 files found and patched: OK"
else
  echo "   No TLS 1.2 files in Extra/tls: building without them (see README)."
fi

# ---------- the target drive ----------
if [ -z "$DISK" ]; then
  echo ""; echo "Removable drives:"
  lsblk -dno NAME,SIZE,MODEL,RM,TRAN | grep -v '^\(fd\|sr\|loop\|ram\)' | awk '$0 ~ / 1 / || /usb/ {print "  /dev/"$0}' || true
  read -r -p "Which one is the stick? (for example /dev/sdb): " DISK
fi
[[ "$DISK" =~ ^/dev/(sd[a-z]+|vd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$ ]] || die "That must be a whole disk like /dev/sdb (no partition number)."
[ -b "$DISK" ] || die "$DISK is not a block device."
B="$(basename "$DISK")"
RM="$(cat /sys/block/$B/removable 2>/dev/null || echo 0)"
TRAN="$(lsblk -dno TRAN "$DISK" 2>/dev/null | tr -d ' ' || true)"
[ "$RM" = "1" ] || [ "$TRAN" = "usb" ] || die "$DISK is not a removable/USB drive. Stopping."
SIZE="$(blockdev --getsize64 "$DISK")"
[ "$SIZE" -ge "$MIN_BYTES" ] || die "$DISK is too small ($((SIZE/1000000)) MB). 16 GB or more please."
[ "$SIZE" -le "$MAX_BYTES" ] || die "$DISK is $((SIZE/1000000000)) GB: that looks like a backup disk, not a stick. Stopping."
ROOTSRC="$(findmnt -no SOURCE / 2>/dev/null || true)"
case "$ROOTSRC" in "$DISK"*) die "$DISK holds the running system. Stopping.";; esac
if lsblk -no MOUNTPOINT "$DISK" | grep -q .; then
  echo "   Unmounting $DISK ..."; for m in $(lsblk -no MOUNTPOINT "$DISK" | grep .); do umount "$m"; done
fi

echo "============================================================"
echo " Target: $DISK  ($(lsblk -dno MODEL "$DISK" | sed 's/ *$//'), $((SIZE/1000000000)) GB)"
lsblk "$DISK" | sed 's/^/    /'
echo "============================================================"
echo " EVERYTHING on this drive will be ERASED."
read -r -p " 1/2 - Type the drive name again (for example sdb): " C1
[ "$C1" = "$B" ] || die "Not the same name. Nothing was changed."
read -r -p " 2/2 - Type ERASE to start: " C2
[ "$C2" = "ERASE" ] || die "Cancelled. Nothing was changed."

# ---------- partition, format, copy ----------
echo ">> Partitioning (MBR + one HFS+ partition)..."
wipefs -a "$DISK" >/dev/null
parted -s "$DISK" mklabel msdos mkpart primary 2048s 100%
# partition type AF (Apple HFS+) and the active flag, written straight into the MBR entry
printf '\x80' | dd of="$DISK" bs=1 seek=446 conv=notrunc 2>/dev/null
printf '\xaf' | dd of="$DISK" bs=1 seek=450 conv=notrunc 2>/dev/null
sync
partprobe "$DISK" 2>/dev/null || true; sleep 2
PART="${DISK}1"; [[ "$DISK" =~ [0-9]$ ]] && PART="${DISK}p1"
[ -b "$PART" ] || die "$PART does not exist after partitioning."
mkfs.hfsplus -v "Mac OS X Install DVD" "$PART" >/dev/null
mount -t hfsplus -o rw,force "$PART" "$VOL" || die "Could not mount the new HFS+ partition for writing."
echo ">> Copying Snow Leopard to the stick (20 to 40 minutes)..."
rsync -aH --numeric-ids --info=progress2 "$ISO_MNT/" "$VOL/" || die "Copy failed."
[ -d "$VOL/System/Installation" ] || die "The copy looks incomplete."

# ---------- patches on the stick ----------
echo ">> Patching the stick (installer environment)..."
cat "$TMP/OSInstall.new"   > "$VOL/$OSI"
cat "$TMP/dsmos_stick.new" > "$VOL/$DSM"
cmp -s "$TMP/OSInstall.new"   "$VOL/$OSI" || die "OSInstall was not written correctly."
cmp -s "$TMP/dsmos_stick.new" "$VOL/$DSM" || die "dsmos was not written correctly."

RC="$VOL/etc/rc.cdrom"; [ -f "$RC" ] || RC="$VOL/private/etc/rc.cdrom"
[ -f "$RC" ] || die "rc.cdrom not found on the stick."
perl -pi -e 's#^RAMDisk /Volumes 1024#RAMDisk /Volumes 4096#; s#^RAMDisk /var/tmp 1024#RAMDisk /var/tmp 32768#; s#^RAMDisk /var/run 1024#RAMDisk /var/run 8192#; s#^(\s*)BootCacheControl .*#$1true#' "$RC"
perl -0pi -e 's/(\n# tell launchd to commence)/\nif [ -f \/Extra\/prewarm.sh ]; then sh \/Extra\/prewarm.sh; fi\nif [ -f \/Extra\/install.sh ]; then ( sleep 90; sh \/Extra\/install.sh ) >\/dev\/null 2>&1 &\nfi\n$1/' "$RC"
grep -q 'Extra/install.sh' "$RC" || die "Could not add the installer hook to rc.cdrom."
grep -q 'RAMDisk /var/tmp 32768' "$RC" || die "Could not resize the RAM disks in rc.cdrom."

# ---------- our files ----------
echo ">> Copying the installer files..."
mkdir -p "$VOL/Extra"
rsync -a --no-owner --no-group --exclude tls --exclude menu/src "$EX/" "$VOL/Extra/"
mkdir -p "$VOL/Extra/payload" "$VOL/Extra/backup"
cp "$TMP/bsd/usr/sbin/installer" "$VOL/Extra/payload/installer"; chmod 755 "$VOL/Extra/payload/installer"
if [ "$HAVE_TLS" = 1 ]; then
  cp "$TMP/Security.new" "$VOL/Extra/payload/Security"
  cp "$EX/tls/securityd" "$VOL/Extra/payload/securityd"
  [ -f "$EX/tls/ssl_anchors.pem" ] && cp "$EX/tls/ssl_anchors.pem" "$VOL/Extra/payload/ssl_anchors.pem"
fi
cp "$EX/chameleon/boot" "$VOL/boot"
cat > "$VOL/Extra/org.chameleon.Boot.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Kernel Flags</key>
	<string>-v -f cpus=1 npci=0x2000 idlehalt=0 arch=i386</string>
	<key>Timeout</key>
	<string>2</string>
	<key>GraphicsEnabler</key>
	<string>No</string>
	<key>Graphics Mode</key>
	<string>1024x768x32</string>
	<key>USBBusFix</key>
	<string>Yes</string>
	<key>EHCIacquire</key>
	<string>Yes</string>
	<key>UHCIreset</key>
	<string>Yes</string>
</dict>
</plist>
PLIST
sync
cmp -s "$TMP/OSInstall.new" "$VOL/$OSI" || die "VERIFY FAILED: OSInstall."
[ -x "$VOL/Extra/payload/installer" ] && [ -f "$VOL/Extra/install.sh" ] || die "VERIFY FAILED: installer files missing."
umount "$VOL"; umount "$ISO_MNT"

# ---------- Chameleon boot sectors ----------
echo ">> Making the stick bootable..."
dd if="$DISK" of="$TMP/mbr.bin" bs=512 count=1 2>/dev/null
dd if="$EX/chameleon/boot0" of="$TMP/mbr.bin" bs=440 count=1 conv=notrunc 2>/dev/null
dd if="$TMP/mbr.bin" of="$DISK" bs=512 count=1 conv=notrunc,fsync 2>/dev/null
dd if="$EX/chameleon/boot1h" of="$PART" bs=512 count=2 conv=notrunc,fsync 2>/dev/null
sync

echo ">> Verifying..."
dd if="$DISK" of="$TMP/mbr_after.bin" bs=512 count=1 2>/dev/null
cmp -s <(head -c 440 "$TMP/mbr_after.bin") <(head -c 440 "$EX/chameleon/boot0") || die "VERIFY FAILED: boot0 is not in the MBR."
[ "$(dd if="$TMP/mbr_after.bin" bs=1 skip=510 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "55aa" ] || die "VERIFY FAILED: 55AA marker missing."
dd if="$PART" of="$TMP/b1h.bin" bs=512 count=2 2>/dev/null
cmp -s "$TMP/b1h.bin" "$EX/chameleon/boot1h" || die "VERIFY FAILED: boot1h is not in the partition."
[ "$(dd if="$DISK" bs=1 skip=450 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "af" ] || die "VERIFY FAILED: partition type is not AF."
[ "$(dd if="$DISK" bs=1 skip=446 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "80" ] || die "VERIFY FAILED: partition is not marked active."

echo ""
echo "============================================================"
echo " Done and verified. You can unplug the stick."
echo " Next: see the README, step 3 (boot the laptop from the stick)."
echo "============================================================"
