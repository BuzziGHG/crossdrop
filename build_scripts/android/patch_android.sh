#!/usr/bin/env bash
set -e

echo "=== Patching Android build files ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_DIR="$SCRIPT_DIR/../../client"
cd "$CLIENT_DIR/android"

# Copy custom AndroidManifest with LAN/VPN permissions
cp "$SCRIPT_DIR/AndroidManifest.xml" app/src/main/AndroidManifest.xml

# Performance & compatibility settings in gradle.properties
cat << 'EOF' >> gradle.properties
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m
android.useAndroidX=true
android.enableJetifier=true
android.suppressUnsupportedCompileSdk=36
EOF

# 1. Patch app/build.gradle.kts if present
if [ -f app/build.gradle.kts ]; then
  echo "Patching app/build.gradle.kts to compileSdk 36..."
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle.kts
  sed -i 's/compileSdkVersion(flutter.compileSdkVersion)/compileSdkVersion(36)/g' app/build.gradle.kts
fi

# 2. Patch app/build.gradle (Groovy) if present
if [ -f app/build.gradle ]; then
  echo "Patching app/build.gradle to compileSdk 36..."
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle
  sed -i 's/compileSdkVersion flutter.compileSdkVersion/compileSdkVersion 36/g' app/build.gradle
fi

echo "=== Android build files patched successfully ==="