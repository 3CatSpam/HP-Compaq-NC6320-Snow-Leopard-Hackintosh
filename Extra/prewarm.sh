#!/bin/sh
# Reads the system files once before the installer starts so they sit in the RAM cache (works around USB read stalls).
D=/var/tmp/sld; mkdir -p $D
P=$D/prewarm.log
echo "prewarm start `date`" >> $P
for d in \
 /System/Library/Frameworks/ApplicationServices.framework \
 /System/Library/Frameworks/CoreServices.framework \
 /System/Library/Frameworks/CoreFoundation.framework \
 /usr/lib \
 /System/Library/Frameworks/Foundation.framework \
 /System/Library/Frameworks/AppKit.framework \
 /System/Library/Frameworks/Security.framework \
 /System/Library/Frameworks/IOKit.framework \
 /System/Library/Frameworks/Carbon.framework \
 /System/Library/Frameworks/QuartzCore.framework \
 /System/Library/PrivateFrameworks \
 /System/Library/Fonts \
 /System/Library/CoreServices \
 /System/Installation/CDIS ; do
  [ -d "$d" ] || continue
  echo "DIR $d `date`" >> $P
  find "$d" -type f | while read -r f; do cat "$f" > /dev/null 2>&1; done
  echo "DONE $d `date`" >> $P
done
echo "prewarm end `date`" >> $P
