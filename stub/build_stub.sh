#!/usr/bin/env bash
# Cross-compile the Windows screensaver stub from macOS using mingw-w64.
#
# Requires:
#   brew install mingw-w64
#
# Produces:  stub/prebuilt/ScreensaverStub.exe  (statically-linked, no DLLs needed
#                                                besides Windows system DLLs)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

CXX="${CXX:-x86_64-w64-mingw32-g++}"
if ! command -v "$CXX" >/dev/null 2>&1; then
  echo "error: $CXX not found."
  echo "Install with:  brew install mingw-w64"
  exit 1
fi

mkdir -p prebuilt
OUT="prebuilt/ScreensaverStub.exe"

"$CXX" \
  -std=c++17 -O2 -municode -mwindows \
  -static -static-libgcc -static-libstdc++ \
  -Wl,--subsystem,windows \
  -DUNICODE -D_UNICODE \
  screensaver_stub.cpp \
  -o "$OUT" \
  -lgdiplus -lshcore -lole32 -luuid -lcomctl32 -lgdi32 -luser32 -lkernel32

echo "Built: $OUT ($(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT") bytes)"

# Mirror into the SwiftPM resource directory so `swift build` bundles the latest.
APP_RES="../ImageToScreensaver/Sources/ImageToScreensaver/Resources"
mkdir -p "$APP_RES"
cp -f "$OUT" "$APP_RES/ScreensaverStub.exe"
echo "Copied to: $APP_RES/ScreensaverStub.exe"
