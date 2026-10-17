#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

input_app="${1:?Usage: sign-release.sh /path/to/unsigned/Zone.app [signed-output-app]}"
input_app="${input_app:A}"
output_app="${2:-$PWD/build/release-signed/Zone.app}"
output_app="${output_app:A}"
: "${ZONE_APP_PROFILE_PATH:?Set ZONE_APP_PROFILE_PATH to the existing Developer ID app provisioning profile.}"
: "${ZONE_FILTER_PROFILE_PATH:?Set ZONE_FILTER_PROFILE_PATH to the existing Developer ID filter provisioning profile.}"
: "${ZONE_SIGNING_IDENTITY:?Set ZONE_SIGNING_IDENTITY to your existing Developer ID Application Keychain identity.}"
: "${ZONE_NOTARY_PROFILE:?Set ZONE_NOTARY_PROFILE to your existing notarytool Keychain profile name.}"
: "${ZONE_RELEASE_SOURCE_SHA:?Set ZONE_RELEASE_SOURCE_SHA to the verified hosted build commit.}"
if [[ ! -f "$ZONE_APP_PROFILE_PATH" || ! -f "$ZONE_FILTER_PROFILE_PATH" ]]; then
  print -u2 'Both provisioning profiles must exist.'
  exit 1
fi
if [[ -e "$output_app" ]]; then
  print -u2 "Output already exists: $output_app. Use a fresh output path."
  exit 1
fi
./scripts/validate-bundle.sh "$input_app"

mkdir -p "$PWD/build" "${output_app:h}"
signing_dir="$(mktemp -d "$PWD/build/zone-signing.XXXXXX")"
chmod 700 "$signing_dir"
trap 'rm -rf -- "$signing_dir"' EXIT
security cms -D -i "$ZONE_APP_PROFILE_PATH" -o "$signing_dir/app-profile.plist"
security cms -D -i "$ZONE_FILTER_PROFILE_PATH" -o "$signing_dir/filter-profile.plist"
python3 - "$input_app" "$signing_dir" "$ZONE_RELEASE_SOURCE_SHA" <<'PY'
import datetime, hashlib, json, pathlib, plistlib, re, subprocess, sys

app, temporary, revision = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
if not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit("Expected a complete source commit SHA.")
with (app / "Contents/Info.plist").open("rb") as source:
    app_info = plistlib.load(source)
team, app_id = app_info["ZoneTeamIdentifier"], app_info["CFBundleIdentifier"]
if not re.fullmatch(r"[A-Z0-9]{10}", team):
    raise SystemExit("Missing or invalid team metadata in hosted app.")
app_group = f"{team}.{app_id}"
extension = app / "Contents/Library/SystemExtensions" / f"{app_id}.filter.systemextension"
certificates = {}
for kind, bundle, bundle_id, template in (
    ("app", app, app_id, "Resources/Zone.entitlements"),
    ("filter", extension, f"{app_id}.filter", "Resources/ZoneFilter.entitlements"),
):
    with (bundle / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    for key, expected in {
        "CFBundleIdentifier": bundle_id,
        "ZoneTeamIdentifier": team,
        "ZoneAppBundleIdentifier": app_id,
        "ZoneFilterBundleIdentifier": f"{app_id}.filter",
        "ZoneMachService": f"{app_group}.filter",
        "ZoneSourceRevision": revision,
    }.items():
        if info.get(key) != expected:
            raise SystemExit(f"Unexpected {key} in {bundle.name}.")
    executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise SystemExit(f"Expected a universal executable in {bundle.name}.")
    with (temporary / f"{kind}-profile.plist").open("rb") as source:
        profile = plistlib.load(source)
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime.datetime) or expires.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise SystemExit(f"The {kind} provisioning profile is expired or has no expiration date.")
    if team not in profile.get("TeamIdentifier", []):
        raise SystemExit(f"Wrong team in the {kind} provisioning profile.")
    if not profile.get("ProvisionsAllDevices") or profile.get("ProvisionedDevices"):
        raise SystemExit(f"The {kind} profile must support Developer ID distribution to all Macs.")
    allowed = profile["Entitlements"]
    application_identifier = f"{team}.{bundle_id}"
    if allowed.get("com.apple.application-identifier") != application_identifier:
        raise SystemExit(f"Wrong app identifier in the {kind} provisioning profile.")
    if allowed.get("com.apple.developer.team-identifier") != team:
        raise SystemExit(f"Wrong entitlement team in the {kind} provisioning profile.")
    # Read the exact built commit, so later edits to local signing templates
    # cannot silently change a release artifact's requested capabilities.
    source_template = subprocess.check_output(["git", "show", f"{revision}:{template}"], text=True)
    resolved_template = source_template.replace("$(ZONE_APP_GROUP)", app_group)
    if "$(" in resolved_template:
        raise SystemExit(f"Unresolved build setting in {template}.")
    entitlements = plistlib.loads(resolved_template.encode())
    entitlements["com.apple.application-identifier"] = application_identifier
    entitlements["com.apple.developer.team-identifier"] = team
    for key, requested in entitlements.items():
        restricted = key.startswith("com.apple.developer.") or key in (
            "com.apple.security.application-groups", "com.apple.application-identifier"
        )
        if not restricted:
            continue
        authorized = allowed.get(key)
        if key == "com.apple.security.application-groups" and isinstance(requested, list):
            # macOS authorizes TEAMID-prefixed groups through the signing team,
            # without a provisioning-profile entry. Exempt only the exact group
            # derived from this artifact; registered group.* IDs still require
            # profile authorization, and unrelated team-prefixed IDs are refused.
            requested = [item for item in requested if item != app_group]
            if any(not isinstance(item, str) or not item.startswith("group.") for item in requested):
                raise SystemExit(f"Unexpected app group in the {kind} entitlements.")
            if not requested:
                continue
        if isinstance(requested, list):
            matches = isinstance(authorized, list) and all(item in authorized for item in requested)
        else:
            matches = requested == authorized
        if not matches:
            raise SystemExit(f"The {kind} profile does not authorize the requested {key} entitlement.")
    with (temporary / f"{kind}.entitlements").open("wb") as output:
        plistlib.dump(entitlements, output)
    certificates[kind] = [hashlib.sha256(cert).hexdigest() for cert in profile.get("DeveloperCertificates", [])]
    if not certificates[kind]:
        raise SystemExit(f"The {kind} profile has no signing certificates.")
