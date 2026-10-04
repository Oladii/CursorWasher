#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/scripts/project.sh"
bash "$project_root/scripts/build.sh" --universal
app_dir="$project_root/Build/CursorWasher.app"
dmg_path="$project_root/Build/$APP_INSTALLER_FILENAME"
stage_dir="$(mktemp -d "$project_root/.build/Installer.XXXXXX")"
payload_dir="$stage_dir/Contents"
mount_dir="$stage_dir/Volume"
mounted=false
cleanup() {
  if [ "$mounted" = true ]; then
    if ! hdiutil detach "$mount_dir" >/dev/null; then
      printf 'Could not detach installer volume; temporary files kept at %s\n' "$stage_dir" >&2
      return 1
    fi
  fi
  rm -rf "$stage_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$payload_dir" "$mount_dir"

ditto "$app_dir" "$payload_dir/CursorWasher.app"
ln -s /Applications "$payload_dir/Applications"
cp "$project_root/Resources/installer-layout.dsstore" "$payload_dir/.DS_Store"
cp "$app_dir/Contents/Resources/app-icon.icns" "$payload_dir/.VolumeIcon.icns"

hdiutil create -fs HFS+ -format UDRW \
  -volname 'CursorWasher' \
  -srcfolder "$payload_dir" "$stage_dir/Installer-writable.dmg"
hdiutil attach -nobrowse -noautoopen -mountpoint "$mount_dir" \
  "$stage_dir/Installer-writable.dmg" >/dev/null
mounted=true
xcrun SetFile -a C "$mount_dir"
hdiutil detach "$mount_dir" >/dev/null
mounted=false
hdiutil convert "$stage_dir/Installer-writable.dmg" -format UDZO \
  -o "$stage_dir/Installer.dmg"

xcrun swiftc -O -module-cache-path "$project_root/.build/ModuleCache" \
  "$project_root/scripts/set-file-icon.swift" \
  -o "$stage_dir/SetFileIcon" -framework AppKit
"$stage_dir/SetFileIcon" "$app_dir/Contents/Resources/app-icon.icns" "$stage_dir/Installer.dmg"
hdiutil verify "$stage_dir/Installer.dmg"
python3 "$project_root/scripts/release_info.py" "$project_root" "$stage_dir/Installer.dmg" "$APP_VERSION" "$APP_BUILD" "$APP_INSTALLER_FILENAME"
mv -f "$stage_dir/Installer.dmg" "$dmg_path"
mv -f "$stage_dir/installer-info.json" "$project_root/Build/installer-info.json"
printf 'Installer: %s\n' "$dmg_path"
