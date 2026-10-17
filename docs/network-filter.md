# Optional network filter

The extension uses Apple's Network Extension content-filter API. A real provisioning profile and macOS approval are required; ad-hoc code signing cannot activate it.

1. Run `xcodegen generate` and open `Zone.xcodeproj`.
2. Copy `Config/Signing.xcconfig.example` to `Config/Signing.xcconfig` and enter your paid Apple Developer team and a unique `ZONE_BUNDLE_ID`. This local file is gitignored. `Config/Base.xcconfig` contains public defaults; the app, extension, app group, Mach service, and XPC signature requirements all derive from those settings.
3. Create Developer ID profiles authorizing `content-filter-provider-systemextension` for both targets and System Extension installation for the app. Put their names in `ZONE_APP_PROFILE` and `ZONE_FILTER_PROFILE`. The app group is `TEAMID.YOUR_BUNDLE_ID`; the Mach service adds `.filter`. Ordinary development profiles may contain `content-filter-provider` without the suffix and cannot sign this direct-distribution variant.
4. Build through Xcode, or run `./scripts/build-signed.sh`. To explicitly permit Xcode to register app identifiers/download profiles, use `--allow-provisioning`. No signing material belongs in the repository.
5. Notarize the Developer ID build. With credentials already stored by `notarytool`, run `ZONE_NOTARY_PROFILE=your-profile ./scripts/notarize.sh`. This explicitly uploads the built app to Apple's notarization service and staples the ticket; it does not publish the app.
6. Place the signed app in `/Applications`, launch it, and select **Settings → Websites → Network filter → Enable Website Filter**. Approve the system extension and the network filter in macOS.
7. Verify the browser cases in [the acceptance checklist](acceptance.md) before depending on it.

The extension accepts policy updates only from an Apple-signed Zone app with the same signing team. The app also validates the provider's signing identity. Policies are saved in Network Extension preferences for restart and delivered by XPC for live updates. “Connected” requires a provider response, not just a saved preferences flag.

## Enforcement boundaries

App blocking **closes apps just after they launch**. It does not deny an executable before it starts. Strong pre-execution denial requires an Endpoint Security extension and Apple's restricted entitlement. Force-quitting Zone bypasses app blocking. Locked mode is a commitment enforced by Zone's controls, not tamper-proof parental control.

The optional network filter evaluates macOS connection hostnames and, where needed, HTTP Host / TLS ClientHello server-name metadata. Rules include subdomains. It never intercepts certificates or decrypts HTTPS, and does not save browsing data.

While a website session is active, unknown-host UDP/443 connections are dropped to encourage HTTP/3 clients to retry TCP. Encrypted ClientHello, opaque VPN/proxy tunnels, unusual ports, cached offline pages, and unidentified connections remain coverage gaps. Established connections with known hosts are tracked in bounded memory and reevaluated when rules change; already-open unknown-host QUIC connections are not covered. A domain network filter also cannot distinguish paths on a shared connection. Universal browser coverage is **not claimed**.

In network mode, website schedules can continue inside the enabled extension while the UI app is closed. Browser control and app schedules need Zone running. Switching blocking methods is disabled while a website session is active, and switching to browser control turns the network filter off. Turning off a schedule affects future occurrences; an already-started session continues. A user can remove the filter through macOS even during a locked session.
