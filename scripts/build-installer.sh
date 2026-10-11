#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-$project_root/build}"
derived_data_dir="$build_dir/DerivedData"
output_dir="$build_dir/installer"
app_path="$derived_data_dir/Build/Products/Release/Mac Cleanup Assistant.app"
dmg_path="$output_dir/Mac-Cleanup-Assistant.dmg"

xcodebuild \
  -project "$project_root/MacCleanup.xcodeproj" \
  -scheme MacCleanup \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data_dir" \
  build

if [[ ! -d "$app_path" ]]; then
  printf 'Release app not found at: %s\n' "$app_path" >&2
  exit 1
fi

mkdir -p "$output_dir"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/mac-cleanup-installer.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

cp -R "$app_path" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"
hdiutil create \
  -volname 'Mac Cleanup Assistant' \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

printf 'Installer created: %s\n' "$dmg_path"