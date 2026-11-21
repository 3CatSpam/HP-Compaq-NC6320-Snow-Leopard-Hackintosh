#!/bin/bash
# Builds the Snow Leopard install stick for the HP Compaq nc6320. Run it on a Mac:
#
#     sudo bash make_stick.sh            (it lists the USB drives and asks which one)
#     sudo bash make_stick.sh /dev/diskN
#
# Put Mac_OS_X_10.6_Snow_Leopard_Retail.iso next to this script (see README).
# EVERYTHING on the chosen USB drive is erased. Needs a stick of 16 GB or more.
#
# Safety: only Apple's own tools are run as root (dd, diskutil, fdisk, asr, hdiutil, perl).
# The Chameleon files are plain data copied to the stick; they only execute on the laptop.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EX="$HERE/Extra"
ISO_NAME="Mac_OS_X_10.6_Snow_Leopard_Retail.iso"
DISK="${1:-}"
MIN_BYTES=15000000000
MAX_BYTES=130000000000
PB=/usr/libexec/PlistBuddy
TMP="$(mktemp -d)"
ISO_DEV=""
APPLY="perl $EX/tools/applypatch.pl"

die() { trap - ERR; echo "" >&2; echo "ERROR: $*" >&2; exit 1; }
cleanup() { [ -n "$ISO_DEV" ] && hdiutil detach "$ISO_DEV" -quiet >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT
trap 'die "A command failed (line $LINENO). Stopping."' ERR

[ "$(id -u)" = "0" ] || die "Run with sudo:  sudo bash make_stick.sh"
[ "$(uname)" = "Darwin" ] || die "This script runs on macOS."

# ---------- files of this repository ----------
for f in chameleon/boot0 chameleon/boot1h chameleon/boot menu/s1.bin menu/stage2.bin menu/bank.bin install.sh prewarm.sh \
         patches/dsmos_stick.patch patches/dsmos.patch patches/bcm5701.patch patches/osinstall.patch patches/security_tea.patch tools/applypatch.pl; do
  [ -f "$EX/$f" ] || die "Missing file in this repository: Extra/$f"
done
[ "$(shasum -a 256 "$EX/chameleon/boot0"  | awk '{print $1}')" = "aef3f382ab29f00638293c8cead390a1c22d5df889e59e278037e7a747bb8ce8" ] || die "Extra/chameleon/boot0 is not the expected file."
[ "$(shasum -a 256 "$EX/chameleon/boot1h" | awk '{print $1}')" = "117820df0bd319a1849421a3260e912c1796368dd4c092a06c000a183790cbee" ] || die "Extra/chameleon/boot1h is not the expected file."
[ "$(shasum -a 256 "$EX/chameleon/boot"   | awk '{print $1}')" = "aeda83fb84196443c1e3425d7592a067154c3dfcb5d5527469fefbde75c8c5fd" ] || die "Extra/chameleon/boot is not the expected file."
[ "$(stat -f %z "$EX/menu/s1.bin")" = "440" ] || die "menu/s1.bin has the wrong size."

# ---------- the ISO ----------
ISO="$HERE/$ISO_NAME"
if [ ! -f "$ISO" ]; then
  FOUND="$(ls "$HERE"/*.iso 2>/dev/null | head -1 || true)"
  if [ -n "$FOUND" ]; then ISO="$FOUND"; else die "$ISO_NAME not found next to this script. Download it, see the README."; fi
fi
echo ">> Disc image: $ISO"
echo ">> Checking the image (read-only)..."
ATTACH="$(hdiutil attach -nobrowse -readonly -noverify "$ISO")"
ISO_DEV="$(printf '%s\n' "$ATTACH" | head -1 | awk '{print $1}')"
ISO_MNT=""
while IFS= read -r line; do
  cand="$(printf '%s' "$line" | cut -f3)"
  if [[ "$cand" == /Volumes/* ]] && [ -d "$cand/System/Installation/Packages" ]; then ISO_MNT="$cand"; break; fi
done <<< "$ATTACH"
[ -n "$ISO_MNT" ] || die "This image does not look like a Mac OS X install disc."
VER="$(defaults read "$ISO_MNT/System/Library/CoreServices/SystemVersion" ProductVersion 2>/dev/null || echo unknown)"
BLD="$(defaults read "$ISO_MNT/System/Library/CoreServices/SystemVersion" ProductBuildVersion 2>/dev/null || echo ?)"
if [ "$VER" != "10.6" ] || [ "$BLD" != "10A432" ]; then
  die "Found Mac OS X $VER ($BLD). The patches in this repository only fit Snow Leopard 10.6 build 10A432 (the archive.org retail disc)."
fi
echo "   Mac OS X $VER ($BLD): OK"

# patches must apply to THIS image: test them on the files of the image before touching the stick
OSI="System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework/Versions/A/OSInstall"
DSM="System/Library/Extensions/Dont Steal Mac OS X.kext/Contents/MacOS/Dont Steal Mac OS X"
$APPLY "$EX/patches/osinstall.patch"   "$ISO_MNT/$OSI" "$TMP/OSInstall.new"  >/dev/null || die "The OSInstall patch does not fit this image."
$APPLY "$EX/patches/dsmos_stick.patch" "$ISO_MNT/$DSM" "$TMP/dsmos_stick.new" >/dev/null || die "The dsmos patch does not fit this image."
echo "   Patches fit this image: OK"

# the Apple 'installer' tool is inside BSD.pkg, not on the disc root: extract it from your copy
echo ">> Extracting Apple's installer tool from BSD.pkg..."
mkdir -p "$TMP/bsd"
( cd "$TMP/bsd" && xar -xf "$ISO_MNT/System/Installation/Packages/BSD.pkg" Payload && gunzip -c Payload | cpio -idm ./usr/sbin/installer 2>/dev/null ) || true
[ -x "$TMP/bsd/usr/sbin/installer" ] || die "Could not extract the installer tool from BSD.pkg."
rm -f "$TMP/bsd/Payload"

# optional TLS 1.2 build
HAVE_TLS=0
if [ -f "$EX/tls/Security" ] && [ -f "$EX/tls/securityd" ]; then
  $APPLY "$EX/patches/security_tea.patch" "$EX/tls/Security" "$TMP/Security.new" >/dev/null || die "Extra/tls/Security is not the build the TLS patch was made for (see README)."
  HAVE_TLS=1; echo "   TLS 1.2 files found and patched: OK"
else
  echo "   No TLS 1.2 files in Extra/tls: building without them (see README)."
fi

# ---------- the target drive ----------
if [ -z "$DISK" ]; then
  echo ""; echo "External drives:"
  diskutil list external physical | grep -E '^/dev/disk' || die "No external drive found. Plug the stick in."
  read -r -p "Which one is the stick? (for example disk4): " DISK
  DISK="/dev/${DISK#/dev/}"
fi
[[ "$DISK" =~ ^/dev/disk[0-9]+$ ]] || die "That must be a whole disk like /dev/disk4 (no 's1' at the end)."
diskutil info -plist "$DISK" > "$TMP/disk.plist" 2>/dev/null || die "Unknown disk: $DISK"
get() { "$PB" -c "Print :$1" "$TMP/disk.plist" 2>/dev/null; }
[ "$(get Internal)" = "false" ]  || die "$DISK is not an external drive. Stopping."
[ "$(get WholeDisk)" = "true" ]  || die "$DISK is not a whole disk. Stopping."
[ "$(get BusProtocol)" = "USB" ] || die "$DISK is not on USB. Stopping."
SIZE="$(get TotalSize)"
[ "$SIZE" -ge "$MIN_BYTES" ] || die "$DISK is too small ($((SIZE/1000000)) MB). 16 GB or more please."
[ "$SIZE" -le "$MAX_BYTES" ] || die "$DISK is $((SIZE/1000000000)) GB: that looks like a backup disk, not a stick. Stopping."
diskutil info -plist / > "$TMP/root.plist"
ROOT_WHOLE="$("$PB" -c "Print :ParentWholeDisk" "$TMP/root.plist" 2>/dev/null || echo none)"
[ "/dev/$ROOT_WHOLE" != "$DISK" ] || die "$DISK holds this Mac's system. Stopping."

echo "============================================================"
echo " Target: $DISK  ($(get MediaName), $((SIZE/1000000000)) GB)"
diskutil list "$DISK" | sed 's/^/    /'
echo "============================================================"
echo " EVERYTHING on this drive will be ERASED."
read -r -p " 1/2 - Type the drive identifier again (for example disk4): " C1
[ "$C1" = "${DISK#/dev/}" ] || die "Not the same identifier. Nothing was changed."
read -r -p " 2/2 - Type ERASE to start: " C2
[ "$C2" = "ERASE" ] || die "Cancelled. Nothing was changed."

RDISK="/dev/r${DISK#/dev/}"; PART="${DISK}s1"; RPART="/dev/r${DISK#/dev/}s1"
mp_of() { diskutil info -plist "$PART" > "$TMP/part.plist"; "$PB" -c "Print :MountPoint" "$TMP/part.plist" 2>/dev/null; }

# ---------- partition and copy the disc ----------
echo ">> Partitioning (MBR + one HFS+ partition)..."
diskutil unmountDisk force "$DISK" >/dev/null 2>&1 || true
diskutil partitionDisk "$DISK" MBR JHFS+ SNOWINSTALL 100%
[ -e "$PART" ] || die "$PART does not exist after partitioning."
echo ">> Copying Snow Leopard to the stick (20 to 40 minutes)..."
asr restore --source "$ISO_MNT" --target "$PART" --erase --noprompt --noverify \
  || die "Copy failed. Alternative: Disk Utility > Restore, image to $PART."
hdiutil detach "$ISO_DEV" -quiet >/dev/null 2>&1 || true; ISO_DEV=""
diskutil mount "$PART" >/dev/null 2>&1 || true
VOL="$(mp_of)"
[ -n "$VOL" ] && [ -d "$VOL/System/Installation" ] || die "The copy looks incomplete."

# ---------- patches on the stick ----------
echo ">> Patching the stick (installer environment)..."
cat "$TMP/OSInstall.new"   > "$VOL/$OSI"
cat "$TMP/dsmos_stick.new" > "$VOL/$DSM"
cmp -s "$TMP/OSInstall.new"   "$VOL/$OSI" || die "OSInstall was not written correctly."
cmp -s "$TMP/dsmos_stick.new" "$VOL/$DSM" || die "dsmos was not written correctly."

# rc.cdrom: bigger RAM disks, no boot cache, and start our installer after boot
RC="$VOL/etc/rc.cdrom"; [ -f "$RC" ] || RC="$VOL/private/etc/rc.cdrom"
[ -f "$RC" ] || die "rc.cdrom not found on the stick."
perl -pi -e 's#^RAMDisk /Volumes 1024#RAMDisk /Volumes 4096#; s#^RAMDisk /var/tmp 1024#RAMDisk /var/tmp 32768#; s#^RAMDisk /var/run 1024#RAMDisk /var/run 8192#; s#^(\s*)BootCacheControl .*#$1true#' "$RC"
perl -0pi -e 's/(\n# tell launchd to commence)/\nif [ -f \/Extra\/prewarm.sh ]; then sh \/Extra\/prewarm.sh; fi\nif [ -f \/Extra\/install.sh ]; then ( sleep 90; sh \/Extra\/install.sh ) >\/dev\/null 2>&1 &\nfi\n$1/' "$RC"
grep -q 'Extra/install.sh' "$RC" || die "Could not add the installer hook to rc.cdrom."
grep -q 'RAMDisk /var/tmp 32768' "$RC" || die "Could not resize the RAM disks in rc.cdrom."

# ---------- our files ----------
echo ">> Copying the installer files..."
mkdir -p "$VOL/Extra"
rsync -a --exclude 'tls' --exclude 'menu/src' "$EX/" "$VOL/Extra/"
mkdir -p "$VOL/Extra/payload" "$VOL/Extra/backup"
cp "$TMP/bsd/usr/sbin/installer" "$VOL/Extra/payload/installer"; chmod 755 "$VOL/Extra/payload/installer"
if [ "$HAVE_TLS" = 1 ]; then
  cp "$TMP/Security.new" "$VOL/Extra/payload/Security"
  cp "$EX/tls/securityd" "$VOL/Extra/payload/securityd"
  [ -f "$EX/tls/ssl_anchors.pem" ] && cp "$EX/tls/ssl_anchors.pem" "$VOL/Extra/payload/ssl_anchors.pem"
fi
cp "$EX/chameleon/boot" "$VOL/boot"; chflags hidden "$VOL/boot"
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
mdutil -i off "$VOL" >/dev/null 2>&1 || true

# ---------- Chameleon boot sectors on the stick (dd = Apple's tool; the files are only data) ----------
echo ">> Making the stick bootable..."
diskutil unmountDisk force "$DISK" >/dev/null
dd if="$RDISK" of="$TMP/mbr_before.bin" bs=512 count=1 2>/dev/null
cp "$TMP/mbr_before.bin" "$TMP/mbr_new.bin"
dd if="$EX/chameleon/boot0" of="$TMP/mbr_new.bin" bs=440 count=1 conv=notrunc 2>/dev/null
dd if="$TMP/mbr_new.bin" of="$RDISK" bs=512 count=1 2>/dev/null
dd if="$EX/chameleon/boot1h" of="$RPART" bs=512 count=2 2>/dev/null
sync
fdisk -e "$RDISK" >/dev/null <<FDISKEOF
flag 1
write
y
quit
FDISKEOF
sync

# ---------- verify by reading back ----------
echo ">> Verifying..."
dd if="$RDISK" of="$TMP/mbr_after.bin" bs=512 count=1 2>/dev/null
[ "$(head -c 440 "$TMP/mbr_after.bin" | shasum -a 256)" = "$(head -c 440 "$EX/chameleon/boot0" | shasum -a 256)" ] || die "VERIFY FAILED: boot0 is not in the MBR."
[ "$(dd if="$TMP/mbr_after.bin" bs=1 skip=510 count=2 2>/dev/null | xxd -p)" = "55aa" ] || die "VERIFY FAILED: 55AA marker missing."
dd if="$RPART" of="$TMP/b1h.bin" bs=512 count=2 2>/dev/null
cmp -s "$TMP/b1h.bin" "$EX/chameleon/boot1h" || die "VERIFY FAILED: boot1h is not in the partition."
diskutil mount "$PART" >/dev/null 2>&1 || true
VOL="$(mp_of)"
[ -n "$VOL" ] && cmp -s "$EX/chameleon/boot" "$VOL/boot" || die "VERIFY FAILED: boot file missing on the stick."
cmp -s "$TMP/OSInstall.new" "$VOL/$OSI" || die "VERIFY FAILED: OSInstall."
[ -x "$VOL/Extra/payload/installer" ] && [ -f "$VOL/Extra/install.sh" ] || die "VERIFY FAILED: installer files missing."

echo ""
echo "============================================================"
echo " Done and verified."
echo " Eject the stick in the Finder before unplugging it."
echo " Next: see the README, step 3 (boot the laptop from the stick)."
echo "============================================================"
