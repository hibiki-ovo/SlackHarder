#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

app_name="SlackHarder"
version="${1:-0.1.0}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: bash scripts/package.sh [major.minor.patch]" >&2
    exit 1
fi

if [[ "${SWIFTPM_DISABLE_SANDBOX:-false}" == "true" ]]; then
    set -- --disable-sandbox
else
    set --
fi
swift build "$@" -c release -debug-info-format none --product "$app_name" --arch arm64 --arch x86_64
binary_directory="$(swift build "$@" -c release --arch arm64 --arch x86_64 --show-bin-path)"
output_directory="$project_root/dist"
staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT
app_bundle="$staging_directory/$app_name.app"
mkdir -p "$app_bundle/Contents/MacOS" "$output_directory"
cp "$binary_directory/$app_name" "$app_bundle/Contents/MacOS/$app_name"

cat > "$app_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$app_name</string>
    <key>CFBundleDisplayName</key><string>$app_name</string>
    <key>CFBundleExecutable</key><string>$app_name</string>
    <key>CFBundleIdentifier</key><string>io.github.hibiki-ovo.SlackHarder</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad hoc signing supports local execution without a paid Developer ID certificate.
codesign --force --sign - "$app_bundle"
codesign --verify --strict "$app_bundle"
plutil -lint "$app_bundle/Contents/Info.plist"
for architecture in arm64 x86_64; do
    lipo "$app_bundle/Contents/MacOS/$app_name" -verify_arch "$architecture"
done

archive="$output_directory/$app_name-$version-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
(
    cd "$output_directory"
    shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256"
)
echo "Created $archive"
