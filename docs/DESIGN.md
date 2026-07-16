# crisp_notation — design log

Running log of non-obvious decisions and their rationale. Append as you go;
terse is fine. Active roadmap coordination lives in PLAN.md.

## Pre-seeded decisions (scaffold, 2026-07-10)

- **Naming**: the project was scaffolded as "neume" and renamed to
  "crisp_notation" the same day (maintainer decision). Current coordination
  lives in PLAN.md and the implemented public contract lives in
  docs/CONTRACT.md.
- **Coordinate system**: layout works in *staff spaces* (1 space = gap between
  adjacent staff lines), origin at the intersection of the staff's top line
  and left edge, y grows downward. Rendering converts to px with one scale
  factor. SMuFL convention: font size = 4 × staff space.
- **Staff position convention**: `Pitch.staffPosition(clef)` returns 0 for the
  bottom line, +1 per line/space upward (treble: E4 = 0; bass: G2 = 0).
- **Two packages, not three**: layout stays in `crisp_notation_core` (pure Dart,
  logic testable without Flutter); a separate layout package added friction
  without a consumer that wants layout-but-not-theory.
- **No dependencies**: theory core is small at our scope; owning it keeps the
  MIT story clean and lets the model be shaped for pedagogy
  (`Key.triadFor(HarmonicFunction)` etc.).

## M1 — theory core (2026-07-10)

- **`showAccidental` is `bool?`, not `bool`**: the original build brief declared
  `final bool showAccidental` but described tri-state semantics
  ("force/hide courtesy accidental" *overriding* an automatic rule). A plain
  bool cannot express "automatic". Resolution: `bool?` — `null` = automatic
  (key signature + earlier accidentals in the measure decide), `true` =
  force, `false` = hide.
- **Minor-key dominant is a major triad** (`Key.triadFor`): follows the
  harmonic-minor convention of functional harmony (A minor: t=Am, s=Dm,
  D=E major), which is what cadence pedagogy (T–S–D–T) teaches. Documented
  on the method.
