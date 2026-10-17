# Menu-bar studies

Eight standalone interaction studies. Each file contains its own CSS and JavaScript, uses system fonts, supports light/dark appearance, and fits a 320-point menu-bar surface. At wider sizes the popover stays centered. These are UI prototypes with sample rules; they do not access or block browsers.

Every study supports starting, configurable pause length and allowance, early resume, flexible ending, locked-session confirmation, disabled early ending, and natural expiry. Session duration continues to elapse during pauses, matching Zone’s current policy. Management links reveal small sample destinations. Escape returns from secondary screens.

## Ranking

| Rank | Study | Why |
| --- | --- | --- |
| 1 | [Quiet duration](01-quiet-duration.html) | Time is the main object. One obvious Start action; list selection and a concise policy summary remain legible. |
| 2 | [Duration inspector](05-duration-inspector.html) | Fewest everyday controls. Best for repeating the same session, but changing time takes another click. |
| 3 | [Timer dial](03-timer-dial.html) | Strong continuity from setup to countdown. Visually pleasant, but the ring takes space and the slider sacrifices precision. |
| 4 | [Native menu](02-native-menu.html) | Familiar command hierarchy without button chrome. The menu has more visible choices than the quieter studies. |
| 5 | [A simple sentence](04-simple-sentence.html) | Reads as an intention rather than a form. Long names and localization complicate line wrapping. |
| 6 | [Until later](06-until-later.html) | End-time selection works well around meetings; duration is more familiar for everyday focus. |
| 7 | [Remembered rhythm](08-remembered-rhythm.html) | Two repeatable routines are quick, but recipes introduce another concept to manage. |
| 8 | [Two decisions](07-two-decisions.html) | Helpful onboarding sequence; too many steps for a frequent menu-bar task. |

## Recommended direction

Use **Quiet duration** as the main structure. Borrow the **Duration inspector**’s brief policy summary and keep advanced editing in a separate small surface. Use the same timer object for active state, with Pause as the sole primary action. End remains a quiet text action for flexible sessions; locked sessions show a clear status statement. Remove preset-button rows, repeated list-edit links, always-visible mode controls, separate Quit icons, and duplicated section titles from the everyday popover.

Keep list and schedule management in the main window. A single “Manage Zone” link is enough in the popover footer. App-wide settings remain a separate standard Settings window, consistent with the Notes and Image Playground macOS 27 captures in the Apple Native App Patterns atlas. The prototypes’ general conventions follow HIG guidance on a small set of related popover tasks, concise labels, clear primary actions, semantic hierarchy, and accessible control names. Their custom geometry is exploratory, not a claim that Apple uses these exact layouts.

## Validation

All eight scripts passed syntax checks and a lightweight state-machine smoke run: initial template rendering, Start, Pause, Resume, allowance exhaustion, flexible End, locked confirmation, early-end prevention, and expiry. Layouts still require visual review in the gallery at narrow and wide sizes. `visibleActionCount` in the metadata counts every initially visible actionable input, picker, button, and management link, not merely prominent buttons.
