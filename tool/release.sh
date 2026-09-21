#!/usr/bin/env bash
# Release APKs, one per ABI, into releases/<version>/.
# With --publish, also a GitHub release v<version> carrying them — what the
# app's Settings → Check for updates reads, in Ayroid/penny-releases.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d+ -f1)
out="releases/$version"
# Android installs an update only over a lower versionCode, and a forgotten
# `+N` bump fails on the phone, not here. So the code comes from the version
# itself: 0.2.3 -> 203, 1.4.0 -> 10400.
IFS=. read -r major minor patch <<<"$version"
build_number=$((major * 10000 + minor * 100 + patch))

# A release nobody can install is not a release: without key.properties the
# Gradle config falls back to the debug key, and an APK signed with it cannot
# be updated later by a properly signed one.
if [ ! -f android/key.properties ]; then
  echo "android/key.properties is missing — release builds would be signed with the debug key." >&2
  echo "Make a keystore first:" >&2
  echo "  keytool -genkey -v -keystore android/penny-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias penny" >&2
  exit 1
fi

if [ -d "$out" ]; then
  echo "releases/$version already exists — bump 'version:' in pubspec.yaml first." >&2
  exit 1
fi

flutter build apk --split-per-abi --release --build-number="$build_number" \
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
echo "Signed with android/penny-release.jks — back that file up."

if [ "${1:-}" = "--publish" ]; then
  # The source is private, so the release lives in a public repo of its own
  # and the tag stays here. Notes are the commit subjects since the last tag.
  prev=$(git describe --tags --abbrev=0 2>/dev/null || true)
  notes=$(git log --format='- %s' ${prev:+"$prev"..}HEAD)
  git tag "v$version"
  git push -q origin "v$version"
  gh release create "v$version" "$out"/*.apk --repo Ayroid/penny-releases \
    --title "Penny $version" --notes "$notes"
fi
