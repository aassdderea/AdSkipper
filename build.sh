#!/bin/bash
# AdSkipper 编译脚本
# 使用方法: bash build.sh
# 需要 theos 开发环境 (https://theos.dev)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEOS_DIR="${THEOS:-/opt/theos}"

echo "==========================================="
echo " AdSkipper 广告跳过插件 - 编译脚本"
echo "==========================================="

if [ ! -d "$THEOS_DIR" ]; then
    echo "[错误] theos 未安装或 THEOS 环境变量未设置"
    echo "请先安装 theos: https://theos.dev/docs/installation"
    exit 1
fi

echo "[信息] theos 路径: $THEOS_DIR"
echo "[信息] 项目路径: $SCRIPT_DIR"

export THEOS="$THEOS_DIR"
export THEOS_PACKAGE_SCHEME=rootless

cd "$SCRIPT_DIR"

echo "[信息] 清理旧的编译产物..."
rm -rf .theos packages 2>/dev/null || true

echo "[信息] 开始编译..."
make clean 2>/dev/null || true
make package FINALPACKAGE=1

if [ $? -eq 0 ]; then
    echo ""
    echo "==========================================="
    echo " 编译成功！"
    echo "==========================================="
    
    DEB_FILE=$(ls packages/*.deb 2>/dev/null | head -1)
    if [ -n "$DEB_FILE" ]; then
        echo "deb包位置: $SCRIPT_DIR/$DEB_FILE"
    fi
    
    echo ""
    echo "=== TrollFools 注入步骤 ==="
    echo "1. 在 iPhone 上打开 TrollFools"
    echo "2. 点击 + 选择 AdSkipper.dylib 或 deb包"
    echo "3. 选择要注入的目标 App"
    echo "4. 注入后打开App即可生效"
    echo ""
    echo "规则文件路径: /Library/Application Support/AdSkipper/rules.json"
    echo "可通过 Filza 编辑规则文件"
else
    echo "[错误] 编译失败！"
    exit 1
fi