- **`Fraction` is public**: games need exact duration sums ("fill the
  measure"); hiding it would force consumers to reimplement rational math.
  `NoteDuration.fraction` keeps the contract's `(int, int)` record shape;
  `toFraction()` bridges to arithmetic.
- **DSL grammar** (`Score.simple`): whitespace-separated tokens, `|` splits
  measures, `pitch[+pitch…][:dur]`, `r[:dur]` for rests, durations `w h q e
  s` with up to two dots, sticky duration (LilyPond-style; initial default
  quarter). Chords use `+` instead of parentheses so tokenizing stays a
  whitespace split. `n` = explicit natural, which also forces
  `showAccidental: true`. Elements auto-get ids `e0, e1, …` in reading
  order so games can address them without building the tree by hand.
- **`Interval.between` is order-insensitive** and caps at one octave;
  quality is recovered from spelling (C–F♯ = A4, C–G♭ = d5), so
  ear-training games can distinguish enharmonic intervals.
- **`Clef.pitchAt(staffPosition)`** added as the inverse of
  `Pitch.staffPosition` — the interaction layer's `StaffTarget.pitchFor`
  and "tap to place a note" need position→pitch, and round-trip tests pin
  the two conventions together.
- **Transposition beyond double accidentals throws `ArgumentError`** (e.g.
  F𝄫 down a major third). Alternatives (silent enharmonic respell) would
  make theory answers wrong; games stay in sane ranges anyway.

## M2 — layout engine (2026-07-10)

- **Geometry types**: the original build brief's pseudo-code used `Offset`, but
  `crisp_notation_core` cannot depend on Flutter. We use `dart:math`'s
  `Point<double>` / `Rectangle<double>` (SDK-only). Deliberately NOT a
  custom class named `Offset`/`Rect` — that would collide with `dart:ui`
  in every consumer that imports both Flutter and crisp_notation.
- **y of a staff position**: `y = (8 - p) / 2` (origin top line, y down).
- **Metadata flow**: core cannot load assets; the consumer decodes
  `bravura_metadata.json` and passes it via
  `SmuflMetadata.fromJson` → `LayoutSettings(metadata: …)`. Core tests read
  the file from `../crisp_notation/assets/` directly. Glyph metrics (bboxes,
  stem anchors) come from the font metadata, not hardcoded values; SMuFL
  bbox/anchor y-up coordinates are flipped at the single point of entry.
- **Spacing formula** (rule 13): a note/rest advances
  `spacingBase + spacingPerLog2 · (4 + log2(duration))` staff spaces from
  its notehead column (sixteenth = `spacingBase` = 1.8, each doubling adds
  0.75), but never closer than `minNoteGap` after the element's ink.
  `log2` of the dot factors is a 3-entry constant table, keeping layout
  bit-for-bit deterministic (rule 14) without transcendental calls.
- **Beam grouping** (rule 7): groups form per `1/beatUnit` window, never
  across rests or windows. In even-numerator x/4 meters, adjacent
  all-eighth groups in the same half-measure merge — this yields the
  contract's "8 eighths in 4/4 = 2 beams" while 3/4 stays per-beat.
  Compound 6/8 grouping (3+3) is out of scope v0.1 ("simple-meter grouping
  only"): in x/8 meters each eighth is its own window, so eighths get
  flags. Unmetered scores group per quarter window.
- **Beam geometry**: slant = `clamp((refY_last − refY_first)/2, ±1)`,
  intercept chosen so every stem keeps ≥ default length (min/max over the
  group), then shifted so the beam never crosses the middle line from the
  stem side. `BeamPrimitive.start/end` are the midpoints of the beam's end
  edges; stems run to the beam's center line. Secondary (16th) beams are
  offset `beamThickness + beamSpacing` toward the noteheads; a lone
  sixteenth between eighths gets a 1-space beamlet stub pointing into the
  group.
- **Stem extension** (rule 5): default 3.5 spaces; if the default tip
  falls short of the middle line for notes far outside the staff, the stem
  extends to y = 2 (both directions).
- **Accidental state** (rule 9): per measure, keyed by (step, octave) —
  F♯4 does not imply F♯5. A hidden accidental (`showAccidental: false`)
  does NOT update the written state (state tracks what the reader sees);
  a forced one does.
- **Chord seconds** (rule 11): walking from the stem's anchor end, a note
  a second above/below an unflipped neighbor flips to the stem's other
  side. Flipped x = one notehead width minus stem thickness.
- **Key signature octaves** (rule 2): treble sharp positions
  [8,5,9,6,3,7,4], flats [4,7,3,6,2,5,1] (staff positions); bass = same
  pattern 2 positions lower (matches VexFlow/Behind Bars, incl. F♭ on the
  ledger position −1 for 7-flat bass signatures).
- **`ScoreLayout.top` added** beyond the contract's width/height: ink
  extends above y = 0 (clef overshoot, high notes), so the renderer needs
  the bounding-box top to translate correctly. Also added
  `measureRegions` (x-extents per measure) for the interaction layer's
  tap→measure mapping.

## M3 — rendering (2026-07-10)

- **Async metadata, sync paint**: `Bravura.load()` parses the bundled
  metadata once and caches it; `StaffView` triggers the load on first
  layout and paints nothing for that frame (apps `await Bravura.load()` in
  `main()` to avoid the gap; tests inject via `debugOverrideMetadata`).
  Chosen over a mandatory `ensureInitialized()` because a blank first
  frame is a gentler failure mode than a crash.
- **Glyph painting**: `TextPainter`, font size = 4 × staff space, glyph
  origin anchored via `computeDistanceToActualBaseline` (the seed's
  baseline-anchoring technique). Painters cached per
  (glyph, color), cache cleared on relayout/theme change.
- **Kid mode** is implemented as data on the theme (`hitSlop`,
  `lineBoost`) rather than behavior switches, so games can tune both
  independently. `lineBoost` feeds the layout settings (thicker primitives
  move ink bounds), so toggling it relayouts; pure color changes only
  repaint.
- **Goldens** (21 scenes) were generated on **macOS** with Flutter 3.44.4;
  font rendering differs across platforms, so run them on macOS or
  regenerate locally (`flutter test --update-goldens`).
- **Example app** is a workspace member (`packages/crisp_notation/example` in
  the root `workspace:` list) — pub workspaces don't allow unlisted nested
  packages.

## M4 — interaction (2026-07-10)

- **One geometry owner**: `RenderStaffView` is the single place that maps
  px ↔ staff spaces. It exposes `elementIdAt`, `quantizeStaffPosition`,
  `localToStaff`/`staffToLocal` and a `ghostNote` repaint-only field;
  `InteractiveStaff` is thin widget glue (gestures via a `GestureDetector`
  pan + the render object's own tap recognizer) rather than a second
  layout consumer.
- **Element tap beats staff tap**: a tap inside any (hit-slop-inflated)
  element region fires `onElementTap` only; `onStaffTap` fires only on
  empty staff. Overlapping regions resolve to the smallest one (a chord
  notehead wins over a long-stemmed neighbor).
- **Drag = preview + drop**: while a pan is active a quantized ghost
  notehead (+ ledger-line preview) follows the pointer; releasing over
  empty staff fires `onStaffTap` with the same quantization. Quantization
  clamps to staff positions −6..14 (3 ledger lines beyond the staff).
- **Selection is app state**: `InteractiveStaff` doesn't own a selection
  set; games pass `highlightedIds` (repaint-only, verified by test).

## M5 — release polish (2026-07-10)

- **Hero image** is produced by a golden test (`test/hero_test.dart` →
  `doc/hero.png` in both packages) rather than a manual screenshot, so it
  regenerates with the renderer. READMEs reference it via
  raw.githubusercontent.com URLs (pub.dev doesn't resolve relative paths);
  they go live once the repo is pushed to the `repository:` URL.
- **`dart pub publish --dry-run`** passes for both packages; the only
  warning is the (expected) uncommitted-changes notice at check time.
  Archive: crisp_notation ≈ 856 KB compressed, dominated by the unmodified
  Bravura font + metadata (OFL requires shipping it unrenamed/unsubset).
- **Example verified**: macOS debug build launched and ran; web and iOS
  simulator debug builds compile. Goldens + widget tests cover rendering
  correctness; platform runs were smoke tests.
- **Not done deliberately**: publishing (maintainer does that, per
  contract), git tags, CI config (no CI requirements in the contract).

## Test expansion (2026-07-10, post-M5)

- **Property sweeps** (`theory_property_test.dart`): instead of more
  hand-picked cases, invariants over the whole game-relevant input space —
  transposition semitone/spelling/round-trip/`Interval.between` agreement
  across ~1575 pitch×interval combos, scale patterns + key-signature
  agreement for every buildable tonic, triad structure for all roots and
  qualities, fraction algebra laws.
- **Layout edge suite** (`layout_edge_test.dart`): stem-direction sweep
  over all 21 staff positions × both clefs, beaming edge cases (beamlets,
  beat boundaries, 2/4 merge, x/8 flags-only fallback, 5/4, unmetered),
  accidental bookkeeping incl. `showAccidental: false` state semantics,
  chord clusters/whole-note seconds/ledger spans, spacing monotonicity,
  barline/measure-region counts, per-corpus determinism.
- **Live paint tests** (`render_pixel_test.dart`): render to image and
  count pixels of the expected color inside notehead boxes (single-point
  sampling fails: whole/half noteheads are hollow and staff lines cross
  every box). Verifies element colors, highlight precedence, ghost-note
  appearance/disappearance and kid-mode line boldness on actual pixels.
- **Asset-path tests** (`bravura_test.dart`): `Bravura.load()` against a
  mocked asset bundle (with `rootBundle.evict` — the bundle caches
  strings), single-flight caching, and the StaffView "empty first frame →
  self-heal after load" behavior. Added `Bravura.debugReset()` for this.
- **Mini game-loop test** (`interaction_edge_test.dart`): a stateful
  place-a-note widget driving the same tap→mutate→rebuild cycle the real
  minigames use. Gotcha encoded in the tests: empty measures are
  zero-width, so tap targets must be computed from the live layout.
- **Example integration test** (`example/integration_test/app_test.dart`):
  boots the real app on a device (`flutter test integration_test -d
  macos`), scrolls the gallery, places/selects a note, toggles kid mode.
  The machine's CocoaPods install is broken (Homebrew Ruby mismatch), so
  Swift Package Manager was enabled (`flutter config
  --enable-swift-package-manager`) and the example ships **no Podfile**
  for macOS or iOS — plugin integration goes through SPM on both (a
  present Podfile forces the CocoaPods path and fails on this machine).
  All three targets (macOS, web, iOS simulator) build under this setup.
- The example's interactive screen now uses a fixed `staffSpace: 16` —
  fit-to-width made an empty two-measure staff comically large (and
  taller than small windows).
- **Bug the live tests caught**: the example mutated a measure's element
  list in place and rebuilt `Score` around the *same* list, so old and new
  scores compared equal and `StaffView` skipped the relayout. Consumers
  must copy lists per rebuild (`Measure(List.of(elements))`); the model
  docs say "treat lists as immutable" and the integration + widget tests
  now guard the pattern. Two test-infra gotchas worth remembering:
  `rootBundle.loadString` decodes large assets on a background isolate, so
  anything that triggers `Bravura.load()` in a widget test must run inside
  `tester.runAsync`; and `Center`ed staffs move when the score grows, so
  tests must re-read the widget origin before every tap.

## Test expansion round 2 + contract doc (2026-07-10)

- Added constructor-validation and engraving-quality suites (core 233
  tests), theme/geometry/gesture contracts and two new goldens (crisp_notation
  64 tests), example control-flow tests and an extended on-device
  integration run. Full inventory in docs/CONTRACT.md §9.
- **Library fix found by the retry test**: `Bravura.load()` cached a
  *failed* future forever — one flaky asset read would have blanked every
  StaffView until restart. Failures now clear the pending future so the
  next call retries.
- **docs/CONTRACT.md** is the consumer-facing description of features and
  API guarantees. Keep it in sync when the public surface changes; READMEs
  link to it.
- Unicode gotcha for UI tests: musical-symbol labels like the half note
  are decomposed sequences (U+1D157 + U+1D165), so `find.text` with the
  precomposed codepoint misses them — find segmented-button labels
  structurally.

## v0.3 notation depth (2026-07-10)

- **Curves** (ties/slurs) are `CurvePrimitive` cubic Béziers stroked with
  round caps — not the filled variable-thickness shapes of full engraving;
  revisit if visual polish demands it.
- **Tuplet spacing** uses `log(normal/actual)/ln2` at layout time — the
  only transcendental call in the engine; it is deterministic for equal
  inputs on a given platform, which is what rule 14 needs in practice.
- **Beams never cross tuplet boundaries** (run building and the
  half-measure merge both check span membership). The golden corpus
  caught the original violation: the merge welded a c5–e5 triplet to a
  following low eighth and flipped the whole group's stems.

## v0.3.8 mid-score changes (2026-07-10)

- The layout builder threads **current** clef/key/time state through the
  measure loop (`_clef`/`_key`/`_time`); everything downstream (note
  positions, accidental implications, beam windows, signature tables)
  reads the current state, so changes are one code path, not special
  cases.
- Volta numbers reuse the SMuFL tuplet digits at 0.8× — crisp_notation still
  has no text primitive; revisit when lyrics (v0.4) introduce one.
- Interaction quantization still maps via one clef; documented caveat in
  CONTRACT.md until the geometry API grows per-measure clefs.

## v0.4.1 two voices (2026-07-11)

- **Two code paths, deliberately**: the proven single-voice measure loop
  is untouched; `_layoutTwoVoiceMeasure` adds an onset-column engine
  (merged onsets of both voices, per-column ideal advance from the onset
  delta, ink constraint across both voices). Unifying them was possible
  but would have re-derived every single-voice test and golden for zero
  user value; revisit if a third path (grand staff) makes the duplication
  hurt.
- Ties match the next element **of the same voice** (`_TieInfo.voice`) —
  layout order interleaves voices per column, so "next in list" is wrong.
- Columns align element *starts*; noteheads misalign slightly when only
  one voice carries an accidental at that beat. Accepted for v0.4.1,
  fix with notehead-aligned columns in 0.6 polish.
- Voice-2 rests offset ±1 space; tuplets/directives stay voice-1 only
  until a consumer needs more.

## v0.4.2 grand staff (2026-07-11)

- **Alignment granularity**: measures (and the leading segment) align
  across staves via two-pass width maxima — not note columns. Equal or
  simple rhythms look right; dense cross-staff polyrhythms would need a
  cross-staff column engine (0.6 candidate if a consumer needs it).
- **Painting extracted** into `LayoutPainter` (shared by StaffView and
  GrandStaffView); the 34 pre-existing goldens passed unchanged,
  proving the extraction pixel-identical.
- The brace is the SMuFL `brace` glyph scaled to span both staves
  (`GlyphPrimitive.scale` machinery); the widget adds a 1.4-space left
  inset for it.

## v0.4.3 line breaking + justification (2026-07-11)

- **Slice-based**: each system re-lays a sub-`Score` of its measures
  with the running clef/key/time as the slice's leading state (state
  arrays precomputed once). No system-aware code inside the measure
  loop; the engine stays single-line.
- Greedy packing estimates system widths from the natural layout's
  cumulative `measureRegions` (exact for barlines/repeats/inline
  changes) plus a per-system leading-width probe; a post-layout trim
  loop guarantees `width ≤ maxWidth` for multi-measure systems. An
  overwide single measure gets its own system rather than failing.
- **Justification = uniform spacing stretch**, binary-searched (24
  iterations, break when within 0.05 spaces under budget; only a
  fitting candidate may end the search — an overshooting one must keep
  narrowing). `spacingStretch` multiplies only the duration-proportional
  ideal advance, never ink minimums or the leading segment.
- The slice keeps its time signature (beam windows derive from it) but
  the engine's new `drawTimeSignature: false` suppresses drawing it on
  later systems; `finalBarline: false` closes continuing systems with a
  thin barline.
- Spans (slurs/dynamics/hairpins) whose endpoints land on different
  systems are **dropped**, not split — correct broken-span rendering
  (dangling curve to the margin) is 0.6 polish; ties already degrade
  gracefully per measure.
- `MultiSystemView` requires a fixed `staffSpace` (no fit-to-width):
  the available width is the input to breaking, so it cannot also
  derive the scale.

## v0.4.4 lyrics (2026-07-11)

- **Core cannot measure text** (pure Dart, no font rasterizer), so
  `TextPrimitive` is anchored center-baseline and the engine estimates
  syllable widths at 0.5 em per character — good enough for hyphen
  placement and hit regions; the renderer centers the real text on the
  same anchor, so visual centering is always exact.
- One shared lyric baseline per layout, below all prior ink
  (`max(6.5, inkBottom + lyricGap + capHeight)`) — computed after
  ties/slurs/dynamics so nothing collides; no per-syllable skyline
  until a consumer needs stacked verses.
- Hyphens draw only when the estimated gap fits a dash; extenders run
  along the baseline under following voice-1 notes without their own
  syllable and stop at the next syllable.
- Widget tests default to the framework's box font; goldens opt into a
  real face via `CrispNotationTheme.textFontFamily: 'Roboto'`, loaded from
  the local Flutter SDK in `test_setup.dart` (no font asset added to
  the package).

## v0.4.5 chord symbols / annotations (2026-07-11)

- Reuses the lyric machinery mirrored upward: `Annotation` =
  center-anchored `TextPrimitive` on one shared baseline **above** all
  prior ink (`min(-1.0, inkTop - gap - descender)`), laid out after
  lyrics so the two never collide. Covers chord symbols, rehearsal
  marks and tempo text; no per-kind styling until a consumer needs it.
- Centered over the notehead (not left-aligned): matches lead-sheet
  conventions well enough and keeps `TextPrimitive` single-anchor.

## v0.5.1 MusicXML import (2026-07-11)

- **Zero-dependency constraint** rules out `package:xml`; a ~200-line
  internal reader (`src/musicxml/xml_reader.dart`) handles the XML
  subset MusicXML actually uses (prolog, DOCTYPE, comments, CDATA,
  entities). Not a general XML parser — namespaces and DTD content are
  out of scope.
- Durations map from `<type>` + `<dot>` when present (authoritative),
  falling back to duration/divisions arithmetic for whole-measure
  rests. `<backup>`/`<forward>` are ignored: voices are grouped by
  their `<voice>` label instead (first label seen per measure = our
  voice 1), which matches crisp_notation's two-voice model.
- Directions (dynamics, wedge starts) and `<harmony>` attach to the
  **next** note read; wedge stops anchor on the most recent note.
- Two id spaces (`e0…`, `e1000…`) keep grand-staff element ids unique
  across staves, as `GrandStaffView` requires.

## v0.5.2 MusicXML export (2026-07-11)

- Round-trip is the contract: `scoreFromMusicXml(scoreToMusicXml(s)) ==
  s` (deep value equality, ids included) for the whole supported
  subset — the test suite asserts it feature by feature.
- `<divisions>` = LCM of every duration's quarter-denominator
  (including tuplet-scaled effective durations), so all `<duration>`
  values are exact integers.
- Chord-symbol annotations export as `<kind text="…">other</kind>` —
  the annotation model keeps display text, not chord semantics, and
  the importer prefers the `text` attribute, closing the loop.
- Grand staffs export as two parts (`P1`/`P2`) rather than a two-staff
  part: simpler, and the importer accepts both shapes.

## v0.5.3 playback cursor (2026-07-11)

- Time is exact `Fraction` whole-notes, never floats — apps convert to
  seconds at the edge (`secondsFor`) so long scores cannot drift.
- Ties stay separate timeline entries (apps highlight both noteheads
  through the sustain); grace notes carry no time of their own.
- Repeat expansion supports one level with two passes; `volta: n`
  plays only on pass n. Nested/multi-ending structures are out of
  scope until a consumer needs them.
- Empty measures advance by the running meter (time changes followed
  in playback order), so cursor and barlines stay aligned.

## v0.5.4 transposition (2026-07-11)

- Key signatures transpose by moving the **major tonic** along the
  line of fifths (step index + 7·alter), then wrapping anything beyond
  ±7 by ±12 to its enharmonic key — exact, no semitone arithmetic.
- Everything except pitches and key signatures is carried over
  untouched, so ids (and with them highlights, taps, playback
  timelines, span attachments) survive transposition.
- Gotcha for consumers: Flutter's `material.dart` also exports an
  `Interval` (animation curve) — apps combining both should
  `import 'package:flutter/material.dart' hide Interval;`.

## v0.6.1 accidental stacking (2026-07-11)

- Zigzag column packing (top, bottom, next-from-top, …; rightmost
  column that clears every occupant by ≥ 6 staff positions). The
  6-position clearance is conservative — sharps/naturals are ~3 spaces
  tall; flats could pack tighter but a uniform rule keeps it
  predictable.
- Column width = widest glyph in the column, so mixed sharp/flat
  columns stay aligned on their right edge.
- All 38 pre-existing goldens passed unchanged — no earlier scene had
  a multi-accidental chord that the naive one-column-each rule and the
  new packing render differently.

## v0.6.2 ornaments (2026-07-11)

- One `Ornament?` per note (not a set): real scores hardly ever stack
  ornaments, and MusicXML's first ornament wins on import.
- Placement chains off the articulation pass: notehead-side marks →
  fermata (always above) → ornament on top, so combined marks never
  collide.
- DSL markers are single trailing characters like articulations:
  `%` trill, `\$` short trill, `&` mordent, `?` turn.

## v0.6.3 multi-measure rests (2026-07-11)

- One `Measure` with `multiRest: N` stands for N silent bars (no
  expansion into real measures) — layout draws a fixed-width H-bar,
  playback advances N × meter, MusicXML round-trips through
  `<measure-style><multiple-rest>`; whole-measure rest markup inside
  an imported multiple-rest is dropped as redundant.
- The count reuses the time-signature digit glyphs at y = −1.

## v0.6.4 octave clefs + ottava (2026-07-11)

- Octave clefs are just three more `Clef` values: all staff arithmetic
  flows from `bottomLineDiatonicIndex` (±7), key-signature tables copy
  the base clef, glyphs carry the printed 8.
- Ottavas shift **written** staff positions (±7) per spanned element
  id (`_writtenPosition`); the model keeps sounding pitches, so
  playback and transposition are unaffected by the bracket.
- The bracket is a `TextPrimitive` label + dashed `LinePrimitive`s +
  end hook, placed above/below all spanned ink.

## v0.6.5 cross-staff onset-column gridding (2026-07-11)

- The rule every serious engraver enforces: simultaneous notes align
  vertically across staves. Built as a shared per-measure column model —
  `alignedColumns(staves, settings)` (in `grand_staff.dart`) maps each
  onset `Fraction` to an x, gaps spaced by the optical time rule but
  floored by the *widest ink across all staves* at that column, fed to a
  new `LayoutEngine.layout(…, forcedColumns:)`. Each staff's single-voice
  path anchors its heads on the shared columns (`noteXOverride`).
- Opt-in via `gridAlign` (default true) on `layoutGrandStaff` /
  `layoutStaffSystem` / `layoutGrandStaffSystems` and their views; a staff
  that cannot align cleanly falls back to barline-only alignment.
- The shared column is the **notehead** x, not ink-left: keying on ink-left
  would let an accidental on only one staff's note at a beat shove that head
  right and break the vertical line. Instead each element's ink is split
  into left (accidental) and right (head/stem/dots); columns are spaced so
  one column's right ink never collides with the next column's left ink, and
  a lone accidental extends *left* of the shared column while the heads stay
  aligned.
- Justification composes rather than fights it: `alignedColumns` takes the
  binary-searched `spacingStretch`, so the width-fill search scales the
  shared grid uniformly instead of re-deriving columns per candidate and
  drifting the staves apart.
- Landed in four increments (grand staff → N-staff systems → 2–4-voice
  staves → accidental-aware columns) so each could re-render and pin its
  own goldens; the multi-voice case gathers onsets from every voice into the
  one grid.

## v0.6.6 additive / compound beam grouping (2026-07-11)

- `TimeSignature.beamGroups()` returns the metric beam-group lengths
  (`Fraction`s) for a measure, and the beam engine groups notes by them:
  an additive meter's `components` (3+2/8 → [3/8, 2/8]), a compound
  eighth-/sixteenth-unit meter grouped in threes (6/8, 9/8, 12/8),
  otherwise one group per beat.
- So 6/8 finally beams in threes instead of falling back to flags, and an
  additive meter beams by its written components rather than by a fictitious
  single beat. Simple x/4 meters resolve to one group per beat under the
  same rule, so no simple-meter golden moved — the change is inert where it
  should be.

## v0.6.7 notehead schemes (2026-07-11)

- `LayoutSettings.noteheadScheme` chooses a per-pitch notehead by its
  movable-do scale degree in the current key: `NoteheadScheme.sacredHarp`
  (four-shape) and `.aikin` (seven-shape) for shape-note singing, plus
  `.pitchName` (draws the letter C–G in place of the head) and `.solfege`
  (draws the syllable) as teaching aids — one enum, four schemes.
- Degree is taken against the key signature, so the shapes shift *with* the
  key (a key's relative minor shares them) — the whole point of movable-do;
  a fixed table would defeat it. An explicit per-note `NoteheadShape` still
  wins over the scheme (the note asked for a specific head). Exposed on the
  Flutter view as `StaffView.noteheadScheme`.

## v0.6.8 ink-skyline collision avoidance (Phase 1.2, 2026-07-11)

- The real engraving-quality gap, now closed. Every glyph's ink rectangle
  is recorded as it is placed (`_inkRects`, `(l, t, r, b)`); two helpers,
  `_skylineTop(xL, xR)` / `_skylineBottom(xL, xR)`, return the highest /
  lowest ink whose x-range overlaps a column. Every floating pass —
  accidentals, articulations, dynamics, ornaments, chord diagrams, slurs —
  now clears only the *actual ink in its own horizontal span*, not the
  system's global extremes, so a low note elsewhere on the line no longer
  shoves the chord symbols up or the lyrics down.
- Pass order is load-bearing: a query sees only ink placed so far, so each
  pass stacks above the marks already below it. Deliberately kept as a
  linear scan over the rect list — the column counts are small and it stays
  bit-for-bit deterministic (no spatial index, no float drift).

## v0.6.9 editor moat — overlays + imperative control (Phase 3.3/3.4/3.8, 2026-07-12)

- Design stance made explicit: **crisp_notation renders, the app drives.** The
  multi-line and grand-staff views gain repaint-only overlays —
  `errorOverlay` (`Map<String, EditorMark>`, each mark a `Color` + optional
  `message`, drawn as the element's ink color plus a small wedge above it),
  `loopRange` (`(startId, endId)`, a translucent band spanning systems /
  both staves), and `rectOfElement(id)` geometry on the render object. The
  `message` is *carried, not drawn* — the app surfaces it from its own
  `onElementTap` / `onHover` hit, so crisp_notation owns no tooltip UI.
- `ScoreEditorController` is a `ChangeNotifier` that is the single source of
  truth for a view's overlay state (`setLoop`/`clearLoop`,
  `mark`/`unmark`/`setMarks`, `highlight`/…), bound into the views via
  `AnimatedBuilder`. Crucially it drives an **app-owned** `ScrollController`
  rather than seizing the viewport: `attachViewport(scrollController:,
  rectOfElement:)`, then `scrollToNote(id, alignment:)` (or
  `offsetToReveal(id)` to compute the offset and animate it yourself). The
  app keeps ownership of scroll physics, focus and coordinate space.
- Caveat carried forward: a `GrandStaff` auto-numbers its upper and lower
  staff each from `e0…`, so element ids collide across the two staves —
  overlay maps and controller calls must disambiguate which staff they mean.

## v0.6.10 interactive grand staff + wrapped systems, contracts C1–C5 (2026-07-11)

- `MultiSystemView` and the new `InteractiveGrandStaffView` reach editor-hook
  parity: `onStaffTap` / `onElementTap`, `onHover(StaffTarget?)` (null on
  exit, via a `MouseTrackerAnnotation`), a full-height `EditorCaret`
  insertion bar, a `ghostTarget` + `ghostDuration` preview notehead, and
  `onElementDragStart/Update/End`. `StaffTarget` carries `systemIndex` +
  `staffIndex` (0 upper, 1 lower), so a hit resolves to the exact staff of
  the exact system on a wrapped, multi-staff score.
- Range geometry for app-side marquee / shift-click lives on the render
  objects: `elementRegions` (`(id, Rect bounds, measureIndex)` in local
  pixels, resolved across systems and both staves) and `elementIdsIn(Rect)`.
  `InteractiveGrandStaffView` wraps a two-clef `GrandStaff` into
  width-fitting systems via core `layoutGrandStaffSystems` (packed by the
  wider of the two staves so barlines stay aligned).

## v0.6.11 OMR — three engines through one command (2026-07-12)

- `crisp_notation omr` routes three CrispEmbed engines, auto-selected by dialect
  (`omrDialectOf` → `OmrDialect`): SMT `bekern` → grand staff, Polyphonic-
  TrOMR semantic → polyphonic staff, Flova simple-notes LilyPond
  (`scoreFromLilyNotes`) → handwritten single staff. `--page` splits a
  full-page scan into systems first (`segmentStaffSystems`, a pure-Dart
  horizontal-projection band splitter) and concatenates them; `--model
  <name>` auto-downloads the GGUF from Hugging Face by name and caches it.
- Division of labour is the point: token→score parsing stays **pure Dart**
  (testable without a model, web-safe, deterministic), and only the
  recognition engine is FFI. The whole pipeline is re-exported as
  `package:crisp_notation_cli/omr.dart`, so any Dart program where `dart:ffi`
  works can drive OMR — the CLI and Flutter desktop alike — not just the
  CLI binary. Web stays out of reach (no `dart:ffi`).

## v0.6.12 tablature technique depth (Phase 6.4, 2026-07-12)

- No new model where the notation model already carries the data: tab
  ornaments (trill/mordent/turn) and articulations (staccato/accent/
  marcato/tenuto/fermata) reuse `NoteElement.ornament` / `.articulations`,
  drawn above the fret by the tab engine — the same fields the notation
  engine reads.
- What notation genuinely lacks becomes per-note-id `Score` lists, each keyed
  by note id and ignored by the standard-notation engine so one score renders
  correctly both ways: `Rasgueado` (downward strum arrow), right-hand p-i-m-a
  fingering (`TabFingering` + `RightHandFinger`), `SlapPop`, `TremoloPicking`,
  plus bends / whammy / slides / strum / portamento.

## v0.6.13 microtones, non-standard keys, extra clefs (2026-07-12)

- `Pitch.microtone` (an optional `MicrotonalAccidental` — half / three-quarter
  sharp/flat, ±50 / ±150 cents) draws the Stein-Zimmermann quarter-tone
  glyphs and *always* shows (a quarter tone is never implied by the key
  signature). The integer `alter` and MIDI number are unchanged, so it is
  fully additive; `centsOffset` exposes the tuning for pitch-bend playback.
  Contract change: the prior "microtonal out" boundary is lifted.
- `KeySignature.custom([KeyAccidental(step, alter), …])` expresses
  modal / atonal signatures the circle of fifths cannot (a mixed B♭ + F♯, a
  non-traditional order). It drives both the drawn signature and
  note-accidental suppression, and is left *as written* under transposition —
  it has no tonic to move (the notes still transpose).
- Five more `Clef` values as C/G/F clefs on non-default lines —
  `frenchViolin`, `soprano`, `mezzoSoprano`, `baritone`, `subbass`. All staff
  arithmetic already flows from the clef's reference line, so each is a table
  entry rather than a code path.

## Blockers

(none)
