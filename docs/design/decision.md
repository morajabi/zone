# A quieter Zone

For 0.2.0, the everyday task is one decision about time, one choice of distractions, and one primary action. Mode and pause settings remain visible as a sentence; their controls appear only when asked for.

## Exploration

We built and ran 24 self-contained HTML studies, in three families of eight. The [gallery](spikes/index.html) opens directly from disk and renders only the current two or four studies. They are experiments with sample data, not screenshots of the macOS app.

All 24 were rendered and visually compared at 1280 × 720. The short list was inspected at full size, including the start/pause flow of Quiet duration and the policy editor of Menu Bar Essential. The prototypes also received lightweight JavaScript syntax and interaction checks. These experiments do not validate native app behavior.

| Finalist | What worked | Decision |
| --- | --- | --- |
| [Quiet duration](spikes/menu/01-quiet-duration.html) | Large editable time, explicit list picker, one action, short policy summary | Primary menu-bar direction |
| [Time First](spikes/minimal/02-time-first.html) | Clear duration-to-countdown transition and breathing room | Main-window direction |
| [Menu Bar Essential](spikes/native/04-menu-panel.html) | Descriptive rows reveal configuration without permanent forms | Carry forward progressive disclosure |
| [Quiet Sentence](spikes/minimal/01-quiet-sentence.html) | Reads naturally with very little chrome | Less robust with long names and translations |
| [Duration inspector](spikes/menu/05-duration-inspector.html) | Very calm repeat-session experience | Adds a click to the common duration change |

The other studies explored a timer dial, command entry, saved recipes, a two-step guide, end-time selection, list-first navigation, a session library, a persistent inspector, native menu rows, and a daily agenda. Rings introduced decoration without improving precision; recipes and command entry introduced extra concepts; agenda and library layouts competed with a quick session. The existing sidebar remains useful for managing lists and schedules in the supporting window.

## Implemented direction

- Remove the row of four duration preset buttons. The large duration is directly editable.
- Use one prominent Start action. The selected list and rule count remain visible before starting.
- Collapse mode and pause controls behind an exact summary, including pause duration.
- Keep time in the same central position during a session. A pause shows its own countdown and the unchanged session end time.
- Open lists and schedules by clicking their row. Move secondary actions into menus instead of repeating Edit and Delete buttons.
- Keep app preferences in the native Settings window. Put Settings and Quit together in the menu-bar panel’s secondary menu.
- Preserve native pickers, disclosures, buttons, sheets, keyboard access, semantic colors, and permission/error states.

Apple’s [button guidance](https://developer.apple.com/design/human-interface-guidelines/buttons) recommends a small number of prominent actions and familiar system controls. This pass applies that hierarchy rather than adding bespoke controls. Native runtime verification is recorded in [acceptance](../acceptance.md).

## Artwork

[Four original vector studies](brand/index.html) led to Quiet orbit: a restrained open ring and still point. The app icon and README banner share the same vector geometry. The editable sources are in `Resources/Brand`; `scripts/generate-icon.swift` generates all ten icon representations and the ICNS without compiling the app.
