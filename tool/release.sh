#!/usr/bin/env bash
# Release APKs, one per ABI, into releases/<version>/.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d+ -f1)
out="releases/$version"

if [ -d "$out" ]; then
  echo "releases/$version already exists — bump 'version:' in pubspec.yaml first." >&2
  exit 1
fi

flutter build apk --split-per-abi --release \
  --obfuscate --split-debug-info="symbols/$version"

mkdir -p "$out"
for abi in armeabi-v7a arm64-v8a x86_64; do
  src="build/app/outputs/flutter-apk/app-$abi-release.apk"
  [ -f "$src" ] && cp "$src" "$out/penny-$version-$abi.apk"
done

echo
echo "Built into $out:"
ls -la "$out"
echo
echo "Hand out the arm64-v8a one unless you know otherwise."
