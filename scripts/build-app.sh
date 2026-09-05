#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VENDOR_DIR="$PROJECT_DIR/Vendor/Mole"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_NAME="Mac Tidy"
EXECUTABLE_NAME="MacTidy"
ARTIFACT_NAME="Mac-Tidy"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
MOLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :MoleEngineVersion' "$INFO_PLIST")"

if [[ -n "${GO_BIN:-}" && -x "$GO_BIN" ]]; then
    GO_TOOL="$GO_BIN"
elif command -v go >/dev/null 2>&1; then
    GO_TOOL="$(command -v go)"
elif [[ -x "$PROJECT_DIR/.toolchain/go/1.27.0/bin/go" ]]; then
    GO_TOOL="$PROJECT_DIR/.toolchain/go/1.27.0/bin/go"
else
    print -u2 "Go 1.25 or newer is required to build bundled Mole binaries."
    exit 1
fi

PACKAGE_TEMP="$(mktemp -d /tmp/mac-tidy-package.XXXXXX)"
APP_PATH="$PACKAGE_TEMP/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
ENGINE_PATH="$CONTENTS/Resources/Mole"
ENGINE_BUILD="$PACKAGE_TEMP/engine-bin"
SOURCE_PATH="$PACKAGE_TEMP/$ARTIFACT_NAME-$VERSION-Source"
APP_ZIP="$PACKAGE_TEMP/$ARTIFACT_NAME-$VERSION-arm64-unnotarized.zip"
APP_DMG="$PACKAGE_TEMP/$ARTIFACT_NAME-$VERSION-arm64-unnotarized.dmg"
SOURCE_ZIP="$PACKAGE_TEMP/$ARTIFACT_NAME-$VERSION-source.zip"
SWIFT_SCRATCH_BASE="${MAC_TIDY_SCRATCH_DIR:-$PACKAGE_TEMP/swift}"
GO_CACHE="${MAC_TIDY_GO_CACHE:-/tmp/mac-tidy-go-cache}"
ICON_WORK="$PACKAGE_TEMP/MacTidy.iconset"

cleanup_package_temp() {
    case "$PACKAGE_TEMP" in
        /tmp/mac-tidy-package.*) rm -rf -- "$PACKAGE_TEMP" ;;
        *) print -u2 "Refusing unsafe temporary cleanup: $PACKAGE_TEMP" ;;
    esac
}
trap cleanup_package_temp EXIT

swift test --scratch-path "$SWIFT_SCRATCH_BASE-tests" --package-path "$PROJECT_DIR"

mkdir -p "$ENGINE_BUILD" "$GO_CACHE"
swift build -c release --arch arm64 \
    --scratch-path "$SWIFT_SCRATCH_BASE-arm64" --package-path "$PROJECT_DIR"
swift_bin_dir="$(swift build -c release --arch arm64 \
    --scratch-path "$SWIFT_SCRATCH_BASE-arm64" --show-bin-path --package-path "$PROJECT_DIR")"
(
    cd "$VENDOR_DIR"
    GOCACHE="$GO_CACHE" "$GO_TOOL" test ./...
    GOCACHE="$GO_CACHE" CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
        "$GO_TOOL" build -trimpath -ldflags='-s -w' -o "$ENGINE_BUILD/analyze-go" ./cmd/analyze
    GOCACHE="$GO_CACHE" CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
        "$GO_TOOL" build -trimpath -ldflags='-s -w' -o "$ENGINE_BUILD/status-go" ./cmd/status
)

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ENGINE_PATH" "$ICON_WORK"
ditto "$swift_bin_dir/$EXECUTABLE_NAME" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
ditto "$INFO_PLIST" "$CONTENTS/Info.plist"
ditto "$PROJECT_DIR/LICENSE" "$CONTENTS/Resources/LICENSE"
ditto "$PROJECT_DIR/NOTICE" "$CONTENTS/Resources/NOTICE"
ditto "$VENDOR_DIR/mole" "$ENGINE_PATH/mole"
ditto "$VENDOR_DIR/bin" "$ENGINE_PATH/bin"
ditto "$VENDOR_DIR/lib" "$ENGINE_PATH/lib"
ditto "$VENDOR_DIR/LICENSE" "$ENGINE_PATH/LICENSE"
ditto "$VENDOR_DIR/MODIFICATIONS.md" "$ENGINE_PATH/MODIFICATIONS.md"
ditto "$VENDOR_DIR/TRADEMARK.md" "$ENGINE_PATH/TRADEMARK.md"
ditto "$ENGINE_BUILD/analyze-go" "$ENGINE_PATH/bin/analyze-go"
ditto "$ENGINE_BUILD/status-go" "$ENGINE_PATH/bin/status-go"

BASE_ICON="$PACKAGE_TEMP/mac-tidy-1024.png"
swift "$PROJECT_DIR/scripts/generate-icon.swift" "$BASE_ICON" 1024
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
    parts=(${=spec})
    sips -z "$parts[1]" "$parts[1]" "$BASE_ICON" --out "$ICON_WORK/$parts[2]" >/dev/null
done
iconutil -c icns "$ICON_WORK" -o "$CONTENTS/Resources/AppIcon.icns"

