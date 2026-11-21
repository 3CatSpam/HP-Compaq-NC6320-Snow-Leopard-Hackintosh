#!/bin/sh
# Snow Leopard installer for the HP Compaq nc6320.
# Runs by itself inside the Snow Leopard installer environment when the stick boots
# (started from rc.cdrom by make_stick.sh). Everything is logged to /Extra/install.log on the stick.
#
# Order of operations (the boot sector is touched LAST, so any failure before that leaves your
# disk exactly as it was, except for the SNOW LEOPARD partition itself):
#   1 find the partition named SNOW LEOPARD, refuse if anything looks wrong
#   2 back up the MBR, the gap before the first partition and the Windows boot sector
#   3 format that partition and install Mac OS X
#   4 patch drivers, copy kexts and Chameleon
#   5 write the boot menu (MBR last)
#
# Marker files on the stick (/Extra):  RESTORE_MBR  = put the original boot sector back, nothing else
#                                      REINSTALL    = allow reinstalling over an existing macOS

X=/Extra
mount -uw / 2>/dev/null
L=$X/install.log
log() { echo "`date '+%H:%M:%S'` $1" >> $L; sync; }
msg() { # best effort on-screen message, then power off
  log "MESSAGE: $1"
  /usr/bin/osascript -e "display dialog \"$1\" buttons {\"Shut down\"} default button 1 with icon stop" >/dev/null 2>&1 &
  sleep 90; sync; /sbin/halt
  exit 0
}
fail() { log "FAILED: $1"; msg "$1 Nothing was changed on your Windows partition. Log: Extra/install.log on the USB stick."; }

[ -f $X/DONE ] && { log "already done, nothing to do"; exit 0; }
[ -d $X/patches ] || exit 0
log "===== nc6320 Snow Leopard installer ====="
BK=$X/backup; mkdir -p $BK

# ---------- helpers ----------
zero_sectors() { # $1 = start LBA, $2 = count : 0 if all zero
  dd if=/dev/rdisk$D of=/var/tmp/z.bin bs=512 skip=$1 count=$2 2>/dev/null
  perl -e 'local $/; open F,"<","/var/tmp/z.bin"; $_=<F>; exit(/[^\0]/ ? 1 : 0)'
}
sec_md5() { dd if=/dev/rdisk$D bs=512 skip=$1 count=${2:-1} 2>/dev/null | md5 -q; }
put_le32() { perl -e 'print pack("V",$ARGV[0])' $1; }

# ---------- 1. find the target ----------
ROOTDEV=`df / | awk 'NR==2{print $1}' | sed 's#/dev/##; s#s[0-9]*$##'`   # the stick itself, never touched
log "stick = $ROOTDEV"
TARGET=""
for s in `diskutil list | grep -o 'disk[0-9]*s[0-9]*' | sort -u`; do
  w=`echo $s | sed 's/s[0-9]*$//'`
  [ "$w" = "$ROOTDEV" ] && continue
  n=`diskutil info /dev/$s 2>/dev/null | sed -n 's/^ *Volume Name: *//p'`
  [ "$n" = "SNOW LEOPARD" ] && { TARGET=$s; break; }
done

if [ -f $X/RESTORE_MBR ]; then
  [ -f $BK/mbr_orig.bin ] || fail "No MBR backup on this stick."
  D=0; [ -n "$TARGET" ] && D=`echo $TARGET | sed 's/^disk\([0-9]*\)s.*/\1/'`
  dd if=$BK/mbr_orig.bin of=/var/tmp/m.bin bs=512 count=1 2>/dev/null
  dd if=/dev/rdisk$D of=/var/tmp/now.bin bs=512 count=1 2>/dev/null
  # only the 440 bytes of boot code go back; the partition table stays as it is now
  dd if=/var/tmp/now.bin of=/var/tmp/new.bin bs=512 count=1 2>/dev/null
  dd if=/var/tmp/m.bin of=/var/tmp/new.bin bs=440 count=1 conv=notrunc 2>/dev/null
  diskutil unmountDisk force disk$D >/dev/null 2>&1
  dd if=/var/tmp/new.bin of=/dev/rdisk$D bs=512 count=1 2>/dev/null
  rm -f $X/RESTORE_MBR; touch $X/DONE; sync
  log "original MBR boot code restored"
  msg "The original boot code is back. Windows boots directly again."
