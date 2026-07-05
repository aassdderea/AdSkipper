#!/bin/bash
set -e

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
[ -z "$SDK_PATH" ] && echo "[错误] 未找到 iPhoneOS SDK" && exit 1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${1:-$SCRIPT_DIR/build}"
SRC_DIR="$SCRIPT_DIR/src"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

FRAMEWORKS="-framework UIKit -framework Foundation -framework CoreGraphics -weak_framework WebKit"
FLAGS="-fobjc-arc -O2 -isysroot $SDK_PATH -mios-version-min=11.0 -Isrc"

echo "[AdSkipper] 编译 arm64..."

OBJ_DIR="$BUILD_DIR/obj"
mkdir -p "$OBJ_DIR"

for src in "$SRC_DIR"/*.m; do
    xcrun -sdk iphoneos clang $FLAGS -arch arm64 -c "$src" -o "$OBJ_DIR/$(basename "$src" .m).o"
done

xcrun -sdk iphoneos clang $FLAGS -arch arm64 -c "$SCRIPT_DIR/Tweak.x" -o "$OBJ_DIR/Tweak.x.o" -x objective-c

xcrun -sdk iphoneos clang $FLAGS -arch arm64 -dynamiclib \
    -install_name @rpath/AdSkipper.dylib \
    $FRAMEWORKS \
    -o "$BUILD_DIR/AdSkipper.dylib" \
    $OBJ_DIR/*.o

ldid -S "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || true

echo "  [完成] $(ls -lh "$BUILD_DIR/AdSkipper.dylib" | awk '{print $5}')"
file "$BUILD_DIR/AdSkipper.dylib"
