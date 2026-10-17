# Contributing

Keep Zone small, native, and local. Prefer standard SwiftUI/AppKit controls and platform behavior over custom UI. Browser control is the default; the network extension is optional.

## Before submitting a change

1. Run `swift test` and `./scripts/build.sh`.
2. Exercise the affected flow in the app. Use disposable apps and domains such as `example.org` for blocking tests, and remove test schedules afterward.
3. For scheduling or enforcement changes, cover pause, resume, expiry, overlapping sessions, and locked-session behavior. Keep time/calendar logic in `ZoneCore` so it can be tested without permissions.
4. Describe what changed and what was actually tested. A successful build does not prove a browser adapter or network path works.

Edit `project.yml`, not the generated Xcode project. Do not commit `Config/Signing.xcconfig`, provisioning profiles, certificates, app data, build output, or private browsing information. No paid developer account is needed for the normal local build.

Bug reports should include the macOS and Zone versions, affected browser/version, steps to reproduce, and whether browser control or the experimental network filter was selected. Please redact personal domains and window contents from screenshots and logs.
