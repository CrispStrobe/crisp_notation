# partitura — design log

Running log of non-obvious decisions and their rationale. Append as you go;
terse is fine. See HANDOVER.md §6.

## Pre-seeded decisions (scaffold, 2026-07-10)

- **Naming**: the project was scaffolded as "neume" and renamed to
  "partitura" the same day (maintainer decision). HANDOVER.md still says
  neume; HANDOVER_PARTITURA.md is the binding amendment.
- **Coordinate system**: layout works in *staff spaces* (1 space = gap between
  adjacent staff lines), origin at the intersection of the staff's top line
  and left edge, y grows downward. Rendering converts to px with one scale
  factor. SMuFL convention: font size = 4 × staff space.
- **Staff position convention**: `Pitch.staffPosition(clef)` returns 0 for the
  bottom line, +1 per line/space upward (treble: E4 = 0; bass: G2 = 0).
- **Two packages, not three**: layout stays in `partitura_core` (pure Dart,
  logic testable without Flutter); a separate layout package added friction
  without a consumer that wants layout-but-not-theory.
- **No dependencies**: theory core is small at our scope; owning it keeps the
  MIT story clean and lets the model be shaped for pedagogy
  (`Key.triadFor(HarmonicFunction)` etc.).

## M1 — theory core (2026-07-10)

- **`showAccidental` is `bool?`, not `bool`**: HANDOVER.md §4.1 declares
  `final bool showAccidental` but describes tri-state semantics
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

- **Geometry types**: HANDOVER.md's pseudo-code uses `Offset`, but
  `partitura_core` cannot depend on Flutter. We use `dart:math`'s
  `Point<double>` / `Rectangle<double>` (SDK-only). Deliberately NOT a
  custom class named `Offset`/`Rect` — that would collide with `dart:ui`
  in every consumer that imports both Flutter and partitura.
- **y of a staff position**: `y = (8 - p) / 2` (origin top line, y down).
- **Metadata flow**: core cannot load assets; the consumer decodes
  `bravura_metadata.json` and passes it via
  `SmuflMetadata.fromJson` → `LayoutSettings(metadata: …)`. Core tests read
  the file from `../partitura/assets/` directly. Glyph metrics (bboxes,
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
  technique, kept per HANDOVER_PARTITURA §2). Painters cached per
  (glyph, color), cache cleared on relayout/theme change.
- **Kid mode** is implemented as data on the theme (`hitSlop`,
  `lineBoost`) rather than behavior switches, so games can tune both
  independently. `lineBoost` feeds the layout settings (thicker primitives
  move ink bounds), so toggling it relayouts; pure color changes only
  repaint.
- **Goldens** (21 scenes) were generated on **macOS** with Flutter 3.44.4;
  font rendering differs across platforms, so run them on macOS or
  regenerate locally (`flutter test --update-goldens`).
- **Example app** is a workspace member (`packages/partitura/example` in
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
  Archive: partitura ≈ 856 KB compressed, dominated by the unmodified
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
  tests), theme/geometry/gesture contracts and two new goldens (partitura
  64 tests), example control-flow tests and an extended on-device
  integration run. Full inventory in docs/CONTRACT.md §9.
- **Library fix found by the retry test**: `Bravura.load()` cached a
  *failed* future forever — one flaky asset read would have blanked every
  StaffView until restart. Failures now clear the pending future so the
  next call retries.
- **docs/CONTRACT.md** is the consumer-facing description of features and
  API guarantees (HANDOVER.md stays the historical build brief). Keep it
  in sync when the public surface changes; READMEs link to it.
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
- Volta numbers reuse the SMuFL tuplet digits at 0.8× — partitura still
  has no text primitive; revisit when lyrics (v0.4) introduce one.
- Interaction quantization still maps via one clef; documented caveat in
  CONTRACT.md until the geometry API grows per-measure clefs.

## Blockers

(none)
