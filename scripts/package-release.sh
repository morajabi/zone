#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

app_path="${1:?Usage: package-release.sh /path/to/signed-and-stapled/Zone.app [output-directory]}"
app_path="${app_path:A}"
output_dir="${2:-$PWD/build/release}"
output_dir="${output_dir:A}"
: "${ZONE_SIGNING_IDENTITY:?Set ZONE_SIGNING_IDENTITY to your existing Developer ID Application signing identity.}"
: "${ZONE_NOTARY_PROFILE:?Set ZONE_NOTARY_PROFILE to your existing notarytool Keychain profile name.}"
: "${ZONE_RELEASE_SOURCE_SHA:?Set ZONE_RELEASE_SOURCE_SHA to the verified hosted build commit.}"

./scripts/validate-bundle.sh "$app_path"
python3 - "$app_path" "$ZONE_RELEASE_SOURCE_SHA" <<'PY'
import pathlib, plistlib, re, subprocess, sys

app, revision = pathlib.Path(sys.argv[1]), sys.argv[2]
if not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit("Expected a complete source commit SHA.")
with (app / "Contents/Info.plist").open("rb") as source:
    app_info = plistlib.load(source)
extension = app / "Contents/Library/SystemExtensions" / f"{app_info['ZoneFilterBundleIdentifier']}.systemextension"
for bundle in (app, extension):
    with (bundle / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info.get("ZoneSourceRevision") != revision:
        raise SystemExit(f"Source revision mismatch in {bundle.name}.")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", info["CFBundleShortVersionString"]):
        raise SystemExit("Expected a numeric release version.")
    executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise SystemExit(f"Expected a universal binary in {bundle.name}.")
    signature = subprocess.check_output(["codesign", "-dvv", str(bundle)], stderr=subprocess.STDOUT, text=True)
    if "Authority=Developer ID Application:" not in signature:
        raise SystemExit(f"Expected Developer ID Application signing in {bundle.name}.")
    if f"TeamIdentifier={info['ZoneTeamIdentifier']}\n" not in signature:
        raise SystemExit(f"Signing team does not match build metadata in {bundle.name}.")
    if "runtime" not in signature or "Timestamp=" not in signature:
        raise SystemExit(f"Expected hardened runtime and secure timestamp in {bundle.name}.")
PY
codesign --verify --deep --strict "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
asset_name="Zone-$version-macOS-universal"
mkdir -p "$output_dir"
for asset in "$asset_name.zip" "$asset_name.dmg" SHA256SUMS release-manifest.json; do
  if [[ -e "$output_dir/$asset" ]]; then
    print -u2 "Output already exists: $output_dir/$asset. Use a fresh output directory."
    exit 1
  fi
done

mkdir -p "$PWD/build"
staging_dir="$(mktemp -d "$PWD/build/zone-package.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
mkdir "$staging_dir/image"
ditto "$app_path" "$staging_dir/image/Zone.app"
ln -s /Applications "$staging_dir/image/Applications"
cat > "$staging_dir/image/Install Zone.txt" <<'TEXT'
Drag Zone into Applications, then open it from Applications.

Zone lives in your menu bar. Add a block list, connect the browsers you use in
Settings → Websites, and start a focus session.

Requires macOS 15 or later. Supports Apple silicon and Intel Macs.
https://github.com/morajabi/zone
TEXT

# ZIPs cannot carry their own stapled ticket. Archive the already-stapled app.
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_dir/$asset_name.zip"
hdiutil create -quiet -volname Zone -srcfolder "$staging_dir/image" \
  -format UDZO "$output_dir/$asset_name.dmg"
codesign --force --sign "$ZONE_SIGNING_IDENTITY" --timestamp \
  --identifier "$bundle_id.diskimage" "$output_dir/$asset_name.dmg"
xcrun notarytool submit "$output_dir/$asset_name.dmg" \
  --keychain-profile "$ZONE_NOTARY_PROFILE" --wait
xcrun stapler staple "$output_dir/$asset_name.dmg"
xcrun stapler validate "$output_dir/$asset_name.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$output_dir/$asset_name.dmg"

# Verify the archive users actually receive, not just its source bundle.
ditto -x -k "$output_dir/$asset_name.zip" "$staging_dir/unpacked"
codesign --verify --deep --strict "$staging_dir/unpacked/Zone.app"
xcrun stapler validate "$staging_dir/unpacked/Zone.app"
spctl --assess --type execute --verbose=2 "$staging_dir/unpacked/Zone.app"
python3 - "$app_path" "$output_dir" "$ZONE_RELEASE_SOURCE_SHA" "$asset_name" <<'PY'
import hashlib, json, pathlib, plistlib, sys

app, output, revision, asset_name = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
assets = {}
for suffix in ("dmg", "zip"):
    asset = output / f"{asset_name}.{suffix}"
    digest = hashlib.sha256()
    with asset.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    assets[asset.name] = {"sha256": digest.hexdigest(), "bytes": asset.stat().st_size}
with (output / "SHA256SUMS").open("w") as checksums:
    for name, details in assets.items():
        checksums.write(f"{details['sha256']}  {name}\n")
manifest = {
    "schema_version": 1,
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "source_revision": revision,
    "bundle_id": info["CFBundleIdentifier"],
    "architectures": ["arm64", "x86_64"],
    "minimum_macos": info["LSMinimumSystemVersion"],
    "developer_id_signed": True,
    "notarized_and_stapled": True,
    "assets": assets,
}
with (output / "release-manifest.json").open("w") as destination:
    json.dump(manifest, destination, indent=2)
    destination.write("\n")
PY
printf '\nVerified release assets: %s\n' "$output_dir"
