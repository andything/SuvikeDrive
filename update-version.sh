#!/bin/bash
set -e

# 获取脚本所在目录
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

# 读取 Resources/README.md 内容作为 releaseNotes
README_FILE="Resources/README.md"
if [ -f "$README_FILE" ]; then
    RELEASE_NOTES=$(cat "$README_FILE")
else
    RELEASE_NOTES="SuvikeDrive v${VERSION}"
    echo "⚠️  Resources/README.md 不存在，使用默认 releaseNotes"
fi

# 更新 version.json
cat > version.json << EOF
{
    "version": "$VERSION",
    "build": "$BUILD",
    "downloadURL": "https://github.com/andything/SuvikeDrive/releases/download/v${VERSION}/SuvikeDrive_v${VERSION}.dmg",
    "checksum": "$CHECKSUM",
    "checksumAlgorithm": "sha256",
    "releaseNotes": $(echo "$RELEASE_NOTES" | awk '{printf "%s\\n", $0}' | sed 's/"/\\"/g' | sed 's/^/"/;s/$/"/'),
    "size": $SIZE,
    "minOSVersion": "14.0",
    "isMandatory": false,
    "releaseDate": "$DATE"
}
EOF

echo "📋 version.json 已更新"
echo ""

# 提交并推送
git add version.json
git commit -m "更新 version.json 到 v$VERSION"
git push

echo ""
echo "✅ version.json 已更新并推送"
echo "📦 请在应用中点击'重试'重新下载"
