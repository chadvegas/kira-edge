#!/bin/bash
# Build Kira.icns from the PNGs in this folder.
# Usage:  chmod +x make-icns.command && ./make-icns.command
#         (or right-click → Open in Finder)
cd "$(dirname "$0")" || exit 1
ICON="Kira.iconset"

# This package ships the @2x files named "-2x" because "@" isn't allowed in the
# export filesystem. Restore Apple's required @2x names before building.
for f in "$ICON"/*-2x.png; do
  [ -e "$f" ] || continue
  mv -f "$f" "${f%-2x.png}@2x.png"
done

iconutil -c icns "$ICON" -o Kira.icns && echo "✓ Built Kira.icns"
