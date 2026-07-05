#!/bin/bash
# AdSkipper 编译脚本
# 用法: bash build_xcode.sh [output_dir]

set -e

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [ -z "$SDK_PATH" ]; then
    echo "[错误] 未找到 iPhoneOS SDK"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${1:-$SCRIPT_DIR/build}"
SRC_DIR="$SCRIPT_DIR/src"
ARCHS="arm64 arm64e"
MIN_IOS="11.0"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

FRAMEWORKS="-framework UIKit -framework Foundation -framework CoreGraphics -framework CFNetwork -weak_framework WebKit"
FLAGS="-fobjc-arc -O2 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS -Isrc"

echo "[AdSkipper] SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
echo "[AdSkipper] 架构: $ARCHS"

THIN_DIRS=""

for arch in $ARCHS; do
    echo "  [编译 $arch]"
    OBJ_DIR="$BUILD_DIR/$arch"
    mkdir -p "$OBJ_DIR"

    for src in "$SRC_DIR"/*.m; do
        name=$(basename "$src" .m)
        xcrun -sdk iphoneos clang $FLAGS -arch $arch -c "$src" -o "$OBJ_DIR/$name.o"
    done

    xcrun -sdk iphoneos clang $FLAGS -arch $arch -c "$SCRIPT_DIR/Tweak.x" -o "$OBJ_DIR/Tweak.x.o" -x objective-c

    THIN="$BUILD_DIR/AdSkipper_$arch.dylib"
    xcrun -sdk iphoneos clang $FLAGS -arch $arch -dynamiclib \
        -install_name @rpath/AdSkipper.dylib \
        $FRAMEWORKS \
        -o "$THIN" \
        $OBJ_DIR/*.o
    
    THIN_DIRS="$THIN_DIRS $THIN"
done

echo "  [合并] lipo"
lipo -create $THIN_DIRS -output "$BUILD_DIR/AdSkipper.dylib"
rm -f $THIN_DIRS

echo "  [签名]"
ldid -S "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || echo "  (签名跳过，TrollStore环境可能不需要)"

SIZE=$(stat -f%z "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || stat -c%s "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null)
echo ""
echo "  [完成] AdSkipper.dylib ($SIZE bytes)"
echo "  架构: $(lipo -info "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || file "$BUILD_DIR/AdSkipper.dylib")"
echo "  install_name: $(otool -D "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || echo 'N/A')"
