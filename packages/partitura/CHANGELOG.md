# Changelog

## 0.1.0-dev.1

Initial release.

- **Rendering**: `StaffView` (render-object widget) painting
  `partitura_core` layouts via the bundled Bravura font (SIL OFL 1.1):
  one px-per-staff-space scale factor, fit-to-width or explicit
  `staffSpace`, per-element colors, highlight set with repaint-only
  updates, `PartituraTheme` incl. kid mode (bold lines, large hit slop).
- **Interaction**: `InteractiveStaff` — element tap → id, empty-staff
  tap/drop → quantized `StaffTarget` (staff position + measure index,
  `pitchFor(clef)`), ghost-note drag preview with ledger-line hints.
- **Assets**: Bravura font + SMuFL metadata bundled; `Bravura.load()`
  caches parsed metadata.
- **Example**: gallery of the 21-scene golden corpus + interactive
  place-a-note demo (macOS, web, iOS).
