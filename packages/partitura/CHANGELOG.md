# Changelog

## 0.4.0-dev.1 (in progress)

- **Editor contract C1 — staff-tap on the multi-line view** (Workshop APIs):
  `MultiSystemView` gains `onStaffTap(StaffTarget)`, firing when the user taps
  empty staff (an element tap still routes to `onElementTap`). A new
  `RenderMultiSystemView.resolveStaffTarget` picks the system whose band is
  nearest the tap, then quantizes to the nearest line/space (same math as
  `RenderStaffView`) and resolves the global measure. `StaffTarget` gains
  `systemIndex` and `staffIndex` (both default 0, backward-compatible). Enables
  click-to-place on a wrapped score.
- **Pluggable SMuFL fonts** (Phase 1.3): a `MusicFont` descriptor (family +
  asset package + metadata JSON) and a `MusicFonts` per-font metadata loader
  make the engraving face swappable via `PartituraTheme.musicFont` (default
  Bravura). Every view — `StaffView`, `MultiSystemView`, `StaffSystemView`,
  `ScorePageView`, `GrandStaffView`, `TabStaffView` and `renderLayoutToPng` —
  now draws glyphs in and loads the metadata of the theme's font, relayouting
  when it changes (proven end to end by a widget test: a swapped font renders
  heavier staff lines). The engine already reads line/stem weights from each
  font's metadata. SMuFL fixes glyph codepoints, so a new face is an asset drop
  (OFL SMuFL fonts bundle cleanly in this MIT project as Bravura does).
- **`ScorePageView`** (Phase 2.5): renders one page of a paginated score at a
  fixed `PageMetrics` box — margins, vertical justification (page-fill) and an
  optional page frame; `pageIndex` switches pages without relayout (golden 81).
- **`StaffSystemView`** (Phase 2.1): renders N-staff systems — connected
  barlines, bracket/brace groups (with nested-depth offsets) and cross-staff
  tap hit-testing (goldens 75–78).
- **`StaffView.showMeasureNumbers`** (Phase 2.4/2.7): anacrusis-aware bar
  numbers above each measure (golden 80). Common/cut time symbols and the
  neutral percussion clef render via the core engine (goldens 82–83).
- **PNG export** (Phase 7.2): `renderLayoutToPng(layout, {…})` rasterizes a
  `ScoreLayout` (notation or tab) to PNG bytes via `dart:ui` — the raster
  counterpart to core's `scoreToSvg`. Runs inside a Flutter binding; reuses
  the shared `LayoutPainter`.
- **Guitar/bass tablature** (v0.8): `TabStaffView` renders a `Score` as tab
  (fret numbers on string lines, TAB clef) for a `Tuning`, with rhythm and
  playing techniques — slides, hammer-on/pull-off, bends, vibrato, palm
  mute / let ring, dead / ghost notes, natural harmonics, and capo + tuning
  labels (`TabStaffView` `capo` / `showTuning`), and tapping + tremolo-bar;
  golden scenes 52–61. Chord/fretboard diagrams place above the notation staff
  too (lead-sheet style, golden 62).
- **Forced horizontal / custom-slant beams** rendered (Phase 1.4, via
  `partitura_core`): golden scene 51, gallery entry.
- **Feathered beams** rendered (Phase 1.4, via `partitura_core`): fanned
  accel./rit. beams; golden scene 50, gallery entry.
- **Sustain-pedal marks** rendered (v0.7.2, via `partitura_core`):
  "Ped." … release star below the staff; golden scene 49, gallery entry.
- **Tremolo** rendered (v0.7.2, via `partitura_core`): 1–5 stroke glyphs
  through the stem; golden scene 48, gallery entry.
- **Glissando / slide** rendered (v0.7.2, via `partitura_core`): straight
  line between two notes; golden scene 47, gallery entry.
- **Arpeggio / rolled chords** rendered (v0.7.2, via `partitura_core`):
  vertical wavy line with a direction arrowhead; golden scene 46, gallery
  entry.
- **Fingering numbers** rendered (v0.7.2, via `partitura_core`): SMuFL
  `fingering0`–`fingering9` glyphs above the note; golden scene 45,
  gallery entry.
- **Navigation marks** rendered (v0.7.1, via `partitura_core`): segno/coda
  glyphs and D.C./D.S./To Coda/Fine words above the staff (reusing the
  existing `GlyphPrimitive`/`TextPrimitive` paint paths — no new painter);
  golden scene 44, gallery entry.
- **Two voices per staff** rendered (via `partitura_core` 0.4); golden
  scene 34, gallery entry.
- **Grand staff**: `GrandStaffView` (brace, connected barlines, aligned
  measures, cross-staff element taps); painting extracted into a shared
  `LayoutPainter`; golden scene 35, gallery card.
- **Line breaking**: `MultiSystemView` wraps a score into systems that
  fit the available width (rebreaks on resize, justification toggle,
  taps and repaint-only highlights across systems); golden scene 36,
  gallery card.
- **Chord symbols / annotations** above the staff (same `TextPrimitive`
  path as lyrics: highlight/element colors, taps resolve to the note);
  golden scene 38, gallery card.
- **Lyrics** rendered via the new `TextPrimitive` (real text centered on
  the core's anchor); `PartituraTheme.textFontFamily` picks the text
  font (null = platform default); syllables follow highlight/element
  colors and taps on them resolve to their note; golden scene 37,
  gallery card.

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
