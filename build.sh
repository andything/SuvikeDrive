#!/bin/bash
set -e

# 固定路径定义
WORKSPACE_DIR="/Users/andything/XcodeProject/SuvikeDrive"
SOURCE_APP="/Users/andything/XcodeOut/Release/Debug/SuvikeDrive.app"

cd "${WORKSPACE_DIR}"

VERSION=${1:-"1.0.1"}
BUILD=$(date +%Y%m%d)
echo "📦 打包 SuvikeDrive v$VERSION"

# Info.plist 路径
INFO_PLIST="${WORKSPACE_DIR}/SuvikeDrive/App/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "${INFO_PLIST}"
plutil -replace CFBundleVersion -string "$BUILD" "${INFO_PLIST}"

# 校验源App是否存在
if [ ! -d "${SOURCE_APP}" ]; then
    echo "❌ 源文件不存在：${SOURCE_APP}"
    exit 1
fi

# 复制APP到工程目录
TARGET_APP="${WORKSPACE_DIR}/SuvikeDrive.app"
rm -rf "${TARGET_APP}"
cp -r "${SOURCE_APP}" "${TARGET_APP}"

# 制作dmg
create-dmg \
--volname "SuvikeDrive" \
--window-pos 200 120 \
--window-size 800 400 \
--icon-size 100 \
--icon "SuvikeDrive.app" 200 190 \
--hide-extension "SuvikeDrive.app" \
--app-drop-link 600 190 \
"SuvikeDrive_v${VERSION}.dmg" \
"SuvikeDrive.app" 2>/dev/null

# 计算校验信息
CHECKSUM=$(shasum -a 256 "SuvikeDrive_v${VERSION}.dmg" | awk '{print $1}')
SIZE=$(stat -f%z "SuvikeDrive_v${VERSION}.dmg")

echo ""
echo "✅ 打包完成！"
echo "📦 APP路径: ${TARGET_APP}"
echo "📦 DMG包: ${WORKSPACE_DIR}/SuvikeDrive_v${VERSION}.dmg"
echo "🔑 SHA-256: $CHECKSUM"
echo "📏 文件大小: $SIZE"
echo ""
echo "📋 version.json"
cat << EOF
{
    "version": "$VERSION",
    "build": "$BUILD",
    "downloadURL": "https://github.com/andything/SuvikeDrive/releases/download/v${VERSION}/SuvikeDrive_v${VERSION}.dmg",
    "checksum": "$CHECKSUM",
    "checksumAlgorithm": "sha256",
    "releaseNotes": "SuvikeDrive v${VERSION}",
    "size": $SIZE,
    "minOSVersion": "14.0",
    "isMandatory": false,
    "releaseDate": "$(date +%Y-%m-%d)"
}
EOF
