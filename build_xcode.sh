#!/bin/bash
set -e

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
[ -z "$SDK_PATH" ] && echo "[错误] 未找到 iPhoneOS SDK" && exit 1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${1:-$SCRIPT_DIR/build}"
SRC_DIR="$SCRIPT_DIR/src"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# === 诊断: 逐个排除可疑模块 ===
# WebConsole  → WKScriptMessageHandler协议依赖
# TouchSimulator → CoreGraphics符号
# NetworkBlocker → mach_vm_protect符号
# 先只保留 Tweak.x + RuleEngine + AdDetector + LogBuffer

SAFE_MODULES="RuleEngine AdDetector LogBuffer"
FRAMEWORKS="-framework UIKit -framework Foundation -weak_framework WebKit"
FLAGS="-fobjc-arc -O2 -isysroot $SDK_PATH -mios-version-min=11.0 -Isrc"

echo "[Diag] safe modules: $SAFE_MODULES"

OBJ_DIR="$BUILD_DIR/obj"
mkdir -p "$OBJ_DIR"

for src in "$SRC_DIR"/*.m; do
    name=$(basename "$src" .m)
    skip=1
    for m in $SAFE_MODULES; do [ "$name" = "$m" ] && skip=0; done
    [ $skip -eq 1 ] && continue
    echo "  ++ $name"
    xcrun -sdk iphoneos clang $FLAGS -arch arm64 -c "$src" -o "$OBJ_DIR/$name.o"
done

echo "  ++ Tweak.x"
xcrun -sdk iphoneos clang $FLAGS -arch arm64 -c "$SCRIPT_DIR/Tweak.x" -o "$OBJ_DIR/Tweak.x.o" -x objective-c

xcrun -sdk iphoneos clang $FLAGS -arch arm64 -dynamiclib \
    -install_name @rpath/AdSkipper.dylib \
    $FRAMEWORKS \
    -o "$BUILD_DIR/AdSkipper.dylib" \
    $OBJ_DIR/*.o

ldid -S "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null || true

echo "  [完成] $(ls -lh "$BUILD_DIR/AdSkipper.dylib" | awk '{print $5}')"
file "$BUILD_DIR/AdSkipper.dylib"

echo ""
echo "=== 包含的模块 ==="
nm -g "$BUILD_DIR/AdSkipper.dylib" 2>/dev/null | grep -i "adskipper\|[Tt] _OBJC_CLASS" | head -20 || true
