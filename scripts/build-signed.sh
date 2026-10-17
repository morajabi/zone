#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -f Config/Signing.xcconfig ]]; then
  print -u2 'Copy Config/Signing.xcconfig.example to Config/Signing.xcconfig and set your team and bundle ID.'
  exit 1
fi
xcodegen generate
rm -rf -- "$PWD/build/signed/Build/Products/Release/Zone.app"
provisioning_args=()
if [[ "${1:-}" == "--allow-provisioning" ]]; then
  provisioning_args=(-allowProvisioningUpdates)
elif [[ -n "${1:-}" ]]; then
  print -u2 'Usage: build-signed.sh [--allow-provisioning]'
  exit 1
fi
# Provisioning updates are explicit: this may register this app's identifiers and
# download profiles through the Apple account already configured in Xcode.
xcodebuild -jobs "${ZONE_BUILD_JOBS:-2}" -project Zone.xcodeproj -scheme Zone -configuration Release \
  -derivedDataPath build/signed -destination 'platform=macOS' \
  "${provisioning_args[@]}" build
./scripts/validate-bundle.sh "$PWD/build/signed/Build/Products/Release/Zone.app"
printf '\nBuilt %s\n' "$PWD/build/signed/Build/Products/Release/Zone.app"