fi

[ -n "$TARGET" ] || fail "No partition named SNOW LEOPARD was found - there is no empty partition to install macOS on. Create one, see the README."
SL=$TARGET
D=`echo $SL | sed 's/^disk\([0-9]*\)s.*/\1/'`
N=`echo $SL | sed 's/^disk[0-9]*s//'`
log "target = $SL (disk$D, slice $N)"
[ "$N" -le 4 ] || fail "SNOW LEOPARD is not a primary partition (slice $N). Recreate it as a primary partition."
SIZE=`diskutil info /dev/$SL | sed -n 's/.*(\([0-9]*\) Bytes).*/\1/p' | sed -n 1p`
[ -n "$SIZE" ] && [ "$SIZE" -ge 15000000000 ] || fail "SNOW LEOPARD is too small (need at least 15 GB)."

# partition table
fdisk /dev/rdisk$D > /var/tmp/fdisk.txt 2>&1
cp /var/tmp/fdisk.txt $BK/fdisk_before.txt
sed -n 's/^ *\([1-4]\): \([0-9A-Fa-f][0-9A-Fa-f]\) .*\[ *\([0-9]*\) - *\([0-9]*\)\].*/\1 \2 \3 \4/p' /var/tmp/fdisk.txt > /var/tmp/parts.txt
M=`awk -v n=$N '$1==n{print $3}' /var/tmp/parts.txt`
[ -n "$M" ] || fail "Could not read the partition table."
log "SNOW LEOPARD starts at LBA $M"
cat /var/tmp/parts.txt >> $L

# existing macOS on it? refuse unless REINSTALL
diskutil mount /dev/$SL >/dev/null 2>&1
MP=`diskutil info /dev/$SL | sed -n 's/^ *Mount Point: *//p'`
if [ -n "$MP" ] && [ -f "$MP/System/Library/CoreServices/SystemVersion.plist" ] && [ ! -f $X/REINSTALL ]; then
  fail "SNOW LEOPARD already contains Mac OS X. Create $X/REINSTALL on the stick to erase and reinstall."
fi
[ -n "$MP" ] && diskutil unmount /dev/$SL >/dev/null 2>&1

# Windows partition (optional): a FAT/NTFS primary partition whose boot sector mentions NTLDR
XP=0
while read i id st sz; do
  [ "$i" = "$N" ] && continue
  case $id in 06|0B|0C|0E|07)
    if dd if=/dev/rdisk$D bs=512 skip=$st count=1 2>/dev/null | grep -a -q NTLDR; then XP=$st; break; fi;;
  esac
done < /var/tmp/parts.txt
log "Windows partition start LBA: $XP (0 = none)"

# menu geometry: 24 sectors for stage 2 right after the MBR, 62 sectors for the images just before SNOW LEOPARD
OKGAP=1
zero_sectors 1 24 || { dd if=/dev/rdisk$D bs=512 skip=1 count=1 2>/dev/null | grep -a -q NC63 || OKGAP=0; }
[ "$OKGAP" = 1 ] || fail "The space after the boot sector (sectors 1-24) is used by another boot loader. Not installing the boot menu."
FIRST=`awk 'BEGIN{m=999999999}{if($3<m)m=$3}END{print m}' /var/tmp/parts.txt`
[ "$FIRST" -ge 26 ] || fail "A partition starts too close to the boot sector."
BANK=0
if [ "$M" -ge 90 ]; then
  S=`expr $M - 62`
  OV=0
  while read i id st sz; do [ "$st" -eq 0 ] && continue; en=`expr $st + $sz`; [ "$st" -lt "$M" ] && [ "$en" -gt "$S" ] && OV=1; done < /var/tmp/parts.txt
  if [ "$OV" = 0 ] && zero_sectors $S 62; then BANK=$S; fi
