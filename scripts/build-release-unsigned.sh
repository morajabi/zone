#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

: "${ZONE_RELEASE_BUNDLE_ID:?Set ZONE_RELEASE_BUNDLE_ID to the app identifier in your release profiles.}"
: "${ZONE_RELEASE_TEAM_ID:?Set ZONE_RELEASE_TEAM_ID to your Apple Developer team identifier.}"
if [[ ! "$ZONE_RELEASE_BUNDLE_ID" =~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' ]] ||
   [[ ! "$ZONE_RELEASE_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]]; then
  print -u2 'Invalid release bundle identifier or team identifier.'
  exit 1
fi
if [[ -e Config/Signing.xcconfig || -L Config/Signing.xcconfig ]]; then
  print -u2 'Use a clean checkout without Config/Signing.xcconfig. This build must not use private signing configuration.'
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  print -u2 'Commit the release sources first. The unsigned artifact must come from a clean checkout.'
  exit 1
fi

source_revision="$(git rev-parse HEAD)"
app_group="$ZONE_RELEASE_TEAM_ID.$ZONE_RELEASE_BUNDLE_ID"
derived_path="$PWD/build/release-unsigned"
app_path="$derived_path/Build/Products/Release/Zone.app"
artifact_dir="$PWD/build/release-artifacts"
mkdir -p "$artifact_dir"
# XcodeGen resolves the extension product reference while generating the
# project. Command-line build settings alone leave that reference at the public
# placeholder ID. Generate a temporary spec with a concrete product name and
# public identity metadata; never create or read a private signing config.
generation_dir="$(mktemp -d "$PWD/build/zone-release-spec.XXXXXX")"
trap 'rm -rf -- "$generation_dir"' EXIT
ruby -rjson -rpsych -e '
  spec = Psych.load_file(ARGV[0])
  bundle_id = ENV.fetch("ZONE_RELEASE_BUNDLE_ID")
  team = ENV.fetch("ZONE_RELEASE_TEAM_ID")
  app_group = "#{team}.#{bundle_id}"
  spec.fetch("settings").fetch("base").merge!({
    "DEVELOPMENT_TEAM" => team,
    "ZONE_BUNDLE_ID" => bundle_id,
    "ZONE_FILTER_BUNDLE_ID" => "#{bundle_id}.filter",
    "ZONE_APP_GROUP" => app_group,
    "ZONE_MACH_SERVICE" => "#{app_group}.filter"
  })
  filter = spec.fetch("targets").fetch("ZoneFilter")
  filter["productName"] = "#{bundle_id}.filter"
  filter.fetch("settings").fetch("base")["PRODUCT_NAME"] = "#{bundle_id}.filter"
  File.write(ARGV[1], JSON.pretty_generate(spec))
' project.yml "$generation_dir/project.json"
xcodegen generate --spec "$generation_dir/project.json" --project-root "$PWD" --project "$PWD"
rm -rf -- "$generation_dir"
trap - EXIT
python3 - "$ZONE_RELEASE_BUNDLE_ID" <<'PY'
import json, subprocess, sys

project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", "Zone.xcodeproj/project.pbxproj"
]))
objects = project["objects"]
target = next(value for value in objects.values() if value.get("isa") == "PBXNativeTarget" and value.get("name") == "ZoneFilter")
product = objects[target["productReference"]]["path"]
expected = f"{sys.argv[1]}.filter.systemextension"
if product != expected:
    raise SystemExit(f"Generated extension product mismatch: expected {expected!r}, got {product!r}")
PY
# Remove only the previous generated product, including any extension with an old ID.
rm -rf -- "$app_path"
xcodebuild -jobs "${ZONE_BUILD_JOBS:-2}" \
  -project Zone.xcodeproj -scheme Zone -configuration Release \
  -derivedDataPath "$derived_path" -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM="$ZONE_RELEASE_TEAM_ID" \
  ZONE_BUNDLE_ID="$ZONE_RELEASE_BUNDLE_ID" \
  ZONE_FILTER_BUNDLE_ID="$ZONE_RELEASE_BUNDLE_ID.filter" \
  ZONE_APP_GROUP="$app_group" ZONE_MACH_SERVICE="$app_group.filter" \
  ZONE_APP_PROFILE='' ZONE_FILTER_PROFILE='' build

./scripts/validate-bundle.sh "$app_path"
python3 - "$app_path" "$source_revision" "$ZONE_RELEASE_TEAM_ID" "$ZONE_RELEASE_BUNDLE_ID" <<'PY'
import pathlib, plistlib, subprocess, sys

app, revision, team, bundle_id = sys.argv[1:]
app = pathlib.Path(app)
extension = app / "Contents/Library/SystemExtensions" / f"{bundle_id}.filter.systemextension"
for bundle, identifier in ((app, bundle_id), (extension, f"{bundle_id}.filter")):
    info_path = bundle / "Contents/Info.plist"
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    expected = {
        "CFBundleIdentifier": identifier,
        "ZoneAppBundleIdentifier": bundle_id,
        "ZoneFilterBundleIdentifier": f"{bundle_id}.filter",
        "ZoneTeamIdentifier": team,
        "ZoneMachService": f"{team}.{bundle_id}.filter",
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise SystemExit(f"Unexpected {key} in {bundle.name}: {info.get(key)!r}")
    executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise SystemExit(f"Expected both Mac architectures in {bundle.name}, got {architectures}")
    info["ZoneSourceRevision"] = revision
    with info_path.open("wb") as output:
        plistlib.dump(info, output)
PY

# Wrap the bundle before upload-artifact so executability, symlinks, and bundle
# structure survive the artifact service's own archive format.
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$artifact_dir/Zone-unsigned.zip"
python3 - "$app_path" "$artifact_dir" "$source_revision" <<'PY'
import hashlib, json, os, pathlib, plistlib, subprocess, sys

app, artifact_dir, revision = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
archive = artifact_dir / "Zone-unsigned.zip"
digest = hashlib.sha256()
with archive.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
manifest = {
    "schema_version": 1,
    "source_revision": revision,
    "repository": os.environ.get("GITHUB_REPOSITORY"),
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID"),
    "workflow_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "bundle_id": info["CFBundleIdentifier"],
    "team_id": info["ZoneTeamIdentifier"],
    "mach_service": info["ZoneMachService"],
    "architectures": ["arm64", "x86_64"],
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "archive": archive.name,
    "archive_sha256": digest.hexdigest(),
    "signed": False,
}
with (artifact_dir / "build-manifest.json").open("w") as output:
    json.dump(manifest, output, indent=2)
    output.write("\n")
PY
printf '\nUnsigned universal release artifact: %s\n' "$artifact_dir/Zone-unsigned.zip"
