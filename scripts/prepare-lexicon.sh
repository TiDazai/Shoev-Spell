#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
archive="$project_dir/Resources/Lexicon/lexicon.sqlite3.gz"
target="$project_dir/Sources/ShoevSpell/Resources/lexicon.sqlite3"
mkdir -p "$(dirname "$archive")" "$(dirname "$target")"
archive_tmp="$(mktemp "$archive.XXXXXX")"
target_tmp="$(mktemp "$target.XXXXXX")"
trap 'rm -f "$archive_tmp" "$target_tmp"' EXIT
expected='493b2b9e1ac83d755a77b24d031affb6a0ba05ac5cfeea0c9aff16ad054a4025'
if [[ ! -f "$archive" ]]; then
    mkdir -p "$(dirname "$archive")"
    parts=("$project_dir"/Resources/Lexicon/parts/lexicon.sqlite3.gz.part-*)
    if [[ -e "${parts[0]}" ]]; then
        cat "${parts[@]}" > "$archive_tmp"
    else
        curl --fail --location --progress-bar \
            'https://github.com/TiDazai/Shoev-Spell/releases/download/v0.1.0/lexicon.sqlite3.gz' \
            --output "$archive_tmp"
    fi
    [[ "$(shasum -a 256 "$archive_tmp" | awk '{print $1}')" == "$expected" ]] || { echo 'Invalid or incomplete lexicon archive' >&2; exit 1; }
    mv "$archive_tmp" "$archive"
fi
[[ "$(shasum -a 256 "$archive" | awk '{print $1}')" == "$expected" ]] || { echo 'Invalid lexicon archive' >&2; exit 1; }
if [[ ! -f "$target" || "$archive" -nt "$target" ]]; then
    gzip -dc "$archive" > "$target_tmp"
    sqlite3 "$target_tmp" 'PRAGMA quick_check;' | grep -qx ok
    mv "$target_tmp" "$target"
fi
sqlite3 "$target" 'PRAGMA quick_check;' | grep -qx ok
