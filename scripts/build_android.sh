#!/usr/bin/env bash
# Build AKV VPN Android APKs (release, debug-signed unless android/key.properties exists).
#
# Usage:
#   bash scripts/build_android.sh            # arm64 split + universal
#   bash scripts/build_android.sh --all-abis # arm64 + armv7 + x86_64 + universal
#   bash scripts/build_android.sh --clean    # flutter clean first
#
# Requirements (see docs/BUILD_RU.md for full setup):
#   - Flutter 3.38.x (3.44+ breaks pinned deps: final IconData)
#   - JDK 17 (flutter config --jdk-dir ...)
#   - Android SDK 36 (flutter config --android-sdk ...)
#   - On low-RAM machines (WSL2 ~8GB) cap Gradle memory in ~/.gradle/gradle.properties:
#       org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m
#       org.gradle.workers.max=1
#       org.gradle.parallel=false
#       kotlin.daemon.jvmargs=-Xmx768m
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET_PLATFORM="android-arm64"
CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --all-abis) TARGET_PLATFORM="android-arm,android-arm64,android-x64" ;;
    --clean) CLEAN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo ">> Checking Flutter version (pubspec requires ^3.38.x; 3.44+ is known to fail)"
FLUTTER_VER=$(flutter --version | head -1 | awk '{print $2}')
case "$FLUTTER_VER" in
  3.38.*|3.39.*|3.4[0-3].*) ;;
  *) echo "WARNING: Flutter $FLUTTER_VER; builds are verified on 3.38.x." \
        "On 3.44+ the build fails (IconData became final). Continue at your own risk." ;;
esac

if [ "$CLEAN" = 1 ]; then
  echo ">> flutter clean"
  flutter clean
fi

echo ">> flutter pub get"
flutter pub get

echo ">> Code generation (build_runner + slang)"
dart run build_runner build --delete-conflicting-outputs
dart run slang

if [ ! -f android/app/libs/hiddify-core.aar ]; then
  echo ">> Downloading hiddify-core (pinned release, CHANNEL=prod)"
  make android-libs CHANNEL=prod
else
  echo ">> hiddify-core.aar already present, skipping download (rm android/app/libs/hiddify-core.aar to refetch)"
fi

if [ ! -f android/key.properties ]; then
  echo ">> NOTE: android/key.properties not found — APK will be signed with the DEBUG key (test builds only)."
fi

echo ">> flutter build apk --release ($TARGET_PLATFORM)"
flutter build apk --release --target lib/main.dart --target-platform "$TARGET_PLATFORM"

echo
echo "== Artifacts =="
ls -lh build/app/outputs/flutter-apk/*.apk
