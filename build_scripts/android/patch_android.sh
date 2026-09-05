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
  echo "Patching app/build.gradle.kts..."
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle.kts
  sed -i 's/compileSdkVersion(flutter.compileSdkVersion)/compileSdkVersion(36)/g' app/build.gradle.kts
  cat << 'EOF' >> app/build.gradle.kts

tasks.configureEach {
    if (name.contains("AarMetadata", ignoreCase = true)) {
        enabled = false
    }
}
EOF
fi

# 2. Patch app/build.gradle (Groovy) if present
if [ -f app/build.gradle ]; then
  echo "Patching app/build.gradle..."
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle
  sed -i 's/compileSdkVersion flutter.compileSdkVersion/compileSdkVersion 36/g' app/build.gradle
  cat << 'EOF' >> app/build.gradle

tasks.configureEach {
    if (name.toLowerCase().contains("aarmetadata")) {
        enabled = false
    }
}
EOF
fi

# 3. Patch root build.gradle.kts if present (NO afterEvaluate!)
if [ -f build.gradle.kts ]; then
  echo "Patching root build.gradle.kts..."
  cat << 'EOF' >> build.gradle.kts

subprojects {
    tasks.configureEach {
        if (name.contains("AarMetadata", ignoreCase = true)) {
            enabled = false
        }
    }
}
EOF
fi

# 4. Patch root build.gradle (Groovy) if present (NO afterEvaluate!)
if [ -f build.gradle ]; then
  echo "Patching root build.gradle..."
  cat << 'EOF' >> build.gradle

subprojects {
    tasks.configureEach {
        if (name.toLowerCase().contains("aarmetadata")) {
            enabled = false
        }
    }
}
EOF
fi

echo "=== Android files patched successfully ==="