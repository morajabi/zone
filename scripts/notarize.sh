#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${ZONE_NOTARY_PROFILE:?Set ZONE_NOTARY_PROFILE to your existing notarytool Keychain profile name.}"
app_path="$PWD/build/signed/Build/Products/Release/Zone.app"
codesign --verify --deep --strict "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$PWD/build/Zone.zip"
xcrun notarytool submit "$PWD/build/Zone.zip" --keychain-profile "$ZONE_NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