fi
log "menu image bank at LBA $BANK (0 = text menu)"

# ---------- 2. backups ----------
dd if=/dev/rdisk$D of=$BK/mbr_orig.bin bs=512 count=1 2>/dev/null
dd if=/dev/rdisk$D of=$BK/first63_orig.bin bs=512 count=63 2>/dev/null
[ "$XP" != 0 ] && dd if=/dev/rdisk$D of=$BK/xp_pbr_orig.bin bs=512 skip=$XP count=1 2>/dev/null
MBR_MD5=`md5 -q $BK/mbr_orig.bin`
XP_MD5=""; [ "$XP" != 0 ] && XP_MD5=`md5 -q $BK/xp_pbr_orig.bin`
log "backup done. MBR md5 $MBR_MD5, Windows boot sector md5 $XP_MD5"

# ---------- 3. format + install ----------
diskutil unmount force /dev/$SL >/dev/null 2>&1
log "formatting $SL"
diskutil eraseVolume "Journaled HFS+" "Snow Leopard" /dev/$SL >> $L 2>&1 || fail "Formatting failed."
T="/Volumes/Snow Leopard"
[ -d "$T" ] || { diskutil mount /dev/$SL >/dev/null 2>&1; }
[ -d "$T" ] || fail "The new volume did not mount."
# make sure the partition type is Apple HFS (AF)
fdisk /dev/rdisk$D 2>/dev/null | grep -q "^ *$N: AF" || log "WARNING: partition type is not AF after formatting"

cp $X/payload/installer /var/tmp/installer && chmod 755 /var/tmp/installer
[ -x /var/tmp/installer ] || fail "installer tool missing on the stick (re-run make_stick.sh)."
log "running the Apple installer (this takes a while)"
/var/tmp/installer -pkg /System/Installation/Packages/OSInstall.mpkg -target "$T" -verboseR -dumplog >> $X/installer_out.log 2>&1
RC=$?
log "installer exit code $RC"
[ $RC -eq 0 ] || fail "The Mac OS X installer failed (code $RC)."
[ -f "$T/System/Library/CoreServices/SystemVersion.plist" ] || fail "Installation looks incomplete."

# ---------- 4. drivers, kexts, Chameleon ----------
E="$T/System/Library/Extensions"
setperm() { chown -R root:wheel "$1"; find "$1" -type d -exec chmod 755 {} \; ; find "$1" -type f -exec chmod 644 {} \; ; }
APPLY="perl $X/tools/applypatch.pl"

# dsmos (patched copy of Apple's file)
DB="$E/Dont Steal Mac OS X.kext/Contents/MacOS/Dont Steal Mac OS X"
$APPLY $X/patches/dsmos.patch "$DB" /var/tmp/dsmos.new >> $L 2>&1 && { cat /var/tmp/dsmos.new > "$DB"; log "dsmos patched"; } || fail "dsmos patch failed."
# Broadcom BCM5788 Ethernet
BKX="$E/IONetworkingFamily.kext/Contents/PlugIns/AppleBCM5701Ethernet.kext"
$APPLY $X/patches/bcm5701.patch "$BKX/Contents/MacOS/AppleBCM5701Ethernet" /var/tmp/bcm.new >> $L 2>&1 && cat /var/tmp/bcm.new > "$BKX/Contents/MacOS/AppleBCM5701Ethernet" || log "WARNING: Ethernet binary patch failed"
if ! grep -q 'pci14e4,169c' "$BKX/Contents/Info.plist"; then
  perl -0pi -e 's#(<key>IONameMatch</key>\s*<array>)#$1\n\t\t\t\t<string>pci14e4,169c</string>#' "$BKX/Contents/Info.plist"
  grep -q 'pci14e4,169c' "$BKX/Contents/Info.plist" || perl -0pi -e 's#(<string>pci14e4,1693</string>)#$1\n\t\t\t\t<string>pci14e4,169c</string>#' "$BKX/Contents/Info.plist"
  plutil -lint "$BKX/Contents/Info.plist" >> $L 2>&1
