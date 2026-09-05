#!/usr/bin/env bash
set -e

echo "=== Patching Android build files ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_DIR="$SCRIPT_DIR/../../client"
cd "$CLIENT_DIR/android"

# Copy custom AndroidManifest with LAN/VPN permissions
cp "$SCRIPT_DIR/AndroidManifest.xml" app/src/main/AndroidManifest.xml

# In gradle.properties
cat << 'EOF' >> gradle.properties
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

tasks.whenTaskAdded { task ->
    if (task.name.toLowerCase().contains("aarmetadata")) {
        task.enabled = false
    }
}
EOF
fi

# 3. Patch root build.gradle.kts if present
if [ -f build.gradle.kts ]; then
  echo "Patching root build.gradle.kts..."
  cat << 'EOF' >> build.gradle.kts

subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val method = androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                method.invoke(androidExt, 36)
            } catch (e1: Exception) {
                try {
                    val method2 = androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                    method2.invoke(androidExt, 36)
                } catch (e2: Exception) {}
            }
        }
    }
    tasks.configureEach {
        if (name.contains("AarMetadata", ignoreCase = true)) {
            enabled = false
        }
    }
}
EOF
fi

# 4. Patch root build.gradle (Groovy) if present
if [ -f build.gradle ]; then
  echo "Patching root build.gradle..."
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
        if (task.name.toLowerCase().contains("aarmetadata")) {
            task.enabled = false
        }
    }
}
EOF
fi

echo "=== Android files patched successfully ==="