# Releasing Zone

Release compilation and tests run on GitHub Actions. Signing, notarization, and packaging use the release maintainer's Mac and existing Keychain identities. There is no local compilation in this workflow, and signing private keys are not uploaded to GitHub.

The app and its optional network extension use the same public bundle identifiers and team metadata throughout the build. Those identifiers must match the existing Developer ID provisioning profiles. Do not change an identifier after compilation: it also determines the extension's executable, Swift provider class, Mach service, and signature checks.

## 1. Build the exact release commit

Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, review the changes, commit, and push. The hosted build requires a clean checkout and records its full source commit in both bundles and in a manifest.

Set these to the identifiers belonging to your release profiles:

```sh
export ZONE_RELEASE_BUNDLE_ID=com.example.Zone
export ZONE_RELEASE_TEAM_ID=YOURTEAMID

gh workflow run release-build.yml --repo morajabi/zone --ref main \
  -f bundle_id="$ZONE_RELEASE_BUNDLE_ID" \
  -f team_id="$ZONE_RELEASE_TEAM_ID"
gh run list --repo morajabi/zone --workflow release-build.yml --limit 5
```

The workflow builds both Apple silicon and Intel slices with Xcode 26.2. It runs the core tests, validates bundle metadata, and uploads a ZIP plus `build-manifest.json`. The ZIP preserves bundle symlinks and executable permissions through the artifact service. The uploaded app is **unsigned**, intended only for the signing step below.

## 2. Download and verify the artifact

Use the successful run ID shown by GitHub. Verify that its `headSha` is the commit you intend to release, rather than automatically picking whichever run happens to be newest.

```sh
run_id=REPLACE_WITH_RUN_ID
gh run view "$run_id" --repo morajabi/zone \
  --json headSha,conclusion,url
export ZONE_RELEASE_SOURCE_SHA=REPLACE_WITH_VERIFIED_FULL_COMMIT_SHA
artifact_dir="build/download-$run_id"
gh run download "$run_id" --repo morajabi/zone \
  --name "zone-unsigned-$ZONE_RELEASE_SOURCE_SHA" --dir "$artifact_dir"

python3 - "$artifact_dir" "$ZONE_RELEASE_SOURCE_SHA" <<'PY'
import hashlib, json, pathlib, sys
directory, expected = pathlib.Path(sys.argv[1]), sys.argv[2]
manifest = json.loads((directory / "build-manifest.json").read_text())
assert manifest["source_revision"] == expected, "Wrong source commit"
assert manifest["archive"] == "Zone-unsigned.zip", "Unexpected artifact name"
archive = directory / "Zone-unsigned.zip"
digest = hashlib.sha256()
with archive.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
assert digest.hexdigest() == manifest["archive_sha256"], "Artifact checksum mismatch"
print("Source commit and archive checksum verified.")
PY

ditto -x -k "$artifact_dir/Zone-unsigned.zip" "$artifact_dir/unpacked"
./scripts/validate-bundle.sh "$artifact_dir/unpacked/Zone.app"
```

## 3. Sign and notarize without rebuilding

Use a valid **Developer ID Application** identity already installed in Keychain. Keep profile files, exported keys, credentials, and `Config/Signing.xcconfig` out of Git. A Mac development profile cannot replace the Developer ID profiles needed by the optional extension.

Set paths to the existing profiles and names of the existing Keychain entries. These variables contain references to local signing material; do not put exported private keys or passwords in them.

```sh
export ZONE_APP_PROFILE_PATH=/path/to/Zone-Developer-ID.provisionprofile
export ZONE_FILTER_PROFILE_PATH=/path/to/Zone-Filter-Developer-ID.provisionprofile
export ZONE_SIGNING_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)'
export ZONE_NOTARY_PROFILE=your-existing-notarytool-profile
app_path="$PWD/build/release-signed/Zone.app"
./scripts/sign-release.sh "$artifact_dir/unpacked/Zone.app" "$app_path"
```

The helper copies the unsigned bundle into a fresh output location, validates profile expiration, team and application identifiers, capabilities, and universal architectures, then derives entitlements from the public resource templates at the exact built commit. That commit must be present in your local Git checkout. It embeds the profiles and signs inside out with hardened runtime and secure timestamps. The signing certificates must be authorized by their profiles. Finally it submits a temporary ZIP to Apple, staples the app's ticket, and checks Gatekeeper. Temporary decoded profiles and entitlement files are removed afterward.

Zone uses the macOS app group `TEAMID.APP_BUNDLE_ID`. Apple authorizes this form through the signing team, so the profiles may omit the app-group entitlement. The helper permits only that exact derived team-prefixed group; any `group.`-prefixed group still needs profile authorization. See [Apple's app-group rules](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).

Continue only after Apple accepts the submission, stapling succeeds, and Gatekeeper accepts the app. Never upload the unsigned Actions artifact as a user download. The script refuses an existing output app; if a previous attempt failed, inspect it before choosing a fresh output path for a retry.

## 4. Package and check the download

Use an output directory that does not already contain release assets:

```sh
./scripts/package-release.sh "$app_path" build/release
```

The helper checks the source revision, universal slices, Developer ID identity, hardened runtime, timestamp, stapled ticket, and Gatekeeper assessment. It creates:

- `Zone-VERSION-macOS-universal.dmg`, containing Zone and an Applications shortcut. The disk image is separately signed, notarized, and stapled.
- `Zone-VERSION-macOS-universal.zip`, containing the already-stapled app. The helper extracts this final ZIP and repeats signature, ticket, and Gatekeeper checks.
- `SHA256SUMS` and `release-manifest.json`, recording asset hashes, sizes, version, build number, and source commit.

Open the final disk image, copy the app into Applications, and exercise the core paths from [the acceptance checklist](acceptance.md). Test a downloaded copy on a separate Mac when available. A valid signature and notarization ticket are necessary distribution checks; they do not replace runtime testing.

## 5. Publish a GitHub release

Create the release from the exact source commit recorded in the artifact. Use a tag matching the version in `project.yml`, and write concise user-facing release notes describing the changes, macOS requirement, installation steps, and known limitations.

```sh
version=REPLACE_WITH_VERSION
gh release create "v$version" \
  "build/release/Zone-$version-macOS-universal.dmg" \
  "build/release/Zone-$version-macOS-universal.zip" \
  build/release/SHA256SUMS build/release/release-manifest.json \
  --repo morajabi/zone --target "$ZONE_RELEASE_SOURCE_SHA" \
  --title "Zone $version" --notes-file build/release-notes.md
```

Download the published assets again with `gh release download`, verify `shasum -a 256 -c SHA256SUMS` from that directory, and confirm the release tag resolves to the recorded commit. The README's download link should point to the public release.

## References

- [GitHub workflow artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data)
- [Apple: creating distribution-signed code](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
- [Apple: packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