with (temporary / "profile-certificates.json").open("w") as output:
    json.dump(certificates, output)
PY

ditto "$input_app" "$output_app"
filter_id="$(/usr/libexec/PlistBuddy -c 'Print :ZoneFilterBundleIdentifier' "$output_app/Contents/Info.plist")"
filter_path="$output_app/Contents/Library/SystemExtensions/$filter_id.systemextension"
cp "$ZONE_APP_PROFILE_PATH" "$output_app/Contents/embedded.provisionprofile"
cp "$ZONE_FILTER_PROFILE_PATH" "$filter_path/Contents/embedded.provisionprofile"

# The current app has no third-party frameworks. Also sign any Swift support
# libraries or future embedded frameworks, from the inside out, if present.
python3 - "$output_app" "$ZONE_SIGNING_IDENTITY" <<'PY'
import os, pathlib, plistlib, subprocess, sys

app, identity = pathlib.Path(sys.argv[1]), sys.argv[2]
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
extension = app / "Contents/Library/SystemExtensions" / f"{info['ZoneFilterBundleIdentifier']}.systemextension"
with (extension / "Contents/Info.plist").open("rb") as source:
    extension_info = plistlib.load(source)
main_executables = {
    (app / "Contents/MacOS" / info["CFBundleExecutable"]).resolve(),
    (extension / "Contents/MacOS" / extension_info["CFBundleExecutable"]).resolve(),
}
magic_numbers = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"
)}
items = set()
for directory, subdirectories, files in os.walk(app, followlinks=False):
    for name in files:
        path = pathlib.Path(directory) / name
        if path.is_symlink() or path.resolve() in main_executables:
            continue
        with path.open("rb") as source:
            magic = source.read(4)
        if magic in magic_numbers:
            items.add(path)
    for name in subdirectories:
        path = pathlib.Path(directory) / name
        if path.suffix == ".framework" and not path.is_symlink():
            items.add(path)
for path in sorted(items, key=lambda path: len(path.parts), reverse=True):
    subprocess.run(["codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp", str(path)], check=True)
PY
codesign --force --sign "$ZONE_SIGNING_IDENTITY" --options runtime --timestamp \
  --entitlements "$signing_dir/filter.entitlements" "$filter_path"
codesign --force --sign "$ZONE_SIGNING_IDENTITY" --options runtime --timestamp \
  --entitlements "$signing_dir/app.entitlements" "$output_app"

# Check that the actual signing certificate is authorized by each profile.
python3 - "$output_app" "$filter_path" "$signing_dir" <<'PY'
import hashlib, json, pathlib, subprocess, sys

app, extension, temporary = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
authorized = json.loads((temporary / "profile-certificates.json").read_text())
for kind, bundle in (("app", app), ("filter", extension)):
    prefix = str(temporary / f"{kind}-certificate-")
    subprocess.run(["codesign", "--display", "--extract-certificates", prefix, str(bundle)], check=True)
    certificate = pathlib.Path(prefix + "0").read_bytes()
    if hashlib.sha256(certificate).hexdigest() not in authorized[kind]:
        raise SystemExit(f"The signing certificate is not authorized by the {kind} provisioning profile.")
    signature = subprocess.check_output(["codesign", "-dvv", str(bundle)], stderr=subprocess.STDOUT, text=True)
    if "Authority=Developer ID Application:" not in signature or "runtime" not in signature or "Timestamp=" not in signature:
        raise SystemExit(f"Expected a timestamped Developer ID signature with hardened runtime in {bundle.name}.")
PY
codesign --verify --deep --strict "$output_app"
ditto -c -k --sequesterRsrc --keepParent "$output_app" "$signing_dir/Zone-notary-submission.zip"
xcrun notarytool submit "$signing_dir/Zone-notary-submission.zip" \
  --keychain-profile "$ZONE_NOTARY_PROFILE" --wait
xcrun stapler staple "$output_app"
xcrun stapler validate "$output_app"
spctl --assess --type execute --verbose=2 "$output_app"
printf '\nSigned, notarized, and stapled app: %s\n' "$output_app"
