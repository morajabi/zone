# Zone artwork

Original vector artwork, released with Zone under the [MIT license](../../LICENSE). No external assets or fonts.

- `zone-mark.svg` — the small identity mark, with light and dark appearances.
- `zone-mark-monochrome.svg` — a solid black source for template rendering. Apply the platform's template tint rather than displaying black in every appearance.
- `zone-icon.svg` — the 1024 × 1024 app-icon master. It preserves the existing open-ring identity with a quieter green palette and stronger contrast.
- [`../../docs/images/banner.svg`](../../docs/images/banner.svg) — the repository banner.

The opening is deliberate. Keep its angle, rounded ends, and center point together. Leave at least one stroke width of clear space around the mark. Avoid rotation, motion, extra rings, or a second accent color.

The app uses `Resources/Zone.icns`. Recreate it with `swift scripts/generate-icon.swift` from the repository root. The tiny AppKit renderer writes all ten PNG iconset representations and packages the ICNS with Apple's `iconutil`; it does not build the app. Its geometry and colors match `zone-icon.svg`, which is reproduced at one-quarter scale in the banner.
