#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/upstream/mgba"
EXPECTED="c3c8e5e813f245028de118a56734e1dc0f35ce2a"
OUT="${1:-$ROOT/build/mgba-modified}"

git -C "$ROOT" submodule update --init --recursive upstream/mgba

ACTUAL="$(git -C "$UPSTREAM" rev-parse HEAD)"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "ERROR: upstream mGBA commit mismatch"
  echo "expected: $EXPECTED"
  echo "actual:   $ACTUAL"
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -a "$UPSTREAM" "$OUT"
rm -rf "$OUT/.git"

cmake \
  -Dmgba_v028_SOURCE_DIR="$OUT" \
  -P "$ROOT/patches/mgba_mpl_modifications.cmake"

echo
echo "Modified mGBA Source Code Form prepared at:"
echo "$OUT"
echo
echo "Affected files:"
cat "$ROOT/MODIFIED_FILES.txt"
