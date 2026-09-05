#!/usr/bin/env bash
set -e

echo "=== Patching Android build files ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_DIR="$SCRIPT_DIR/../../client"
cd "$CLIENT_DIR/android"

# Copy custom AndroidManifest with LAN/VPN permissions
cp "$SCRIPT_DIR/AndroidManifest.xml" app/src/main/AndroidManifest.xml

# Copy permanent release keystore for reproducible APK signature
cp "$SCRIPT_DIR/crossdrop.keystore" app/crossdrop.keystore

# Determine alias and ensure alias 'crossdrop' exists
if command -v keytool &> /dev/null; then
  ALIAS=$(keytool -list -keystore app/crossdrop.keystore -storepass crossdrop123 | grep "PrivateKeyEntry" | awk '{print $1}' | tr -d ',' || true)
  if [ -z "$ALIAS" ]; then
    ALIAS=$(keytool -list -keystore app/crossdrop.keystore -storepass crossdrop123 | grep -m 1 "Entry type:" -B 1 | head -n 1 | awk '{print $1}' | tr -d ',' || true)
  fi
  if [ -n "$ALIAS" ] && [ "$ALIAS" != "crossdrop" ]; then
    echo "Renaming keystore alias from $ALIAS to crossdrop..."
    keytool -changealias -alias "$ALIAS" -destalias "crossdrop" -keystore app/crossdrop.keystore -storepass crossdrop123 || true
  fi
fi

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
  echo "Patching app/build.gradle.kts with permanent release signing and compileSdk 36..."
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle.kts
  sed -i 's/compileSdkVersion(flutter.compileSdkVersion)/compileSdkVersion(36)/g' app/build.gradle.kts
  sed -i 's/signingConfig = signingConfigs.getByName("debug")/signingConfig = signingConfigs.create("release") { storeFile = file("crossdrop.keystore"); storePassword = "crossdrop123"; keyAlias = "crossdrop"; keyPassword = "crossdrop123" }/g' app/build.gradle.kts || true
fi

# 2. Patch app/build.gradle (Groovy) if present
if [ -f app/build.gradle ]; then
  echo "Patching app/build.gradle with permanent release signing and compileSdk 36..."
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle
  sed -i 's/compileSdkVersion flutter.compileSdkVersion/compileSdkVersion 36/g' app/build.gradle
  sed -i 's/signingConfig = signingConfigs.debug/signingConfig = signingConfigs.create("release") { storeFile = file("crossdrop.keystore"); storePassword = "crossdrop123"; keyAlias = "crossdrop"; keyPassword = "crossdrop123" }/g' app/build.gradle || true
fi

echo "=== Android build files patched successfully ==="