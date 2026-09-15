#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_dir/.build/distribution"
arm_scratch="$build_root/arm64"
x86_scratch="$build_root/x86_64"
"$project_dir/scripts/prepare-lexicon.sh"
swift build --package-path "$project_dir" -c release --triple arm64-apple-macosx13.0 --scratch-path "$arm_scratch"
swift build --package-path "$project_dir" -c release --triple x86_64-apple-macosx13.0 --scratch-path "$x86_scratch"
arm_bin="$(swift build --package-path "$project_dir" -c release --triple arm64-apple-macosx13.0 --scratch-path "$arm_scratch" --show-bin-path)"
x86_bin="$(swift build --package-path "$project_dir" -c release --triple x86_64-apple-macosx13.0 --scratch-path "$x86_scratch" --show-bin-path)"
app="$project_dir/dist/Shoev Spell.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$arm_bin/ShoevSpell" "$x86_bin/ShoevSpell" -output "$app/Contents/MacOS/ShoevSpell"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$project_dir/LEXICON_LICENSES.md" "$app/Contents/Resources/LEXICON_LICENSES.md"
bundle="$(find "$arm_bin" -maxdepth 1 -type d -name 'ShoevSpell_*.bundle' -print -quit)"
[[ -z "$bundle" ]] || cp -R "$bundle" "$app/Contents/Resources/"
if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$project_dir/Resources/ShoevSpell.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$app"
else
  local_keychain="${SHOEV_SPELL_LOCAL_KEYCHAIN:-${HOME}/Library/Application Support/Shoev Spell Development/LocalSigning.keychain-db}"
  local_identity="Shoev Spell Local Development"
  if [[ -f "$local_keychain" ]] && security find-certificate -c "$local_identity" "$local_keychain" >/dev/null 2>&1; then
    security unlock-keychain -p "" "$local_keychain"
    certificate_sha="$({ security find-certificate -c "$local_identity" -Z "$local_keychain" || true; } | awk '/SHA-1/{print $3; exit}')"
    if [[ -z "$certificate_sha" ]]; then
      echo "Could not resolve local signing certificate" >&2
      exit 1
    fi
    codesign \
      --force \
      --entitlements "$project_dir/Resources/ShoevSpell.entitlements" \
      --sign "$certificate_sha" \
      --keychain "$local_keychain" \
      "$app"
  else
    codesign \
      --force \
      --entitlements "$project_dir/Resources/ShoevSpell.entitlements" \
      --sign - \
      "$app"
  fi
fi
codesign --verify --deep --strict "$app"
echo "$app"
