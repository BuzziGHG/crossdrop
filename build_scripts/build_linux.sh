#!/usr/bin/env bash
set -e

echo "=== [CrossDrop] Baue Linux Release & Debian (.deb) Paket ==="

cd "$(dirname "$0")/../client"

echo "1. Führe Flutter Build für Linux aus..."
flutter build linux --release

echo "2. Erstelle Debian Paket-Struktur..."
PKG_DIR="build/debian_package"
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/lib/crossdrop"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"

# Copy DEBIAN control file
cp linux/debian/DEBIAN/control "$PKG_DIR/DEBIAN/"

# Copy Flutter build bundle
cp -r build/linux/x64/release/bundle/* "$PKG_DIR/usr/lib/crossdrop/"

# Create wrapper script in /usr/bin
cat << 'EOF' > "$PKG_DIR/usr/bin/crossdrop"
#!/bin/bash
exec /usr/lib/crossdrop/crossdrop "$@"
EOF
chmod +x "$PKG_DIR/usr/bin/crossdrop"

# Copy Desktop entry
cp linux/debian/usr/share/applications/crossdrop.desktop "$PKG_DIR/usr/share/applications/"

echo "3. Packe .deb Datei..."
OUTPUT_DEB="../build_scripts/crossdrop_1.0.0_amd64.deb"
dpkg-deb --build "$PKG_DIR" "$OUTPUT_DEB"

echo "=== ERFOLG: Debian-Paket erstellt unter: $OUTPUT_DEB ==="
echo "Installation auf Debian/Ubuntu: sudo dpkg -i crossdrop_1.0.0_amd64.deb"
