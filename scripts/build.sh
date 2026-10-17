#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
app_path="$PWD/build/Build/Products/Debug/Zone.app"
# Bundle IDs are configurable; discard only the generated app so old embedded
# extensions from a previous ID cannot remain in the next product.
rm -rf -- "$app_path"
xcodebuild -jobs "${ZONE_BUILD_JOBS:-2}" -project Zone.xcodeproj -scheme Zone -configuration Debug -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
# Local UI/app-blocker build: deliberately omits restricted entitlements. The UI
# detects missing provisioning and never tries to activate an unsigned extension.
for extension_path in "$app_path/Contents/Library/SystemExtensions/"*.systemextension; do
  codesign --force --sign - "$extension_path"
done
codesign --force --sign - --entitlements Resources/Zone-Local.entitlements "$app_path"
./scripts/validate-bundle.sh "$app_path"
printf '\nBuilt %s\n' "$app_path"
