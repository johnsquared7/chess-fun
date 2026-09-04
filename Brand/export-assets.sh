#!/bin/zsh
set -euo pipefail

brand_dir="${0:A:h}"
workspace_dir="${brand_dir:h}"
assets_dir="$workspace_dir/ios/Oddfish/Assets.xcassets"
temporary_dir="$(mktemp -d -t oddfish-brand.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT

sips -s format png "$brand_dir/OddfishMark.svg" --out "$temporary_dir/mark.png" >/dev/null
sips -z 120 120 "$temporary_dir/mark.png" --out "$assets_dir/OddfishMark.imageset/OddfishMark.png" >/dev/null
sips -z 240 240 "$temporary_dir/mark.png" --out "$assets_dir/OddfishMark.imageset/OddfishMark@2x.png" >/dev/null
sips -z 360 360 "$temporary_dir/mark.png" --out "$assets_dir/OddfishMark.imageset/OddfishMark@3x.png" >/dev/null

sips -s format png "$brand_dir/OddfishAppIcon.svg" --out "$temporary_dir/app-icon-alpha.png" >/dev/null
swift "$brand_dir/FlattenPNG.swift" \
    "$temporary_dir/app-icon-alpha.png" \
    "$assets_dir/AppIcon.appiconset/OddfishIcon.png"

if ! sips -g hasAlpha "$assets_dir/AppIcon.appiconset/OddfishIcon.png" | grep -q 'hasAlpha: no'; then
    print -u2 "App icon export unexpectedly contains transparency."
    exit 1
fi

print "Exported the square Split O mark and opaque app icon from the SVG masters."
