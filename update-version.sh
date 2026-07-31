#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

VERSION=${1:-"1.0.1"}
DMG_FILE="SuvikeDrive_v${VERSION}.dmg"

if [ ! -f "$DMG_FILE" ]; then
    echo "❌ 错误: 找不到 ${SCRIPT_DIR}/${DMG_FILE}"
    echo "请先运行 ./build.sh $VERSION 打包"
    exit 1
fi

echo "========================================="
echo "📦 更新 version.json 到 v$VERSION"
echo "========================================="

CHECKSUM=$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')
SIZE=$(stat -f%z "$DMG_FILE")
DATE=$(date +%Y-%m-%d)
BUILD=$(date +%Y%m%d)

echo "🔑 SHA-256: $CHECKSUM"
echo "📏 大小: $SIZE"
echo ""

# 读取 README.md 并转义为 JSON 字符串
README_FILE="Resources/README.md"
if [ -f "$README_FILE" ]; then
    echo "📖 正在读取 Resources/README.md..."
    # 使用 Python 读取并转义
    RELEASE_NOTES=$(python3 -c '
import json
try:
    with open("Resources/README.md", "r", encoding="utf-8") as f:
        content = f.read()
    print(json.dumps(content))
except Exception as e:
    print(json.dumps("SuvikeDrive v'"$VERSION"'"))
')
    echo "✅ 读取成功"
else
    RELEASE_NOTES="\"SuvikeDrive v${VERSION}\""
    echo "⚠️  Resources/README.md 不存在"
fi

# 直接写入 version.json（不用 heredoc 嵌套变量）
echo "{" > version.json
echo "    \"version\": \"$VERSION\"," >> version.json
echo "    \"build\": \"$BUILD\"," >> version.json
echo "    \"downloadURL\": \"https://github.com/andything/SuvikeDrive/releases/download/v${VERSION}/SuvikeDrive_v${VERSION}.dmg\"," >> version.json
echo "    \"checksum\": \"$CHECKSUM\"," >> version.json
echo "    \"checksumAlgorithm\": \"sha256\"," >> version.json
echo "    \"releaseNotes\": $RELEASE_NOTES," >> version.json
echo "    \"size\": $SIZE," >> version.json
echo "    \"minOSVersion\": \"14.0\"," >> version.json
echo "    \"isMandatory\": false," >> version.json
echo "    \"releaseDate\": \"$DATE\"" >> version.json
echo "}" >> version.json

echo "📋 version.json 已更新"

git add version.json
git commit -m "更新 version.json 到 v$VERSION" 2>/dev/null || echo "没有需要提交的更改"
git push 2>/dev/null || echo "推送失败，请手动推送"

echo ""
echo "✅ version.json 已更新"
