# Mac OS X Snow Leopard on the HP Compaq nc6320

Install Mac OS X 10.6 Snow Leopard on an **HP Compaq nc6320** from a USB stick, next to Windows XP
if you have it, with a boot menu that lists both. Keyboard, trackpad, Ethernet, sound and battery are
set up for you.

> **Status: untested outside the author's laptop.** The installer rewrites the boot sector of your disk.
> Back up what you care about first. The original boot sector is saved before anything is changed,
> and the boot sector is written last, so a failure earlier leaves your disk booting as before.

## What you need

| | |
|---|---|
| Laptop | HP Compaq nc6320 (Core 2 Duo, Intel GMA950) |
| RAM | **2 to 4 GB recommended** (1 GB is Snow Leopard's official minimum) |
| USB stick | **16 GB** (It gets erased). |
| A Mac **or** a Linux PC | Only to build the stick (Windows users: see step 2) |
| Snow Leopard disc image | `Mac_OS_X_10.6_Snow_Leopard_Retail.iso` (7.2 GB) from <https://archive.org/details/mac-os-x-10.6-snow-leopard-retail> |
| Free space on the laptop | A partition of **20 GB or more** for macOS |

This repository contains **no Apple software**. You bring the disc image; the scripts patch your own copy
(see [What gets patched](#what-gets-patched)). Only build 10A432, the archive.org retail disc, is supported.

## Install

1. **Make an empty partition called `SNOW LEOPARD`.**
   On the laptop, from a working OS (Windows XP, or any live Linux): shrink or delete a partition and
   create a new **primary** partition of at least 20 GB. Format it as **FAT32** and give it the label
   **`SNOW LEOPARD`**, in capitals. macOS reads the label to find it. The installer erases only that partition.
   Don't touch your Windows partition. If there is no partition with that label, the installer stops with an
   error ("no empty partition to install macOS on") and changes nothing.
2. **Build the stick.** Download this repository, put the `.iso` next to the scripts and plug in the stick.
   - **On a Mac:** in Terminal, `cd` into the folder and run `sudo bash make_stick.sh`.
   - **On Linux:** install `parted hfsprogs rsync libarchive-tools` (Debian/Ubuntu: `sudo apt install parted hfsprogs rsync libarchive-tools`),
     then run `sudo bash make_stick_linux.sh`. A live USB of any distribution works, including one booted on the nc6320 itself.
   - **On Windows:** Windows cannot write the Mac file system, and WSL2's default kernel has no HFS+ support either, so there is no native way. Boot any PC from an Ubuntu live USB
     (or use a Mac) and follow the Linux instructions.

   Either script lists the removable drives, asks which one, asks you to confirm twice, then erases it. 20 to 40 minutes.
3. **Install.** Charger plugged in. Plug the stick into the nc6320, switch on, press **F9**, pick the USB stick.
   Wait. Don't touch anything. A Mac installer screen appears; about 90 seconds later the installer starts
   by itself, and when it is done (30 to 60 minutes, depending on the stick) the laptop **turns itself off**.
4. **Remove the stick and switch on.** The boot menu shows macOS and Windows; macOS starts by itself
   after 8 seconds. Go through the macOS setup assistant.

If something goes wrong, `Extra/install.log` on the stick tells you what happened.

## Boot menu

The menu is written into the free space around the first partition (sectors 1 to 24, and the 62 sectors just
before the SNOW LEOPARD partition), so it needs those sectors to be empty. If the 62 sectors for the images are
not free you get a plain text menu instead. If no Windows partition is found the laptop boots straight into macOS.
If the space after the boot sector is in use by another boot loader, the installer stops before changing anything.

## Going back to the original boot sector

Create an empty file called `RESTORE_MBR` in the `Extra` folder of the stick, boot from the stick and wait for
it to power off. The boot code of your original MBR comes back; the partition table is left as it is. The
original sectors are also in `Extra/backup/` on the stick and on the macOS partition.

## What gets patched

`make_stick.sh` and the installer apply small byte patches (`Extra/patches/`, a few hundred bytes each) to
files from **your** copy of the disc. Each patch checks the checksum of the file it was made for and refuses
to touch anything else.

| Patch | What it does | Applied to |
|---|---|---|
| `dsmos_stick.patch` | lets the installer environment run on a PC | the stick |
| `osinstall.patch` | the installer skips Apple's hardware checks | the stick |
| `dsmos.patch` | same for the installed system | the installed macOS |
| `bcm5701.patch` | adds this laptop's Broadcom BCM5788 Ethernet to Apple's driver | the installed macOS |
| `security_tea.patch` | HTTPS in Safari, see below (optional) | your TLS build |

The Apple `installer` command line tool is extracted from `BSD.pkg` on your disc while the stick is built.

## Optional: HTTPS / TLS 1.2 in Safari

Plain Snow Leopard 10.6.0 cannot open most modern HTTPS sites. The fix is a rebuilt `Security.framework`
and `securityd` from the community project
<https://github.com/startergo/tls12-snow-leopard-merge>
(background: <https://forums.macrumors.com/threads/tls-1-2-for-snow-leopard-10-6-8-system-wide-security-framework-rebuild.2486304/>).
That project publishes **no prebuilt binaries**: you build them on a Snow Leopard 10.6.8 machine as described
there, then put them in `Extra/tls/`:

```
Extra/tls/Security
Extra/tls/securityd
Extra/tls/ssl_anchors.pem     (optional: the root certificates, a PEM bundle)
```

`make_stick.sh` applies `security_tea.patch` to `Security` (it fixes an endless loop in the certificate check)
and the installer puts the pair on the new system. Without an `Extra/tls/` folder the stick is built without TLS 1.2.

The patch fits one exact build of `Security` (see the first lines of `Extra/patches/security_tea.patch`).
If yours differs, `make_stick.sh` says so and stops; build the stick without the files, or open an issue.

## Notes

- Kernel flags are `cpus=1 arch=i386`: one core and the 32-bit kernel. Edit `Extra/org.chameleon.Boot.plist`
  on the installed system to change them.
- Apple's `AppleIntelCPUPowerManagement` kext is moved to `/Extra/disabled_kexts` on the installed system.
- Known gaps: headphone-jack switching, fingerprint reader, internal Wi-Fi (Intel 3945ABG), microphone.

## Credits

Chameleon boot loader, VoodooPS2, VoodooHDA, ACPIBatteryManager, and the tls12-snow-leopard-merge project.
Mac OS X and its components belong to Apple Inc.
