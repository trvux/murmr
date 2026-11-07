#!/bin/zsh
# Builds "Murmr Stream.app" into app/build/. Needs only the Command Line Tools and Go.
#
#   scripts/bundle.sh                       ad-hoc signed (macOS may ask for permissions again after every rebuild)
#   MURMR_SIGN_ID="My Cert" scripts/bundle.sh   sign with a stable identity so permissions survive rebuilds
set -euo pipefail
cd "${0:A:h}/.."   # app/

APP="build/Murmr Stream.app"
# One source of truth for the version: the VERSION file at the repo root (see CHANGELOG.md and "Releasing" in CLAUDE.md).
VERSION="$(tr -d '[:space:]' < ../VERSION)"
BUILD="$(git -C .. rev-list --count HEAD 2>/dev/null || echo 1)"   # always grows, as macOS wants

echo "==> engine (Go)"
(cd .. && go build -ldflags "-X main.version=$VERSION" -o app/build/murmr .)

echo "==> speech engine (whisper-server, one self-contained file; built once, see scripts/build-whisper.sh)"
[[ -x vendor/whisper-server ]] || scripts/build-whisper.sh

echo "==> shell (Swift)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MurmrStream"

echo "==> bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MurmrStream"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
cp build/murmr "$APP/Contents/Resources/murmr"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# the two languages of the interface (Vietnamese words are the keys; English is the translation, see L10n.swift)
cp -R Resources/en.lproj Resources/vi.lproj "$APP/Contents/Resources/"
cp vendor/whisper-server "$APP/Contents/Resources/whisper-server"
mkdir -p "$APP/Contents/Resources/licenses"
cp vendor/licenses/* "$APP/Contents/Resources/licenses/"

echo "==> sign (${MURMR_SIGN_ID:--})"
# the helpers first, then the app around them
codesign --force --sign "${MURMR_SIGN_ID:--}" "$APP/Contents/Resources/whisper-server" "$APP/Contents/Resources/murmr"
codesign --force --deep --sign "${MURMR_SIGN_ID:--}" "$APP"
codesign --verify --deep --strict "$APP"

echo "built: $PWD/$APP  (version $VERSION, build $BUILD)"
