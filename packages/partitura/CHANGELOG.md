# Changelog

## 0.4.1-dev.1 (in progress)

- **Tab Tier-3 tail** (Phase 6.4, fully completes 6.4): `TabStaffView` now
  renders tapped/semi/feedback harmonics, named rasgueado patterns
  (`Rasgueado.pattern`), golpe (`Golpe`), wah open/close (`Wah`), and fade-in/out
  swells (`Fade`); plus `ChordPresets` for ukulele/banjo/mandolin. Golden 117.
- **Editor contract C7 — region controller** (Workshop): the element hit-region
  geometry that already lived on the private render objects is now reachable
  from app code via an `ElementRegionController` (alias
  `MultiSystemViewController`). Attach it with `MultiSystemView(controller:)` or
  `InteractiveGrandStaffView(controller:)`; after the first layout it exposes
  `elementRegions` (`(id, Rect bounds, int measureIndex)` in local pixels) and
  `elementIdsIn(Rect)` — the geometry behind marquee-select and drag-to-reorder.
  It re-binds when swapped and detaches on unmount.
- **Editor contract C8 — one-call export** (Workshop): `exportScoreToPng` /
  `exportScoreToSvg` (and `exportGrandStaffToPng` / `exportGrandStaffToSvg`) take
  a `Score`/`GrandStaff` (+ theme + staffSpace) and return PNG bytes / an SVG
  string with the engraving font embedded — owning the layout pass, the SMuFL
  metadata lookup and the font data-URI, so a print / page-export action is a
  single call. `MusicFont` gains a `fontAsset` for the SVG embed.

First tagged release. Everything below shipped during the 0.4.0 cycle.

- **Tab technique tail** (Phase 6.4, completes 6.4): `TabStaffView` now renders
  multi-point bend contours (`Bend.curve`), whammy dip/dive/return curves
  (`TremoloBar.curve`), slide in/out (`TabSlide`), pick-stroke direction
  (`PickStroke`), and arpeggiated chords (`NoteElement.arpeggio`). Golden 115.
- **Grace notes on the tab staff** (Phase 6.4): `TabStaffView` renders a note's
  grace notes as small fret digits before the principal, with a legato arc and
  an acciaccatura slash (appoggiatura omits it). Golden `107_tab_grace_notes`.
- **Editor overlays + control geometry** (Phase 3.3/3.4/3.8): `MultiSystemView`
  gains `errorOverlay` (a `Map<String, EditorMark>` — per-note color + message,
  drawn in the mark's color with a small wedge above it, for assessment /
  ear-training / proofreading apps), `loopRange` (`(startId, endId)` painted as
  a translucent selection/loop band that spans across systems), and
  `rectOfElement(id)` on the render object (the local pixel rect of any element,
  for the app to scroll-to-note). Overlays are repaint-only. New exported
  `EditorMark`; golden `109_editor_overlay`. The same `errorOverlay`,
  `loopRange`, and `rectOfElement(id)` are also on `InteractiveGrandStaffView`
  (the loop band spans both staves; error wedges sit above the note's own
  staff) — golden `111_grand_staff_overlay`.
- **`ScoreEditorController`** (Phase 3.8): a `ChangeNotifier` control surface
  that is the single source of truth for a view's overlay state — `setLoop` /
  `clearLoop`, `mark` / `unmark` / `setMarks` / `clearMarks`, `highlight` /
  `clearHighlight` — bound into `MultiSystemView` / `InteractiveGrandStaffView`
  via `AnimatedBuilder`. It also drives scroll-to-note on an **app-owned**
  `ScrollController`: `attachViewport(scrollController:, rectOfElement:)`, then
  `scrollToNote(id, alignment:)` (or `offsetToReveal(id)` to compute the offset
  and animate yourself). Realizes the `controller.setLoop(...)` /
  `controller.scrollToNote(...)` editor API.

- **Cross-staff gridding — accidental-aware columns** (§2.9): the shared column
  is now the **notehead** x, so heads align across staves even when only some
  carry an accidental at that beat (the accidental extends left of the column
  instead of pushing the head right). `alignedColumns` splits each element's ink
  into left (accidental) and right (notehead/stem/dots) and spaces columns so
  one column's right ink never collides with the next column's left ink; the
  engine's single-voice path anchors each head with `noteXOverride`. Completes
  §2.9. Goldens 75/76/95/96 re-rendered (subtle spacing shift; SATB accidentals
  on a beat now line up).
- **Cross-staff gridding — justification composes** (§2.9, increment 4): the
  wrapped grand staff now fills the line *and* keeps simultaneous notes aligned
  — `alignedColumns` takes the `spacingStretch`, so the justification search
  scales the shared columns rather than fighting them (verified by
  `grand_staff_systems_test.dart`).
- **Cross-staff gridding — multi-voice staves** (§2.9, increment 3): a staff
  with two-to-four voices now joins the shared column grid too. `alignedColumns`
  gathers onsets from every voice, `_layoutMultiVoiceMeasure` honours the shared
  `forcedColumns`, and the grand-staff / N-staff layouts drop their single-voice
  guard — so e.g. a two-voice piano hand aligns with the other staff. Fully
  additive (no golden changed).
