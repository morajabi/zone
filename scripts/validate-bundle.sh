#!/bin/zsh
set -euo pipefail
app_path="${1:?Usage: validate-bundle.sh /path/to/Zone.app}"
app_info="$app_path/Contents/Info.plist"
read_key() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
require_equal() {
  if [[ "$1" != "$2" ]]; then
    print -u2 "Invalid bundle: $3 (expected '$2', got '$1')"
    exit 1
  fi
}
require_equal "$(read_key "$app_info" CFBundlePackageType)" APPL 'app package type'
filter_id="$(read_key "$app_info" ZoneFilterBundleIdentifier)"
filter_path="$app_path/Contents/Library/SystemExtensions/$filter_id.systemextension"
filter_info="$filter_path/Contents/Info.plist"
require_equal "$(read_key "$filter_info" CFBundlePackageType)" SYSX 'system extension package type'
require_equal "$(read_key "$filter_info" CFBundleIdentifier)" "$filter_id" 'extension identifier'
require_equal "$(read_key "$filter_info" ZoneAppBundleIdentifier)" "$(read_key "$app_info" CFBundleIdentifier)" 'containing app identifier'
require_equal "$(read_key "$filter_info" CFBundleVersion)" "$(read_key "$app_info" CFBundleVersion)" 'extension build version'
require_equal "$(read_key "$filter_info" NetworkExtension:NEMachServiceName)" "$(read_key "$app_info" ZoneMachService)" 'Mach service'
provider_class="$(read_key "$filter_info" NetworkExtension:NEProviderClasses:com.apple.networkextension.filter-data)"
[[ "$provider_class" == *.FilterDataProvider && "$provider_class" != *'$('* ]] || { print -u2 'Invalid filter provider class'; exit 1; }
[[ -x "$filter_path/Contents/MacOS/$(read_key "$filter_info" CFBundleExecutable)" ]] || { print -u2 'Missing filter executable'; exit 1; }
print 'App and system extension bundle metadata verified.'
