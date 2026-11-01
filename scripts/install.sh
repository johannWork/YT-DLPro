#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
ZIP_PATH="${ZIP_PATH:-$BUILD_ROOT/YT-DLPro-universal.zip}"
APP_PATH="$BUILD_ROOT/package/YT-DLPro.app"
INSTALL_PATH="$INSTALL_DIR/YT-DLPro.app"
PRODUCT_PATH="$BUILD_ROOT/Xcode/Build/Products/Release/YT-DLPro"

cd "$PROJECT_ROOT"
MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if (( MACOS_MAJOR < 14 )); then
  print -u2 "YT-DLPro requires macOS 14 (Sonoma) or newer. This Mac is running macOS $MACOS_VERSION."
  exit 1
fi

mkdir -p "$BUILD_ROOT/package" "$INSTALL_DIR"

xcodebuild \
  -scheme YTDLPro \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_ROOT/Xcode" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=14.0 \
  build

if [[ ! -x "$PRODUCT_PATH" ]]; then
  print -u2 "Build output not found: $PRODUCT_PATH"
  exit 1
fi

/bin/rm -rf "$APP_PATH"
/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
/usr/bin/install -m 755 "$PRODUCT_PATH" "$APP_PATH/Contents/MacOS/YT-DLPro"
/usr/bin/install -m 644 "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
/usr/bin/install -m 644 "$PROJECT_ROOT/Resources/YT-DLPro.icns" "$APP_PATH/Contents/Resources/YT-DLPro.icns"
print -rn -- 'APPL????' > "$APP_PATH/Contents/PkgInfo"

/usr/bin/codesign --force --deep --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

/bin/mkdir -p "$(dirname -- "$ZIP_PATH")"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -e "$INSTALL_PATH" ]]; then
  if [[ -w "$INSTALL_DIR" ]]; then
    /bin/rm -rf "$INSTALL_PATH"
  else
    sudo /bin/rm -rf "$INSTALL_PATH"
  fi
fi
if [[ -w "$INSTALL_DIR" ]]; then
  /usr/bin/ditto "$APP_PATH" "$INSTALL_PATH"
else
  sudo /usr/bin/ditto "$APP_PATH" "$INSTALL_PATH"
fi
/usr/bin/codesign --verify --deep --strict "$INSTALL_PATH"

print "Installed: $INSTALL_PATH"
print "Universal ZIP: $ZIP_PATH"