- **Cross-staff gridding — N-staff systems** (§2.9, increment 2):
  `layoutStaffSystem` / `StaffSystemView` now grid-align simultaneous notes
  across every staff of an ensemble system (SATB, orchestral), reusing the same
  `alignedColumns` model — via a `gridAlign` flag (default true; single-voice
  staves). Goldens 75 (SATB) and 76 (two-staff system) re-render column-aligned.
- **Cross-staff onset-column gridding** (§2.9, increment 1): simultaneous notes
  now align vertically across the two staves of a grand staff — the rule every
  serious engraver enforces. A new core `alignedColumns(staves)` builds a shared
  per-measure column table (onset → x, gaps spaced by the optical time rule
  floored by the widest ink across staves), fed to a new
  `LayoutEngine.layout(..., forcedColumns:)` for the single-voice path; each
  staff places its notes on the shared columns. `layoutGrandStaff` /
  `layoutGrandStaffSystems` / `GrandStaffView` / `InteractiveGrandStaffView` gain
  a `gridAlign` flag (default true; a 2+-voice staff falls back to barline-only
  alignment). Goldens 35 & 95 re-rendered aligned; new golden
  `96_cross_staff_gridding`. *Left (later increments):* N-staff systems,
  multi-voice staves, accidental-aware columns.
- **Wrapped grand-staff justification.** `InteractiveGrandStaffView` gains a
  `justify` flag (default true): every non-final system now fills the width via
  a **shared note-spacing stretch applied to both staves** (binary-searched in
  `layoutGrandStaffSystems`), so the slack distributes as note spacing rather
  than end-padding and barlines stay aligned across the two staves.
  `layoutGrandStaff` gains a `spacingStretch` parameter. (Onset columns are
  still spaced per staff — full cross-staff gridding is a separate feature.)
- **Interactive grand staff — hover / caret / ghost / drag** (C2/C3 on the
  keyboard system): `InteractiveGrandStaffView` gains `onHover(StaffTarget?)`
  (via `MouseTrackerAnnotation`, null on exit), a `caret` (`EditorCaret`, drawn
  as a full-height insertion bar spanning both staves at the resolved x), a
  `ghostTarget` + `ghostDuration` preview notehead (its `staffIndex` picks the
  staff), and element drag hooks `onElementDragStart/Update/End` (via a
  `PanGestureRecognizer`). Completes the editor-hook parity with
  `MultiSystemView` for the grand staff. `interactive_grand_staff_view_test.dart`.
- **Editor contract C4 — range hit-testing / region geometry** (Workshop APIs):
  `RenderStaffView`, `RenderMultiSystemView` and `RenderInteractiveGrandStaffView`
  expose read-only `elementRegions` (each `(id, Rect bounds, measureIndex)` in
  local pixel coordinates, resolved across systems / both staves) and
  `elementIdsIn(Rect)` — for app-side marquee / shift-click range selection and
  custom overlays. `multi_system_view_test.dart`,
  `interactive_grand_staff_view_test.dart`.
- **Grand-staff PNG** (`renderGrandStaffLayoutToPng`): rasterizes a two-staff
  `GrandStaffLayout` to PNG — the raster twin of `grandStaffToSvg`, sharing the
  layout painter so the two staves stack `staffGap` apart. Wires up
  `partitura omr … out.png` (via the `render_png` harness' new `PARTITURA_GRAND`
  mode), so an optical-recognition scan renders straight to a two-staff image.
- **Editor contract C5 — interactive multi-line grand staff** (Workshop APIs):
  a new `InteractiveGrandStaffView` wraps a two-clef `GrandStaff` into multiple
  systems that fit the width, with `onElementTap` and `onStaffTap` on both
  staves (the `StaffTarget` carries `systemIndex` and `staffIndex` — 0 upper,
  1 lower). Backed by a new core `layoutGrandStaffSystems` (in `multi_system.dart`)
  that packs measures by the wider of the two staves so barlines align, draws
  the time signature only on the first system, and braces + barline-connects
  each system. `layoutGrandStaff` gains `drawTimeSignature`/`finalBarline` flags.
  Golden `95_grand_staff_wrapped`; `grand_staff_systems_test.dart`,
  `interactive_grand_staff_view_test.dart`. *Left:* per-system justification and
  hover/caret/drag (C2/C3) on the grand staff.
- **Editor contract C3 — drag an existing element** (Workshop APIs):
  `InteractiveStaff` and `MultiSystemView` gain `onElementDragStart(id)`,
  `onElementDragUpdate(id, StaffTarget)` and `onElementDragEnd(id, StaffTarget)`.
  A drag that begins on an element reports it with the live quantized target
  (carrying `systemIndex` on the multi-line view); a drag on empty staff still
  drives the placement ghost / `onStaffTap`. `MultiSystemView` grows a
  `PanGestureRecognizer` alongside its tap recognizer. partitura only reports;
  the app maps the target to a new pitch/position and rebuilds the score.
- **Editor contract C2 — hover preview + caret on the multi-line view**
  (Workshop APIs): `MultiSystemView` gains `onHover(StaffTarget?)` (fires on
  mouse move, null on exit — via a `MouseTrackerAnnotation`), a `caret`
  (`EditorCaret` — before an element or at a `measureIndex`/`staffPosition`,
  drawn as a vertical insertion bar across systems) and a `ghostTarget` +
  `ghostDuration` translucent preview notehead (with preview ledger lines).
  Caret and ghost are repaint-only. Drive `ghostTarget` from `onHover` for a
  desktop placement preview.
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
