#!/bin/bash
# AdSkipper 编译脚本 (Xcode CLI / GitHub Actions)
# 用法: bash build_xcode.sh [output_dir]

set -e

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [ -z "$SDK_PATH" ]; then
    echo "[错误] 未找到 iPhoneOS SDK，请确保 Xcode 已安装"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${1:-$SCRIPT_DIR/build}"
SRC_DIR="$SCRIPT_DIR/src"
ARCHS="arm64 arm64e"
MIN_IOS="11.0"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

FRAMEWORKS="-framework UIKit -framework Foundation -framework CoreGraphics -framework CFNetwork -framework WebKit"
FLAGS="-fobjc-arc -O2 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS -Isrc"

echo "[AdSkipper] 开始编译..."
echo "  SDK: $SDK_PATH"
echo "  架构: $ARCHS"
echo "  最低iOS: $MIN_IOS"

for arch in $ARCHS; do
    echo "  [编译] $arch"
    OBJ_DIR="$BUILD_DIR/$arch"
    mkdir -p "$OBJ_DIR"

    for src in "$SRC_DIR"/*.m; do
        name=$(basename "$src" .m)
        xcrun -sdk iphoneos clang $FLAGS -arch $arch -c "$src" -o "$OBJ_DIR/$name.o"
    done

    xcrun -sdk iphoneos clang $FLAGS -arch $arch -c "$SCRIPT_DIR/Tweak.x" -o "$OBJ_DIR/Tweak.x.o" -x objective-c
done

echo "  [链接] 创建 dylib..."
OBJ_FILES="$BUILD_DIR/arm64/*.o"
xcrun -sdk iphoneos clang $FLAGS -dynamiclib \
    -install_name @executable_path/AdSkipper.dylib \
    $FRAMEWORKS \
    -o "$BUILD_DIR/AdSkipper.dylib" \
    $OBJ_FILES

if [ -f "$BUILD_DIR/AdSkipper.dylib" ]; then
    ldid -S"$SCRIPT_DIR/entitlements.plist" "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || true
    
    DYLIB_SIZE=$(stat -f%z "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || stat -c%s "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || echo "unknown")
    echo ""
    echo "  [完成] AdSkipper.dylib ($DYLIB_SIZE bytes)"
    echo "  位置: $BUILD_DIR/AdSkipper.dylib"
    echo ""
    echo "  配套文件 (放到/Library/Application Support/AdSkipper/):"
    echo "    - rules/default_rules.json"
    echo "    - rules/domain_blacklist.txt"
else
    echo "[错误] 编译失败"
    exit 1
fi
