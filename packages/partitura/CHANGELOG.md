# Changelog

## 0.3.0-dev.1

- **Slurs** and **ties** rendered as stroked Bézier curves (`CurvePrimitive`); golden
  scenes 26/27, gallery entries; **tuplets** (digit + bracket) with
  golden scene 28; **articulations** with golden scene 29; **dynamics + hairpins** with golden scene 30;
  **grace notes** (scaled glyph painting) with golden scene 31;
  **32nd/64th/breve durations** with golden scene 32; **mid-score
  changes, repeats & voltas** with golden scene 33.

## 0.2.0-dev.1

- **Alto and tenor clefs** (via `partitura_core` 0.2): C-clef rendering,
  golden scenes, gallery entries and clef options in the example's
  interactive demo.

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
  caches parsed metadata (single-flight; failed loads are not cached and
  retry on the next call).
- **Example**: gallery of the 23-scene golden corpus + interactive
  place-a-note demo (macOS, web, iOS) with an end-to-end integration
  test (`flutter test integration_test -d macos`).
