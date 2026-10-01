#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/scripts/project.sh"
build_dir="$project_root/.build"
output_dir="$project_root/Build"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
module_cache="${CURSOR_WASH_MODULE_CACHE:-$build_dir/ModuleCache}"
mkdir -p "$build_dir" "$module_cache" "$output_dir"
stage_dir="$(mktemp -d "$output_dir/.CursorWasher.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
app_dir="$stage_dir/CursorWasher.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

case "${1:-}" in
  "") architectures=("$(uname -m)") ;;
  --universal) architectures=(arm64 x86_64) ;;
  *) printf 'Usage: bash scripts/build.sh [--universal]\n' >&2; exit 2 ;;
esac
sources=()
for source_name in "${APP_RUNTIME_SOURCES[@]}"; do
  sources+=("$project_root/Sources/$source_name.swift")
done

for architecture in "${architectures[@]}"; do
  xcrun swiftc -O -sdk "$sdk_path" -target "$architecture-apple-macosx$APP_MINIMUM_MACOS" \
    -module-cache-path "$module_cache" "${sources[@]}" \
    -o "$stage_dir/CursorWasher-$architecture" \
    -framework CoreImage -framework AppKit -framework CoreGraphics
done
if [ "${#architectures[@]}" -eq 2 ]; then
  xcrun lipo -create "$stage_dir/CursorWasher-arm64" "$stage_dir/CursorWasher-x86_64" \
    -output "$app_dir/Contents/MacOS/CursorWasher"
else
  cp "$stage_dir/CursorWasher-${architectures[0]}" "$app_dir/Contents/MacOS/CursorWasher"
fi
cp "$project_root/Resources/bucket-dry.png" "$app_dir/Contents/Resources/bucket.png"
cp "$project_root/Resources/water-calm-source.png" "$app_dir/Contents/Resources/water-calm-source.png"
iconset_dir="$stage_dir/AppIcon.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$project_root/Resources/app-icon.png" \
    --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$project_root/Resources/app-icon.png" \
    --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/app-icon.icns"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>CursorWasher</string>
<key>CFBundleDisplayName</key><string>CursorWasher</string>
<key>CFBundleIdentifier</key><string>$APP_IDENTIFIER</string>
<key>CFBundleExecutable</key><string>CursorWasher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>app-icon.icns</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>$APP_MINIMUM_MACOS</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - --options runtime --timestamp=none "$app_dir"
codesign --verify --strict "$app_dir"
for architecture in "${architectures[@]}"; do
  xcrun lipo "$app_dir/Contents/MacOS/CursorWasher" -verify_arch "$architecture"
done
for resource in bucket.png water-calm-source.png app-icon.icns; do
  test -s "$app_dir/Contents/Resources/$resource"
done
python3 "$project_root/scripts/replace-build.py" "$app_dir" "$output_dir/CursorWasher.app"
printf 'Built: %s\n' "$output_dir/CursorWasher.app"
