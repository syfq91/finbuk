#!/usr/bin/env bash
set -euo pipefail

# Finbuk ARM64 APK Docker Build Script
# Uses docker image gmeligio/flutter-android:3.47.9

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="gmeligio/flutter-android:3.47.9"

echo "==> Building ARM64 release APK using Docker image: ${IMAGE_NAME}"

# Detect host Java 21 if present
JDK_MOUNT=()
if [ -d "${HOME}/.local/jdk-21" ]; then
  JDK_MOUNT=(-v "${HOME}/.local/jdk-21:/opt/jdk-21:ro")
fi

# Detect host Android SDK Platform 37.0 if present
PLATFORM_MOUNT=()
if [ -d "${HOME}/Android/Sdk/platforms/android-37.0" ]; then
  PLATFORM_MOUNT=(-v "${HOME}/Android/Sdk/platforms/android-37.0:/home/flutter/sdks/android-sdk/platforms/android-37.0:ro")
fi

# Ensure host gradle directory exists
mkdir -p "${HOME}/.gradle"

docker run --rm -u 0 \
  "${JDK_MOUNT[@]}" \
  "${PLATFORM_MOUNT[@]}" \
  -v "${HOME}/.gradle:/root/.gradle" \
  -v "${PROJECT_ROOT}:/workspace" \
  -w /workspace \
  "${IMAGE_NAME}" \
  bash -c "
    set -euo pipefail
    git config --global --add safe.directory '*'

    # 1. Setup Java 21
    if [ -x '/opt/jdk-21/bin/java' ]; then
      export JAVA_HOME=/opt/jdk-21
    else
      echo '==> Installing OpenJDK 21...'
      apt-get update -qq && apt-get install -y -q --no-install-recommends openjdk-21-jdk-headless
      export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
    fi
    export PATH=\"\${JAVA_HOME}/bin:\${PATH}\"

    echo '==> Java version in container:'
    java -version

    # 2. Patch tools.common.jar for Android SDK API 37 target matching
    python3 - << 'PYEOF'
import zipfile
jar_path = '/home/flutter/sdks/android-sdk/cmdline-tools/latest/lib/common/tools.common.jar'
try:
    with zipfile.ZipFile(jar_path, 'r') as zin:
        files = {item.filename: zin.read(item.filename) for item in zin.infolist()}
    target = 'com/android/sdklib/AndroidApiLevel.class'
    if target in files:
        data = files[target]
        if bytes([0x10, 0x24, 0xA2]) in data:
            files[target] = data.replace(bytes([0x10, 0x24, 0xA2]), bytes([0x10, 0x32, 0xA2]))
            with zipfile.ZipFile(jar_path, 'w', zipfile.ZIP_DEFLATED) as zout:
                for name, content in files.items():
                    zout.writestr(name, content)
            print('==> Successfully patched tools.common.jar for API 37 target hash')
except Exception as e:
    print('==> Notice: tools.common.jar check/patch:', e)
PYEOF

    # 3. Ensure platform android-37.0 is available
    if [ ! -d '/home/flutter/sdks/android-sdk/platforms/android-37.0' ]; then
      echo '==> Installing Android SDK Platform 37.0...'
      yes | /home/flutter/sdks/android-sdk/cmdline-tools/latest/bin/sdkmanager 'platforms;android-37.0' >/dev/null 2>&1 || true
    fi

    if [ -d '/home/flutter/sdks/android-sdk/platforms/android-37.0' ] && [ ! -e '/home/flutter/sdks/android-sdk/platforms/android-37' ]; then
      ln -s android-37.0 /home/flutter/sdks/android-sdk/platforms/android-37
    fi

    yes | flutter doctor --android-licenses >/dev/null 2>&1 || true

    # 4. Fetch dependencies & build release APK for ARM64
    echo '==> Fetching Flutter dependencies...'
    flutter pub get

    echo '==> Building release ARM64 APK...'
    flutter build apk --release --target-platform android-arm64

    # 5. Prepare dist directory and sha256 checksums
    mkdir -p dist
    if [ -f build/app/outputs/flutter-apk/app-release.apk ]; then
      cp build/app/outputs/flutter-apk/app-release.apk dist/finbuk-arm64-v8a-release.apk
    elif [ -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ]; then
      cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk dist/finbuk-arm64-v8a-release.apk
    fi
    cd dist
    sha256sum *.apk > checksums.sha256

    # 6. Fix permissions for host user
    chown -R $(id -u):$(id -g) /root/.gradle /workspace/build /workspace/dist /workspace/.dart_tool 2>/dev/null || true
    echo '==> Docker build completed successfully!'
  "
