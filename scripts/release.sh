#!/bin/zsh
# Builds a Compositor product package (a shippable .dmg).
#
# Always produces a UNIVERSAL binary (ARCHS="arm64 x86_64") so the single
# .app / .dmg runs natively on both Apple Silicon and Intel Macs.
#
# Two modes:
#   SIGN=1 (default, local) — signed + notarized with your "Developer ID Application"
#                              certificate and a notarytool profile. Uses create-dmg for the
#                              styled DMG window. Needs the Sparkle background art under scripts/dmg.
#   SIGN=0 (CI / unsigned)  — ad-hoc signed universal build; the DMG is made with the built-in
#                              hdiutil (no Homebrew dependency, no certificate, no notarization).
#                              Produces a valid multi-architecture product package.
#
# Env overrides:
#   ARCHS               architectures to build        (default "arm64 x86_64")
#   SIGN                1 = signed+notarized, 0 = unsigned/ad-hoc (default 1)
#   TEAM_ID             Apple Developer Team ID       (default 3E4X3B9Z9T)
#   CODE_SIGN_IDENTITY  signing identity (signed mode, default "Developer ID Application")
#   NOTARY_PROFILE      notarytool profile name       (default compositor-notary)
#   RELEASE_WORK_DIR    temp build dir               (default ~/Library/Caches/CompositorRelease)
#
# Local signed/notarized flow needs, all kept out of this repository:
#   - a "Developer ID Application" certificate in the login keychain
#   - notarization credentials saved once with:
#       xcrun notarytool store-credentials "compositor-notary" --apple-id "…" --team-id 3E4X3B9Z9T
#   - create-dmg (brew install create-dmg)  [only for the styled window in SIGN=1]
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP=Compositor
TEAM="${TEAM_ID:-3E4X3B9Z9T}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-compositor-notary}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN="${SIGN:-1}"
WORK="${RELEASE_WORK_DIR:-$HOME/Library/Caches/CompositorRelease}"
DIST="$PROJECT_DIR/dist"

settings=$(xcodebuild -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
MINIMUM=$(print -r -- "$settings" | awk -F' = ' '/ MACOSX_DEPLOYMENT_TARGET = /{print $2; exit}')
echo "==> $APP $VERSION ($BUILD), macOS >= $MINIMUM, archs=[$ARCHS], sign=$SIGN"

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"

echo "==> Archiving a Release build (universal: $ARCHS)"
if [[ "$SIGN" == "1" ]]; then
  xcodebuild archive -quiet \
    -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$WORK/$APP.xcarchive" -derivedDataPath "$WORK/DerivedData" \
    ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM"
else
  # Ad-hoc signed ("-") so the universal binary stays codesign-valid and runnable.
  xcodebuild archive -quiet \
    -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$WORK/$APP.xcarchive" -derivedDataPath "$WORK/DerivedData" \
    ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="$TEAM"
fi

APP_PATH="$WORK/$APP.xcarchive/Products/Applications/$APP.app"
[[ -d "$APP_PATH" ]] || { echo "!! App not found at $APP_PATH"; exit 1 }

# Confirm the binary is actually multi-architecture.
BIN="$APP_PATH/Contents/MacOS/$APP"
if [[ -f "$BIN" ]]; then
  echo "==> Binary architectures:"; lipo -info "$BIN"
fi

DMG="$DIST/$APP-$VERSION-universal.dmg"
rm -f "$DMG"

if [[ "$SIGN" == "1" ]]; then
  echo "==> Exporting, signed with Developer ID"
  xcodebuild -exportArchive -quiet \
    -archivePath "$WORK/$APP.xcarchive" \
    -exportOptionsPlist "$PROJECT_DIR/scripts/ExportOptions.plist" \
    -exportPath "$WORK/export"
  APP_PATH="$WORK/export/$APP.app"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"

  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$APP_PATH" "$WORK/$APP.zip"
  xcrun notarytool submit "$WORK/$APP.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
fi

echo "==> Assembling the DMG"
STAGE="$WORK/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications" 2>/dev/null || true

if command -v create-dmg >/dev/null 2>&1 && [[ "$SIGN" == "1" ]]; then
  # Styled window with background art — local signed release only.
  LOW="$PROJECT_DIR/scripts/dmg/dmg-bg.jpg"
  HIGH="$PROJECT_DIR/scripts/dmg/dmg-bg-retina.jpg"
  background=()
  if [[ -f "$LOW" && -f "$HIGH" ]]; then
    sips -s format png -s dpiWidth 72 -s dpiHeight 72 "$LOW" --out "$WORK/background.png" >/dev/null
    sips -s format png -s dpiWidth 144 -s dpiHeight 144 "$HIGH" --out "$WORK/background@2x.png" >/dev/null
    tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null
    background=(--background "$WORK/background.tiff")
  elif [[ -f "$LOW" ]]; then
    background=(--background "$LOW")
  fi
  create-dmg \
    --volname "$APP" \
    --window-pos 200 120 --window-size 600 380 \
    --icon-size 128 --text-size 13 \
    --icon "$APP.app" 160 180 --hide-extension "$APP.app" \
    --app-drop-link 440 180 \
    "${background[@]}" \
    "$DMG" "$STAGE"
else
  # Dependency-free DMG via hdiutil (CI / unsigned / no create-dmg).
  RW="$WORK/rw.dmg"
  hdiutil create -ov -volname "$APP" -srcfolder "$STAGE" -format UDRW "$RW" >/dev/null
  hdiutil convert "$RW" -format UDZO -o "$DMG" -ov >/dev/null
  rm -f "$RW"
fi

if [[ "$SIGN" == "1" ]]; then
  echo "==> Signing and notarizing the DMG"
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "==> What Gatekeeper will say on another Mac"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
  spctl --assess --type execute --verbose=2 "$APP_PATH" || true
else
  echo "==> (unsigned/ad-hoc DMG — run with SIGN=1 locally to sign + notarize before public release)"
fi

echo "==> Done: $DMG"
