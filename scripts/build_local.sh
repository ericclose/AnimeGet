#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_NAME="anime_get"
RAW_VERSION="$(grep -E '^version:' pubspec.yaml | head -n1 | awk '{print $2}' | cut -d'+' -f1)"
VERSION="${VERSION:-${RAW_VERSION:-1.0.0}}"

BUILD_MACOS=false
BUILD_ANDROID=false
ANDROID_ARM64_ONLY=false
INSTALL_ANDROID=false
SKIP_TEST=false

usage() {
  cat <<'EOF'
Usage: ./scripts/build_local.sh [targets] [options]

Targets (default: both macos and android):
  macos           Build macOS release .dmg into dist/
  android         Build Android release .apk into dist/
  all             Build both macOS and Android (default)

Options:
  --arm64         Build only android-arm64 APK (faster for local phone testing)
  --install       Install built arm64-v8a APK to connected device via adb
  --skip-test     Skip flutter analyze and flutter test
  --version VER   Override output version (default: from pubspec.yaml)
  -h, --help      Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    macos)
      BUILD_MACOS=true
      shift
      ;;
    android)
      BUILD_ANDROID=true
      shift
      ;;
    all)
      BUILD_MACOS=true
      BUILD_ANDROID=true
      shift
      ;;
    --arm64)
      ANDROID_ARM64_ONLY=true
      shift
      ;;
    --install)
      INSTALL_ANDROID=true
      shift
      ;;
    --skip-test)
      SKIP_TEST=true
      shift
      ;;
    --version)
      VERSION="${2:?Missing version value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$BUILD_MACOS" == false && "$BUILD_ANDROID" == false ]]; then
  BUILD_MACOS=true
  BUILD_ANDROID=true
fi

echo "==> AnimeGet local build (version: ${VERSION})"

flutter pub get

if [[ "$SKIP_TEST" == false ]]; then
  echo "==> Running flutter analyze & flutter test..."
  flutter analyze
  flutter test
fi

mkdir -p dist

if [[ "$BUILD_MACOS" == true ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: macOS build requires macOS host." >&2
    exit 1
  fi
  echo "==> Building macOS release..."
  flutter build macos --release

  BIN_ARCHS="$(lipo -archs build/macos/Build/Products/Release/AnimeGet.app/Contents/MacOS/AnimeGet)"
  if [[ "$BIN_ARCHS" == *"arm64"* && "$BIN_ARCHS" == *"x86_64"* ]]; then
    ARCH="universal"
  else
    ARCH="$(uname -m)"
  fi

  DMG_NAME="${PACKAGE_NAME}-macos-${ARCH}-${VERSION}.dmg"
  rm -rf build/dmg_staging "dist/${DMG_NAME}"
  mkdir -p build/dmg_staging
  ditto build/macos/Build/Products/Release/AnimeGet.app build/dmg_staging/AnimeGet.app
  ln -s /Applications build/dmg_staging/Applications
  diskutil image create from --format UDZO --volumeName "AnimeGet" build/dmg_staging "dist/${DMG_NAME}"
  rm -rf build/dmg_staging
  echo "==> macOS package ready: dist/${DMG_NAME}"
fi

if [[ "$BUILD_ANDROID" == true ]]; then
  if [[ -z "${JAVA_HOME:-}" && -d "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home" ]]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
    export PATH="/opt/homebrew/opt/openjdk@21/bin:${PATH}"
  fi

  if [[ "$ANDROID_ARM64_ONLY" == true ]]; then
    echo "==> Building Android arm64-v8a release APK..."
    flutter build apk --release --target-platform android-arm64 --split-per-abi
    ABIS=("arm64-v8a")
  else
    echo "==> Building Android split APKs (arm64-v8a, armeabi-v7a, x86_64)..."
    flutter build apk --release --split-per-abi
    ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
  fi

  for abi in "${ABIS[@]}"; do
    SRC="build/app/outputs/flutter-apk/app-${abi}-release.apk"
    if [[ -f "$SRC" ]]; then
      TARGET="dist/${PACKAGE_NAME}-android-${abi}-${VERSION}.apk"
      cp "$SRC" "$TARGET"
      echo "==> Android package ready: ${TARGET}"
    fi
  done

  if [[ "$INSTALL_ANDROID" == true ]]; then
    ARM64_APK="dist/${PACKAGE_NAME}-android-arm64-v8a-${VERSION}.apk"
    if [[ -f "$ARM64_APK" ]]; then
      echo "==> Installing ${ARM64_APK} via adb..."
      adb install -r "$ARM64_APK"
    else
      echo "Warning: ${ARM64_APK} not found, skipping adb install." >&2
    fi
  fi
fi

echo "==> Output artifacts in dist/:"
ls -lh dist/
