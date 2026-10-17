# README presentation proposal

Lead with the installable app, then explain the everyday flow. Keep developer setup below the product explanation. The current README leads with a full feature list and build instructions; that becomes unnecessary friction once a signed download is available.

## Recommended order

1. Banner: `docs/images/banner.svg`, using useful alt text so the product name is readable without the image.
2. One-sentence description and the main **Download for macOS** link to `https://github.com/morajabi/zone/releases/latest`.
3. Compatibility and install sentence. State “signed and notarized” only after the downloadable artifact has passed verification. Do not promise automatic updates unless they exist.
4. One genuine screenshot of the chosen, implemented UI. Replace the existing screenshot only after capturing the final app; the HTML spikes are design exploration, not product screenshots.
5. Three everyday steps: choose distractions, choose a duration, start. Put browser permissions in the first-use step and explain app-closing behavior before the user starts.
6. A compact “Made for your routine” list: schedules, flexible or locked sessions, configurable pauses, menu-bar access. Skip claims like “all browsers” or “tamper-proof.”
7. A short “What to expect” section covering supported browser automation, the occasional brief page appearance before redirection, app quitting, and locked-mode limits. Link fuller behavior to existing docs.
8. “Build it yourself” and contributor links. Keep signing details in dedicated release documentation. Preserve public no-paid-account build instructions.
9. License.

## Suggested opening copy

```markdown
![Zone — Make room for focus. A small, native macOS app for fewer distractions.](docs/images/banner.svg)

Zone lives in your menu bar and blocks distracting websites and apps while you focus. Start a session now or make it part of your weekly routine.

**[Download for macOS](https://github.com/morajabi/zone/releases/latest)** · [Build from source](#build-it-yourself) · [Report an issue](https://github.com/morajabi/zone/issues)

Requires macOS 15 or later. Free and open source. No account, subscription, or analytics.

<!-- Add after verifying the release artifact: “The download is signed and notarized. Open the disk image and drag Zone to Applications.” Use “Unzip and move Zone to Applications” if the asset is a ZIP instead. -->
```

Avoid a badge strip, duplicate title, version badge, large feature grid, fake App Store badge, or multiple competing download links. The banner should supply the visual identity; the screenshot should demonstrate the real interface.

## Artwork selection

The comparison is [`brand/index.html`](brand/index.html). **Quiet orbit (01)** is recommended: it preserves Zone's existing ring-and-point motif, works as a silhouette, and fits beside native controls without making the UI more decorative. The palette is restrained deep green and near-white, with one pale green point.

Original SVG sources are in `Resources/Brand/`. The selected master is reproduced by `scripts/generate-icon.swift`, which renders all ten iconset sizes and packages `Resources/Zone.icns` without building the app. The selected icon has been generated and visually inspected at 16 and 256 pixels.

## Release page copy

Use a short release title such as **Zone 0.2.0**. Lead with the download and installation sentence, the minimum macOS version, and whether the binary is universal. List only the major user-visible changes. Include SHA-256 checksums as an asset or a small code block, and retain the source archives GitHub supplies.

Only claim universal support, Gatekeeper acceptance, notarization, or automatic updates when the exact released artifact has the corresponding evidence. A successful source build is not enough.
