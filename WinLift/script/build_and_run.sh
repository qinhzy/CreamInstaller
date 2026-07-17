#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WinLift"
BUNDLE_ID="com.william.WinLift"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "WinLift 必须在 macOS 14+ 上构建和运行。" >&2
  exit 1
fi

cd "$ROOT_DIR"

if pgrep -f "qemu-system-aarch64.*WinLift/Virtual Machines" >/dev/null 2>&1; then
  echo "检测到 WinLift 虚拟机仍在运行。请先正常关闭 Windows，再重新构建。" >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --product "$APP_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    if ! open_app; then
      echo "open 启动失败，回退为直接运行 App 二进制。" >&2
      nohup "$APP_BINARY" >/dev/null 2>&1 &
    fi
    for _ in $(seq 1 20); do
      if pgrep -x "$APP_NAME" >/dev/null; then
        echo "$APP_NAME 已成功启动。"
        exit 0
      fi
      sleep 1
    done
    echo "验证失败：$APP_NAME 未在 20 秒内出现。" >&2
    exit 1
    ;;
  *)
    echo "用法: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
