#!/usr/bin/env bash
set -e

echo "=== Patching Android build files for compileSdk 36 ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../../client/android"

# Copy custom AndroidManifest with LAN/VPN permissions
cp "$SCRIPT_DIR/AndroidManifest.xml" app/src/main/AndroidManifest.xml

# Set compileSdk 36 in app/build.gradle
if [ -f app/build.gradle ]; then
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle
  sed -i 's/compileSdkVersion flutter.compileSdkVersion/compileSdkVersion 36/g' app/build.gradle
  sed -i 's/targetSdk = flutter.targetSdkVersion/targetSdk = 34/g' app/build.gradle
fi

# Append subprojects compileSdkVersion 36 to root build.gradle
if [ -f build.gradle ]; then
  cat << 'EOF' >> build.gradle

subprojects {
    afterEvaluate { project ->
        if (project.hasProperty('android')) {
            project.android {
                compileSdkVersion 36
            }
        }
    }
}
EOF
fi

# Add gradle.properties settings
cat << 'EOF' >> gradle.properties
android.useAndroidX=true
android.enableJetifier=true
android.suppressUnsupportedCompileSdk=36
EOF

echo "=== Android files patched successfully ==="