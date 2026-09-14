#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
archive="$project_dir/Resources/Lexicon/lexicon.sqlite3.gz"
target="$project_dir/Sources/ShoevSpell/Resources/lexicon.sqlite3"
if [[ ! -f "$archive" ]]; then
    mkdir -p "$(dirname "$archive")"
    curl --fail --location --progress-bar \
        'https://github.com/TiDazai/Shoev-Spell/releases/download/v0.1.0/lexicon.sqlite3.gz' \
        --output "$archive"
fi
if [[ ! -f "$target" || "$archive" -nt "$target" ]]; then
    gzip -dc "$archive" > "$target"
fi
sqlite3 "$target" 'PRAGMA quick_check;' | grep -qx ok
