#!/usr/bin/env bash
set -e

echo "=== [CrossDrop] Baue Linux Release & Debian (.deb) Paket ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../client"

echo "1. Fuehre Flutter Build fuer Linux aus..."
flutter build linux --release

echo "2. Erstelle Debian Paket-Struktur..."
PKG_DIR="$SCRIPT_DIR/debian_package"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/lib/crossdrop"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"

# Copy DEBIAN control file
cp "$SCRIPT_DIR/debian/DEBIAN/control" "$PKG_DIR/DEBIAN/"

# Copy Flutter build bundle
cp -r build/linux/x64/release/bundle/* "$PKG_DIR/usr/lib/crossdrop/"

# Create wrapper script in /usr/bin
cat << 'EOF' > "$PKG_DIR/usr/bin/crossdrop"
#!/bin/bash
exec /usr/lib/crossdrop/crossdrop "$@"
EOF
chmod +x "$PKG_DIR/usr/bin/crossdrop"

# Copy Desktop entry
cp "$SCRIPT_DIR/debian/usr/share/applications/crossdrop.desktop" "$PKG_DIR/usr/share/applications/"

echo "3. Packe .deb Datei..."
VER=$(grep '^version:' "$SCRIPT_DIR/../client/pubspec.yaml" | head -n1 | cut -d' ' -f2 | cut -d'+' -f1)
sed -i "s/^Version:.*/Version: $VER/" "$PKG_DIR/DEBIAN/control"
OUTPUT_DEB="$SCRIPT_DIR/crossdrop_${VER}_amd64.deb"
dpkg-deb --build "$PKG_DIR" "$OUTPUT_DEB"

echo "=== ERFOLG: Debian-Paket erstellt unter: $OUTPUT_DEB ==="