fi
log "Ethernet: `grep -c 169c "$BKX/Contents/Info.plist"` match entry"
# keyboard / trackpad, sound
for k in VoodooPS2Controller VoodooHDA; do
  rm -rf "$E/$k.kext"; cp -R $X/kexts/$k.kext "$E/$k.kext"; setperm "$E/$k.kext"
done
# battery: loaded after boot by a small LaunchDaemon
KX="$T/Users/Shared/kx"; mkdir -p "$KX"; rm -rf "$KX/ACPIBatteryManager.kext"
cp -R $X/kexts/ACPIBatteryManager.kext "$KX/"; setperm "$KX/ACPIBatteryManager.kext"
cat > "$T/Users/Shared/battery.sh" <<'BS'
#!/bin/sh
sleep 10
kextstat | grep -q ACPIBatteryManager || kextload /Users/Shared/kx/ACPIBatteryManager.kext
BS
chmod 755 "$T/Users/Shared/battery.sh"; chown root:wheel "$T/Users/Shared/battery.sh"
cat > "$T/Library/LaunchDaemons/nc6320.battery.plist" <<'LDP'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>nc6320.battery</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/Users/Shared/battery.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
LDP
chown root:wheel "$T/Library/LaunchDaemons/nc6320.battery.plist"; chmod 644 "$T/Library/LaunchDaemons/nc6320.battery.plist"
# Apple's CPU power management kext panics on this CPU/ACPI combination
mkdir -p "$T/Extra/disabled_kexts"
for k in AppleIntelCPUPowerManagement AppleIntelCPUPowerManagementClient; do
  [ -d "$E/$k.kext" ] && mv "$E/$k.kext" "$T/Extra/disabled_kexts/"
done

# TLS 1.2 (only when make_stick.sh found the files)
if [ -f $X/payload/Security ] && [ -f $X/payload/securityd ]; then
  SEC="$T/System/Library/Frameworks/Security.framework/Versions/A/Security"; DAE="$T/usr/sbin/securityd"
  mkdir -p "$T/Users/Shared/tls_backup"; cp -p "$SEC" "$T/Users/Shared/tls_backup/Security.stock"; cp -p "$DAE" "$T/Users/Shared/tls_backup/securityd.stock"
  cp $X/payload/Security "$SEC"; cp $X/payload/securityd "$DAE"; chown root:wheel "$SEC" "$DAE"; chmod 755 "$SEC" "$DAE"
  if [ -f $X/payload/ssl_anchors.pem ]; then
    mkdir -p "$T/usr/local/SecurityPieces"; cp $X/payload/ssl_anchors.pem "$T/usr/local/SecurityPieces/ssl_anchors.pem"
    chmod 755 "$T/usr/local" "$T/usr/local/SecurityPieces"; chmod 644 "$T/usr/local/SecurityPieces/ssl_anchors.pem"
  fi
  rm -f "$T"/var/db/dyld/dyld_shared_cache_*
  update_dyld_shared_cache -root "$T" -force >> $L 2>&1 && log "TLS 1.2 installed" || {
    log "dyld cache rebuild failed: restoring the original Security files"
    cp -p "$T/Users/Shared/tls_backup/Security.stock" "$SEC"; cp -p "$T/Users/Shared/tls_backup/securityd.stock" "$DAE"
    rm -f "$T"/var/db/dyld/dyld_shared_cache_*; update_dyld_shared_cache -root "$T" -force >> $L 2>&1; }
fi

