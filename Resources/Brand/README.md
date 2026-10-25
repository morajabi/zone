# Zone artwork

Original vector artwork, released with Zone under the [MIT license](../../LICENSE). No external assets or fonts.

- `zone-mark.svg` — the small identity mark: an open ring around a warm sun, with light and dark appearances.
- `zone-mark-monochrome.svg` — a solid black source for template rendering. Apply the platform's template tint rather than displaying black in every appearance.
- `zone-icon.svg` — the 1024 × 1024 app-icon master on Apple's 824-point grid. The open ring now holds a rising sun on a dawn sky, from periwinkle through rose to apricot.
- [`../../docs/images/banner.svg`](../../docs/images/banner.svg) — the earlier repository banner, kept for the design archive. The README now uses `docs/images/icon.png`, made from `scripts/generate-icon.swift --preview`.

The opening is deliberate. Keep its angle, rounded ends, and center point together. Leave at least one stroke width of clear space around the mark. Keep the dawn palette warm and soft; avoid dark or alarming colors.

The app uses `Resources/Zone.icns`. Recreate it with `swift scripts/generate-icon.swift` from the repository root. The tiny AppKit renderer writes all ten PNG iconset representations and packages the ICNS with Apple's `iconutil`; it does not build the app. Its geometry and colors match `zone-icon.svg`, which is reproduced at one-quarter scale in the banner.
