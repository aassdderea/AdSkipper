#!/bin/bash
set -e
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

mkdir -p "$BUILD_DIR"

echo "[Hello] 编译最小诊断 dylib..."

xcrun -sdk iphoneos clang -fobjc-arc -O2 \
    -arch arm64 \
    -isysroot "$SDK_PATH" \
    -mios-version-min=11.0 \
    -dynamiclib \
    -install_name @rpath/hello.dylib \
    -framework UIKit -framework Foundation \
    -o "$BUILD_DIR/hello.dylib" \
    "$SCRIPT_DIR/test_hello.m"

lipo -create -arch arm64 "$BUILD_DIR/hello.dylib" -output "$BUILD_DIR/hello_fat.dylib" 2>/dev/null && \
    mv "$BUILD_DIR/hello_fat.dylib" "$BUILD_DIR/hello.dylib"

ldid -S "$BUILD_DIR/hello.dylib" 2>/dev/null || echo "  (签名跳过)"

echo "  [完成] $BUILD_DIR/hello.dylib"
echo "  架构: $(lipo -info "$BUILD_DIR/hello.dylib" 2>/dev/null)"
