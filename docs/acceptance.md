# Acceptance evidence

## UI polish pass — October 17, 2026

- Version 0.1.0 (10) is signed, notarized, stapled, and installed locally. Both arm64 and x86_64 Release targets compiled.
- A separate public-source copy built without private signing configuration, using the placeholder bundle IDs.
- All 23 core tests passed.
- Focus opens the first block-list editor directly. Saving a pending domain adds it without a separate Add click.
- Invalid duration text disables Start; selecting a preset restores a valid value.
- Settings opens as a separate native window through Command-comma. General and Websites panes were visually inspected.
- Connect opens a closed Safari and confirms its existing Automation permission; Chrome and Dia show connected.
- Website schedules default to enabled when browser control is connected. Enabled weekly and one-time schedules save; editing reopens the saved values. No weekdays disables Save with an inline explanation.
- Block-list Websites/Apps controls, schedule day controls, Focus layout, and Settings were visually inspected on the built-in display.
- Safari redirected an existing page, released it during a one-minute pause, then redirected automatically at pause expiry. The pause allowance reached zero.
- Build scripts now default to two concurrent Xcode jobs; further build verification runs in GitHub Actions.

## Earlier enforcement baseline — build 8

- 23 core tests passed (including nine invalid-domain cases in a parameterized test).
- Both app and system extension compiled for arm64 and x86_64 in the Developer ID Release build.
- A separate source copy with no `Signing.xcconfig` built successfully with the public placeholder IDs.
- The signed build passed strict recursive code-signature verification; Apple notarization returned Accepted.
- The stapled app passed Gatekeeper assessment; version 0.1.0 (8) was installed at `/Applications/Zone.app`.
- The menu bar, Focus, block-list editor, app picker, and Settings controls have been exercised through Accessibility. Replacing the Focus GroupBox with a contained section resolved the automation service's traversal crash.
- A disposable app closed at session start, opened during a one-minute pause, and closed automatically when the pause expired. The allowance fell to zero; a relaunch during the resumed session was closed. Flexible early ending was exercised.
- A one-minute locked session hid End and disabled Quit, then expired normally. Disabled weekly and one-time schedules were saved and reopened with their settings preserved.
- Chrome and Dia redirected existing `example.org` tabs to the bundled local page. Chrome's background tab redirected while its unrelated `example.com` tab remained open. Fresh Chrome navigation also redirected.
- A one-minute pause allowed both browsers to open the blocked domain. Automatic resume redirected both again and exhausted the pause allowance. Session expiry restored access in both.
- Safari Automation access was confirmed. Existing tabs and fresh navigation redirected; pausing released the page, early resume redirected it again without refunding the pause, and ending the session restored access.
- The menu-bar popover opened Settings successfully.
- Browser workers are isolated by browser, and permission requests use a separate worker. Safari's unresolved Automation access did not prevent Chrome and Dia enforcement in the final build. Timers now use the common run-loop modes so open menus do not suspend periodic checks.
- The initial system-extension activation failed because the generated Info.plist omitted `CFBundlePackageType=SYSX`. Both build scripts now validate the built bundles. Version 0.1.0 (3) activated and the provider replied through XPC.
- Network filtering was then turned off when browser control became the requested default. Switching methods was exercised on build 8; the optional network mode showed the filter off, and Browser control was restored as the saved selection.
- Test lists, schedules, and browser windows were removed. No session remains active; quick-session defaults are 25 minutes with one five-minute pause.

Arc, Brave, Edge, and Opera adapters are implemented but not runtime-qualified. Safari natural session expiry has not yet been separately exercised. Network traffic blocking has not been qualified.

## Automated

Run `swift test`. Tests cover:

- Valid domain normalization; path, credentials and malformed input rejection; suffix boundaries.
- Half-open session intervals and returning from sleep after expiry.
- Locked stop rejection, pause budgets, early resume, automatic expiry and end-time clamping.
- Combined restrictions from overlapping sessions.
- Overnight weekday ownership, one-off catch-up, next-week occurrence calculation.
- Spring-forward and fall-back calendar behavior.
- Stopped recurring sessions not restarting during the same occurrence.
- Active snapshots surviving edits to their original list/schedule.
- Atomic JSON round-trip and preserving corrupt storage.
- HTTP metadata, partial TLS ClientHello, fragmented TLS records, ECH handling and malformed input bounds.
- Browser URL boundaries, local/internal page exclusion, immediate policy updates, pause expiry, stop, mode changes, and clock-independent session expiry.

## Local app

The unsigned-development build deliberately contains no activated system extension. Verify UI/app behavior with a disposable app containing no user work:

- Add/edit/remove a list and select the disposable app.
- Start flexible mode; app closes and relaunch closes again.
- Pause; app can run; resume closes it again. Confirm pause allowance decreases.
- End flexible session; app is available again.
- Start a short locked session; End and Quit unavailable; expiry restores access.
- Save a disabled schedule; edit days, overnight times and pause settings; reopen to verify persistence.
- Close the management window and reopen from the menu bar.

## Browser control — remaining validation

- Connect each browser and verify denied permission is explained.
- Repeat the Chrome/Dia checks in Arc, Brave, Edge, and Opera; check natural session expiry in Safari.
- Multiple profiles, private windows, and tabs closing mid-scan.
- Early resume in Chrome/Dia, overlapping browser sessions, scheduled browser sessions, and sleep/wake.
- CPU usage with many windows and tabs.

## Optional network extension — remaining validation

- Each of Safari, Chrome, Firefox, Brave, Edge, Arc/Dia: fresh navigation, an existing tab, private mode and background tabs.
- System DNS vs secure DNS; ECH enabled/disabled; HTTP/2 vs HTTP/3; IPv4/IPv6; connected VPN and proxy behavior.
- Root domain and subdomains block; sibling domains remain reachable.
- Session start with existing connections, pause/resume, exact end, overlapping sessions.
- Sleep/wake, network changes, app restart, provider restart and system restart.
- Filter revoked or provider crash: UI reports degraded state and does not claim protection.
- Other network filters and 1Focus remain functional; no changes to their configuration.
- CPU, memory and latency under ordinary browsing.

Known gaps in the README must be resolved or accepted before treating this as an all-browser replacement. Successful compilation or an XPC response alone is not website-blocking acceptance.
