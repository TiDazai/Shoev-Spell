#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="$project_dir/dist/Shoev Spell.app"
dmg="$project_dir/dist/Shoev-Spell.dmg"
[[ -d "$app" ]] || "$project_dir/scripts/build-app.sh"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "Shoev Spell" -srcfolder "$staging" -ov -format UDZO "$dmg"
echo "$dmg"