chmod 755 "$CONTENTS/MacOS/$EXECUTABLE_NAME" "$ENGINE_PATH/mole" "$ENGINE_PATH/bin"/*.sh "$ENGINE_PATH/bin/analyze-go" "$ENGINE_PATH/bin/status-go"
xattr -cr "$APP_PATH"
for binary in "$CONTENTS/MacOS/$EXECUTABLE_NAME" "$ENGINE_PATH/bin/analyze-go" "$ENGINE_PATH/bin/status-go"; do
    [[ "$(/usr/bin/lipo -archs "$binary")" == "arm64" ]]
done
codesign --force --sign - "$ENGINE_PATH/bin/analyze-go"
codesign --force --sign - "$ENGINE_PATH/bin/status-go"
codesign --force --sign - "$CONTENTS/MacOS/$EXECUTABLE_NAME"
codesign --force --sign - --entitlements "$PROJECT_DIR/Resources/MacTidy.entitlements" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

[[ -x "$ENGINE_PATH/mole" ]]
[[ -x "$ENGINE_PATH/bin/analyze-go" ]]
[[ -x "$ENGINE_PATH/bin/status-go" ]]
[[ -f "$ENGINE_PATH/LICENSE" ]]
[[ -f "$ENGINE_PATH/MODIFICATIONS.md" ]]
if [[ -n "$(find "$ENGINE_PATH" -name .git -print -quit)" ]]; then
    print -u2 "Packaged engine contains forbidden Git metadata."
    exit 1
fi

mkdir -p "$PACKAGE_TEMP/smoke-home"
ENGINE_VERSION_OUTPUT="$(
    env -i HOME="$PACKAGE_TEMP/smoke-home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" NO_COLOR=1 \
        "$ENGINE_PATH/mole" --version
)"
if [[ "$ENGINE_VERSION_OUTPUT" != *"Mole version $MOLE_VERSION"* ]]; then
    print -u2 "Bundled Mole version smoke failed."
    exit 1
fi
env -i HOME="$PACKAGE_TEMP/smoke-home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" NO_COLOR=1 \
    "$ENGINE_PATH/mole" touchid --gui-status > "$PACKAGE_TEMP/touchid-status.json"
plutil -p "$PACKAGE_TEMP/touchid-status.json" >/dev/null

mkdir -p "$SOURCE_PATH/Vendor"
ditto "$PROJECT_DIR/Sources" "$SOURCE_PATH/Sources"
ditto "$PROJECT_DIR/Tests" "$SOURCE_PATH/Tests"
ditto "$PROJECT_DIR/Resources" "$SOURCE_PATH/Resources"
ditto "$PROJECT_DIR/scripts" "$SOURCE_PATH/scripts"
ditto "$PROJECT_DIR/.github" "$SOURCE_PATH/.github"
for file in .gitattributes .gitignore Package.swift README.md LICENSE NOTICE CONTRIBUTING.md SECURITY.md PROJECT_STATUS.md; do
    ditto "$PROJECT_DIR/$file" "$SOURCE_PATH/$file"
done
ditto "$VENDOR_DIR" "$SOURCE_PATH/Vendor/Mole"
rm -rf -- "$SOURCE_PATH/Vendor/Mole/.git"
rm -f -- "$SOURCE_PATH/Vendor/Mole/bin/analyze-go" "$SOURCE_PATH/Vendor/Mole/bin/status-go"

ditto -c -k --norsrc --keepParent "$APP_PATH" "$APP_ZIP"
mkdir -p "$PACKAGE_TEMP/dmg"
ditto --norsrc "$APP_PATH" "$PACKAGE_TEMP/dmg/$APP_NAME.app"
ln -s /Applications "$PACKAGE_TEMP/dmg/Applications"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$PACKAGE_TEMP/dmg" -format UDZO "$APP_DMG"
ditto -c -k --norsrc --keepParent "$SOURCE_PATH" "$SOURCE_ZIP"
unzip -tq "$APP_ZIP" >/dev/null
unzip -tq "$SOURCE_ZIP" >/dev/null
hdiutil verify "$APP_DMG" >/dev/null
zipinfo -1 "$SOURCE_ZIP" > "$PACKAGE_TEMP/source-entries.txt"
if grep -q '/\.git/' "$PACKAGE_TEMP/source-entries.txt"; then
    print -u2 "Source archive contains forbidden Git metadata."
    exit 1
fi
if grep -q '/\.toolchain/' "$PACKAGE_TEMP/source-entries.txt"; then
    print -u2 "Source archive contains local build tools."
    exit 1
fi

FINAL_APP_ZIP="$OUTPUT_DIR/$ARTIFACT_NAME-$VERSION-arm64-unnotarized.zip"
FINAL_APP_DMG="$OUTPUT_DIR/$ARTIFACT_NAME-$VERSION-arm64-unnotarized.dmg"
FINAL_SOURCE_ZIP="$OUTPUT_DIR/$ARTIFACT_NAME-$VERSION-source.zip"
mkdir -p "$OUTPUT_DIR"
rm -rf -- "$OUTPUT_DIR/$APP_NAME.app"
rm -f -- "$FINAL_APP_ZIP" "$FINAL_APP_DMG" "$FINAL_SOURCE_ZIP"
ditto --norsrc "$APP_ZIP" "$FINAL_APP_ZIP"
ditto --norsrc "$APP_DMG" "$FINAL_APP_DMG"
ditto --norsrc "$SOURCE_ZIP" "$FINAL_SOURCE_ZIP"
hdiutil verify "$FINAL_APP_DMG" >/dev/null

print -r -- "$FINAL_APP_DMG"
print -r -- "$FINAL_APP_ZIP"
print -r -- "$FINAL_SOURCE_ZIP"
