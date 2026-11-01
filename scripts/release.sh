#!/bin/zsh
set -euo pipefail

usage() {
  print "Usage: $0 <version> [--draft|--prerelease]"
  print "Example: $0 1.0.0 --draft"
}

if (( $# < 1 || $# > 2 )); then
  usage >&2
  exit 2
fi

VERSION="$1"
RELEASE_MODE=""
if (( $# == 2 )); then
  RELEASE_MODE="$2"
  if [[ "$RELEASE_MODE" != "--draft" && "$RELEASE_MODE" != "--prerelease" ]]; then
    usage >&2
    exit 2
  fi
fi

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' ]]; then
  print -u2 "Version must be a semantic version such as 1.0.0."
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  print -u2 "GitHub CLI (gh) is required to publish a release."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/build}"
PRODUCT_PATH="$BUILD_ROOT/Xcode/Build/Products/Release/YT-DLPro"
DMG_PATH="$BUILD_ROOT/YT-DLPro-$VERSION.dmg"
TAG="v$VERSION"

cd "$PROJECT_ROOT"
/bin/mkdir -p "$BUILD_ROOT"
STAGING_DIR="$(/usr/bin/mktemp -d "$BUILD_ROOT/release-staging.XXXXXX")"
APP_PATH="$STAGING_DIR/YT-DLPro.app"

cleanup() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if (( MACOS_MAJOR < 14 )); then
  print -u2 "YT-DLPro requires macOS 14 (Sonoma) or newer. This Mac is running macOS $MACOS_VERSION."
  exit 1
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  print -u2 "A GitHub release for $TAG already exists."
  exit 1
fi

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

/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
/usr/bin/install -m 755 "$PRODUCT_PATH" "$APP_PATH/Contents/MacOS/YT-DLPro"
/usr/bin/install -m 644 "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
/usr/bin/install -m 644 "$PROJECT_ROOT/Resources/YT-DLPro.icns" "$APP_PATH/Contents/Resources/YT-DLPro.icns"
print -rn -- 'APPL????' > "$APP_PATH/Contents/PkgInfo"

/usr/bin/codesign --force --deep --sign - "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/hdiutil create \
  -volname "YT-DLPro $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

RELEASE_ARGS=("$TAG" "$DMG_PATH" --title "YT-DLPro $VERSION" --generate-notes)
if [[ "$RELEASE_MODE" == "--draft" ]]; then
  RELEASE_ARGS+=(--draft)
elif [[ "$RELEASE_MODE" == "--prerelease" ]]; then
  RELEASE_ARGS+=(--prerelease)
fi

gh release create "${RELEASE_ARGS[@]}"
print "Published release: $TAG"
print "DMG: $DMG_PATH"
