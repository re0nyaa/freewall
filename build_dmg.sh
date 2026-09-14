#!/usr/bin/env bash
set -e

# 프로젝트 루트 디렉토리 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 1. freewall 릴리즈 빌드 시작..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project freewall/freewall.xcodeproj \
           -scheme freewall \
           -configuration Release \
           -derivedDataPath build_output \
           build -quiet

echo "📦 2. DMG 스테이징 디렉토리 구성 중..."
STAGING_DIR="/tmp/freewall_dmg_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# .app 복사 및 Applications 폴더 바로가기 링크 생성
cp -R build_output/Build/Products/Release/freewall.app "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 3. freewall.dmg 압축 이미지 생성 중..."
rm -f freewall.dmg
hdiutil create -volname "freewall" \
               -srcfolder "$STAGING_DIR" \
               -ov \
               -format UDZO \
               freewall.dmg

# 정리
rm -rf "$STAGING_DIR"
rm -rf build_output

echo "✅ DMG 빌드 완료: $(pwd)/freewall.dmg"
ls -lh freewall.dmg
