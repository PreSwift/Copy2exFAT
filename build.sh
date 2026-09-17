#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Copy2exFAT.app"
ICONSET="$ROOT/.build/AppIcon.iconset"

echo "→ 编译 Copy2exFAT"
cd "$ROOT"
swift build -c release --product Copy2exFAT

BIN="$(swift build -c release --product Copy2exFAT --show-bin-path)/Copy2exFAT"

echo "→ 生成图标"
mkdir -p "$ICONSET"
swift "$ROOT/Scripts/GenerateIcon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT/.build/AppIcon.icns"

echo "→ 打包应用"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Copy2exFAT"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/.build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "→ 签名"
codesign --force --deep --sign - "$APP" >/dev/null

echo "完成：$APP"
echo "可双击打开，或执行：open \"$APP\""
