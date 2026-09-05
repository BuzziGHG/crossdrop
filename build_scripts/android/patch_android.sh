#!/usr/bin/env bash
set -e

echo "=== Patching Android build files ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_DIR="$SCRIPT_DIR/../../client"
cd "$CLIENT_DIR/android"

# Copy custom AndroidManifest with LAN/VPN permissions
cp "$SCRIPT_DIR/AndroidManifest.xml" app/src/main/AndroidManifest.xml

# Disable AarMetadata checks and set compileSdk 36 in app/build.gradle
if [ -f app/build.gradle ]; then
  sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/g' app/build.gradle
  sed -i 's/compileSdkVersion flutter.compileSdkVersion/compileSdkVersion 36/g' app/build.gradle
  cat << 'EOF' >> app/build.gradle

tasks.whenTaskAdded { task ->
    if (task.name.contains("AarMetadata") || task.name.contains("aarMetadata")) {
        task.enabled = false
    }
}
EOF
fi

# Append subprojects compileSdkVersion 36 and disable AarMetadata in root build.gradle
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
    tasks.whenTaskAdded { task ->
        if (task.name.contains("AarMetadata") || task.name.contains("aarMetadata")) {
            task.enabled = false
        }
    }
}
EOF
fi

# In gradle.properties
cat << 'EOF' >> gradle.properties
android.useAndroidX=true
android.enableJetifier=true
android.suppressUnsupportedCompileSdk=36
EOF

echo "=== Android files patched successfully ==="