# Chameleon + settings
cp $X/chameleon/boot "$T/boot"; chflags hidden "$T/boot"; chown root:wheel "$T/boot"
mkdir -p "$T/Extra"
cp $X/config/smbios.plist "$T/Extra/smbios.plist"
cat > "$T/Extra/org.chameleon.Boot.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Kernel Flags</key>
	<string>arch=i386</string>
	<key>Timeout</key>
	<string>0</string>
	<key>Quiet Boot</key>
	<string>Yes</string>
	<key>GraphicsEnabler</key>
	<string>Yes</string>
	<key>Graphics Mode</key>
	<string>1024x768x32</string>
	<key>USBBusFix</key>
	<string>No</string>
	<key>EHCIacquire</key>
	<string>No</string>
	<key>UHCIreset</key>
	<string>No</string>
	<key>Wake</key>
	<string>No</string>
</dict>
</plist>
PLIST
chown root:wheel "$T/Extra/smbios.plist" "$T/Extra/org.chameleon.Boot.plist"; chmod 644 "$T/Extra/smbios.plist" "$T/Extra/org.chameleon.Boot.plist"
mkdir -p "$T/Extra/backup"; cp $BK/* "$T/Extra/backup/" 2>/dev/null
rm -rf "$E/../Caches/com.apple.kext.caches/Startup"/* "$E/../Caches/com.apple.kext.caches/Directories" 2>/dev/null
rm -f "$T/System/Library/Extensions.mkext" "$T/System/Library/Extensions.kextcache"; touch "$E"
sync

# ---------- 5. boot sectors (MBR last) ----------
diskutil unmountDisk force disk$D >/dev/null 2>&1
dd if=$X/chameleon/boot1h of=/dev/rdisk${D}s$N bs=512 count=2 2>/dev/null   # Chameleon stage 1 in the partition boot sector
# stage 2 with this disk's positions patched into its config block (offset 4: magic, mac, windows, bank)
cp $X/menu/stage2.bin /var/tmp/stage2.bin
perl -e '
  open F,"+<:raw","/var/tmp/stage2.bin"; seek F,4,0; read F,$m,4; die "bad stage2" unless $m eq "NC63";
  print F pack("V3",$ARGV[0],$ARGV[1],$ARGV[2]);' $M $XP $BANK
dd if=/var/tmp/stage2.bin of=/dev/rdisk$D bs=512 seek=1 count=24 2>/dev/null
[ "$BANK" != 0 ] && dd if=$X/menu/bank.bin of=/dev/rdisk$D bs=512 seek=$BANK count=62 2>/dev/null
# MBR: only the first 440 bytes (code); disk signature and partition table stay as they are
dd if=/dev/rdisk$D of=/var/tmp/mbr_new.bin bs=512 count=1 2>/dev/null
dd if=$X/menu/s1.bin of=/var/tmp/mbr_new.bin bs=440 count=1 conv=notrunc 2>/dev/null
dd if=/var/tmp/mbr_new.bin of=/dev/rdisk$D bs=512 count=1 2>/dev/null
sync

# ---------- verify ----------
dd if=/dev/rdisk$D of=/var/tmp/mbr_after.bin bs=512 count=1 2>/dev/null
[ "`dd if=/var/tmp/mbr_after.bin bs=1 skip=440 count=72 2>/dev/null | md5 -q`" = "`dd if=$BK/mbr_orig.bin bs=1 skip=440 count=72 2>/dev/null | md5 -q`" ] || log "WARNING: partition table area changed"
[ "`dd if=/var/tmp/mbr_after.bin bs=1 count=440 2>/dev/null | md5 -q`" = "`md5 -q $X/menu/s1.bin`" ] || log "WARNING: MBR code mismatch"
if [ "$XP" != 0 ]; then
  [ "`sec_md5 $XP`" = "$XP_MD5" ] && log "Windows boot sector unchanged" || log "NOTE: Windows boot sector differs (normal after Windows ran, only the dirty flag changes)"
fi
touch $X/DONE; sync
log "===== DONE ====="
sync; sleep 3
/sbin/fsck_hfs -fy /dev/rdisk${D}s$N >> $L 2>&1
/sbin/halt
