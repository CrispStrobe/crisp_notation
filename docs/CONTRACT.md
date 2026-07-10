# partitura — features and public API contract (v0.3-dev)

This document describes what partitura **does** and which API surface and
behaviors consumers may **rely on**. It reflects the implementation as
shipped; the original build brief lives in [HANDOVER.md](../HANDOVER.md)
(amended by [HANDOVER_PARTITURA.md](../HANDOVER_PARTITURA.md)), and the
reasoning behind non-obvious choices in [DESIGN.md](DESIGN.md).

Both packages are pre-1.0: minor versions may break APIs, but anything
listed under *Guarantees* below is treated as stable and only changes with
a documented migration note.

---

## 1. Packages

| Package | Platform | Depends on | Contents |
|---|---|---|---|
| `partitura_core` | any Dart | Dart SDK only (zero deps) | music theory, score model, deterministic layout engine, SMuFL metadata types |
| `partitura` | Flutter | Flutter + `partitura_core` (re-exported) | rendering (`StaffView`), interaction (`InteractiveStaff`), bundled Bravura font (SIL OFL 1.1) |

`partitura_core` must never gain a runtime dependency; `partitura` must
never gain one beyond Flutter + `partitura_core`. The Bravura font ships
unconverted, unsubset and unrenamed (OFL Reserved Font Name clause).

## 2. Binding conventions

These are load-bearing across both packages and the consuming apps.
Changing any of them is a breaking change:

- **Pitch**: scientific pitch notation; middle C = **C4** = MIDI **60**;
  octaves increment at C. Alterations are integers −2…2 (𝄫…𝄪).
- **Staff position**: `Pitch.staffPosition(clef)` → 0 = bottom staff line,
  +1 per line/space upward. Bottom lines: treble E4, bass G2, alto F3,
  tenor D3. Inverse: `Clef.pitchAt(position)`.
- **Layout space**: all layout output is in **staff spaces** (1 space =
  gap between adjacent staff lines). Origin = intersection of the staff's
  **top line** with its left edge; **y grows downward**; staff lines lie
  at y = 0…4; a staff position `p` maps to `y = (8 − p) / 2`.
- **Pixels**: rendering converts staff spaces → px with **one scale
  factor** (`staffSpace`), and SMuFL glyphs draw at font size =
  4 × staff space.
- **Geometry types**: `dart:math` `Point<double>` / `Rectangle<double>`
  (deliberately not Flutter's `Offset`/`Rect`, and deliberately no custom
  types of those names — see DESIGN.md).

## 3. Theory layer (`partitura_core`)

| Type | Contract |
|---|---|
| `Step` | 7 diatonic letters, `semitonesFromC` |
| `Pitch` | `midiNumber`, `diatonicIndex`, `staffPosition(clef)`, `transposeBy(interval, descending:)` (diatonic spelling; throws `ArgumentError` beyond double alterations), `isEnharmonicWith`, `Pitch.parse('f#3')` |
| `Clef` | `treble`, `bass`, `alto`, `tenor`; `pitchAt(staffPosition)`, `bottomLineDiatonicIndex` |
| `Interval` | quality d/m/P/M/A × number 1–8 (class-checked by assert); 15 named constants; `semitones`; order-insensitive `Interval.between(a, b)` ≤ one octave (throws if unnameable) |
| `NoteDuration` | base breve/whole…sixty-fourth × 0–2 dots; exact `(int, int) fraction` and `toFraction()` (breve = 2/1) |
| `Fraction` | exact, always reduced, sign on the numerator; `+ − × < ≤ > ≥ compareTo toDouble`; equal values are `==` and hash equally |
| `KeySignature` | fifths −7…7; `alteredSteps` in writing order (♯ F C G D A E B, ♭ B E A D G C F); `alterFor(step)` |
| `TimeSignature` | beats ≥ 1 over a power-of-two unit 1…16; `measureCapacity` as reduced fraction of a whole note |
| `Scale` | major, natural/harmonic/melodic (ascending) minor; `pitches` = 8 ascending pitches from the tonic, each letter used once, spelled diatonically |
| `Triad` | major/minor/diminished/augmented on a root, inversions 0–2 (`pitches` from the bass upward, ascending) |
| `Key` | `Key.major` / `Key.minor`; `signature` (throws beyond ±7 fifths); `triadFor(HarmonicFunction)`: major keys → all major; minor keys → t and s minor, **D major** (harmonic-minor convention) |

All theory types are immutable value types: `==`/`hashCode` are
value-based, invalid constructor arguments fail asserts in debug builds.

## 4. Score model (`partitura_core`)

- `Score` = clef + `KeySignature` (default C) + optional `TimeSignature`
  (null = unmetered: no time signature drawn, measure sums unchecked) +
  `List<Measure>`.
- `Measure` = ordered `List<MusicElement>` plus non-overlapping
  `TupletSpan`s (`actual` notes in the time of `normal` over a contiguous
  element range; cannot cross barlines), optional mid-score changes
  (`clefChange`, `keyChange` — with cancellation naturals, `timeChange`)
  taking effect at the measure, repeat flags (`startRepeat`/`endRepeat`)
  and a `volta` ending number. `effectiveDurationAt(i)` and
  `totalDuration` sum exactly with tuplet scaling — a triplet eighth
  sounds 1/12 (games compare against `TimeSignature.measureCapacity`; the
  layout engine does **not** enforce it).
- `MusicElement` (sealed) = `NoteElement` (1 pitch = note, n pitches =
  chord; `showAccidental`: `null` auto / `true` force / `false` hide;
  `tieToNext` ties to the next note element — identical pitches only,
  a tie into a rest draws nothing; `articulations`: staccato, tenuto,
  accent, marcato, fermata; `graceNotes`: an acciaccatura group drawn as
  small slashed eighths before the element) or `RestElement`.
- `Score.slurs`: `Slur(startId, endId)` phrasing curves between note
  elements; unknown or reversed ids throw at layout time.
- `Score.dynamics` (`DynamicMarking(elementId, pp…ff)`) and
  `Score.hairpins` (`Hairpin(startId, endId, crescendo|diminuendo)`) —
  model-only (no DSL shorthand); drawn on a dynamics line below the
  staff that drops beneath any low element ink. The optional `id` makes an element addressable by the
  interaction layer; ids should be unique per score.
- **Lists are treated as immutable.** Model equality is deep value
  equality over the given lists; mutating a list in place makes an "old"
  and "new" score compare equal and defeats change detection downstream
  (`StaffView` skips relayout for `==` scores). Copy lists per rebuild.

### `Score.simple` DSL

```text
notes    := measure ('|' measure)*        measures split on '|'
token    := rest | chord                  tokens split on whitespace
rest     := 'r' (':' duration)?
chord    := pitch ('+' pitch)* (':' duration)?
pitch    := [a-gA-G] ('##'|'#'|'bb'|'b'|'n')? octaveInt
duration := ('w'|'h'|'q'|'e'|'s') ('.' | '..')?
tie      := '~' at the end of a chord token (c4:q~)
slur     := '(' opens / ')' closes, at the end of a chord token
            (c4:q( d4 e4)) — may cross barlines, no nesting
tuplet   := 'actual[' or 'actual:normal[' opens, ']' closes
            (3[c4:e d4 e4]) — within one measure, no nesting; default
            normal = largest power of two below actual (3 for duplets)
artic    := trailing markers: ' staccato, _ tenuto, > accent,
            ^ marcato, @ fermata (combinable: c4:q>')
grace    := '{pitch,pitch}' prefix before the chord ({g4}a4:q)
directive:= measure-level tokens: !clef=bass, !key=-2, !time=3/4,
            !repeat, !endrepeat, !volta=1
```

Durations are sticky (initial default: quarter). `n` = explicit natural
and forces `showAccidental: true`. Elements auto-receive ids `e0, e1, …`
in reading order. Malformed input throws `FormatException` naming the
offending token.

## 5. Layout engine (`partitura_core`)

`const LayoutEngine().layout(score, settings)` → `ScoreLayout`.

- `LayoutSettings(metadata: …)`: engraving values (staff line/stem/ledger/
  beam/barline thicknesses, ledger extension) default to the font's
  `engravingDefaults`; spacing policy (padding, gaps, `spacingBase`,
  `spacingPerLog2`, `minNoteGap`, `stemLength` 3.5) is partitura's own and
  overridable per instance.
- `SmuflMetadata.fromJson(...)` parses a SMuFL font metadata file
  (engraving defaults, glyph bounding boxes, stem anchors); core never
  loads assets itself. Unknown glyph lookups throw `ArgumentError`.
- `ScoreLayout` exposes `width`, `height`, `top` (≤ 0; ink rises above
  the top staff line), `bounds`, a flat painting-ordered `primitives`
  list (`GlyphPrimitive` = SMuFL name + origin, `LinePrimitive`,
  `BeamPrimitive` = end-edge midpoints + thickness,
  `CurvePrimitive` = cubic Bézier for ties/slurs), per-element
  `regions` (hit boxes for every id-tagged element) and `measureRegions`
  (x-extents per measure; empty measures are zero-width).
- Primitives tagged with an `elementId` are that element's ink;
  untagged glyph/line primitives are staff furniture; beams are untagged
  shared note ink.

### Engraving rules implemented

Clef anchoring (gClef on G4, fClef on F3, cClef on C4 — middle line for
alto, fourth line for tenor) · key signatures at conventional octaves per
clef (bass/alto = treble − 2/− 1 positions; tenor uses its own sharp
pattern and flats one position above treble) · stacked
time-signature digits centered on the staff · noteheads by duration (incl. the
stemless breve) · stems (down iff the notehead farthest from the middle
line is at position ≥ 4; chords by the farther extreme, ties down;
default length 3.5 spaces, extended to the middle line for far ledger
notes and by 0.75/level for 3rd/4th beam-or-flag levels) · flags for
unbeamed eighths…sixty-fourths · beat-based beaming (windows of
`1/beatUnit`; adjacent all-eighth groups merge per half measure in even
x/4 meters — 8 eighths in 4/4 = 2 beams; never across rests or windows;
slant clamped to ±1 space; every beamed stem keeps ≥ default length; the
beam never crosses the middle line from the stem side; secondary/tertiary/quaternary
beams per duration level and 1-space beamlets) · ledger lines with
`legerLineExtension` on both sides spanning all chord columns ·
accidentals with per-measure, per-(step, octave) memory
(`showAccidental` overrides; hidden ones don't update the memory) ·
augmentation dots (line-notes dot the space above; rest dots in the
third space) · chords on one shared stem with seconds flipped across it ·
rests at conventional homes (whole hangs from line 4, half sits on
line 3) · duration-proportional spacing
(`spacingBase + spacingPerLog2 · (4 + log₂ duration)`, min gap enforced) ·
thin barlines between measures, thin+thick final barline · ties on
the notehead side away from the stem, across barlines, chords tying
pairwise by identical pitch · slurs above unless every spanned note stems
up, arcing clear of everything in between · tuplet digit + bracket on the
group's stem side; tuplet members space at their sounding width, beam
within their beat window and never beam across the tuplet boundary ·
articulations on the notehead side (opposite the stem), stacked outward
in enum order; fermatas always above and outside the staff · dynamics
glyphs centered under their element; hairpin wedges between element
centers on the same dynamics line · grace notes as 0.6× glyphs
(`GlyphPrimitive.scale`), stems always up, slash on the first stem,
small ledger lines · mid-score changes at the measure start (0.8× clef,
cancellation naturals before a new key, fresh time digits; notes and
beam windows follow the current state) · repeat barlines with SMuFL
repeat dots · volta brackets with ending numbers above the staff.

Caveat: interaction quantization (`StaffTarget.pitchFor`) takes an
explicit clef — apps using mid-score clef changes must map per measure.

**Not implemented (v0.x non-goals)**: multi-voice collision avoidance,
slurs/ties, tuplets, grace notes, cross-staff beaming, lyrics, dynamics,
articulations, line breaking/justification, grand staff, MusicXML,
audio (never), transposing instruments, tablature, compound-meter beam
grouping (x/8 meters render flags). Alto/tenor clefs shipped in v0.2.

## 6. Rendering (`partitura`)

- `Bravura.load()` — parses the bundled font metadata once (async,
  cached, single-flight; failures are not cached and retry). Apps should
  `await` it in `main()`; otherwise the first `StaffView` frame is empty
  and the widget self-heals when the load completes.
- `StaffView(score, theme, staffSpace, highlightedIds, onElementTap)` —
  a `LeafRenderObjectWidget`. `staffSpace` = px per staff space; `null`
  fits the available width. Glyphs paint via `TextPainter`
  (baseline-anchored, font size = 4 × staff space).
- `PartituraTheme` — `staffColor` (furniture), `noteColor` (element ink),
  `highlightColor` (wins over everything), `elementColors` per-id
  overrides, `kidMode`/`hitSlop`/`lineBoost`. Presets: `standard`, `kids`
  (hit slop 1.5 spaces, line boost 1.4). Value type with `copyWith`.
- `RenderStaffView` is public as the geometry service: `scoreLayout`,
  `scale`, `localToStaff`/`staffToLocal`, `elementIdAt`,
  `quantizeStaffPosition`, `ghostNote`.

## 7. Interaction (`partitura`)

`InteractiveStaff(score, theme, staffSpace, highlightedIds, onElementTap,
onStaffTap, showGhostNote, ghostDuration)`:

- Tap on an element (hit box inflated by `theme.hitSlop`) →
  `onElementTap(id)`. Overlapping regions resolve to the **smallest**
  containing one. Kid mode yields ≥ 44×44 px targets at the default
  12 px staff space.
- Tap or drag-drop on empty staff → `onStaffTap(StaffTarget)`, quantized
  to the nearest line/space, clamped to positions −6…14; a drop onto an
  element fires nothing. `StaffTarget.pitchFor(clef, preferredAlter:)`
  maps back to a pitch.
- While dragging (and `showGhostNote`), a semi-transparent quantized
  ghost notehead of `ghostDuration` (with preview ledger lines) follows
  the pointer and vanishes on release.
- Selection is app state: pass `highlightedIds` down; partitura never
  stores a selection.

## 8. Guarantees

1. **Determinism**: identical `Score` + `LayoutSettings` produce an
   identical `ScoreLayout` — no randomness, clock or platform dependence.
   (Golden images additionally depend on the platform's font rasterizer;
   the committed goldens are macOS.)
2. **Repaint-only highlights**: changing `highlightedIds`,
   `elementColors`, other colors, or `ghostNote` never relayouts — the
   `ScoreLayout` instance is reused. Changing `score`, `staffSpace` or
   `theme.lineBoost` relayouts.
3. **Value semantics**: all model/theory types compare by value; a
   value-equal score swap is a no-op (see the list-immutability rule in
   §4).
4. **Loud failures**: unspellable transpositions, out-of-range
   signatures, unnameable intervals and unknown glyphs throw
   (`ArgumentError`); malformed DSL throws `FormatException`; invalid
   constructor arguments fail asserts in debug builds. Nothing degrades
   silently.
5. **Zero dependencies** and the licensing rules of §1.

## 9. Quality gates

Every commit: `dart format` clean, `flutter analyze` zero issues under
strict lints (incl. `public_member_api_docs`), all tests green:

| Suite | Scope |
|---|---|
| `partitura_core` unit tests (230+) | theory tables + property sweeps, layout rules 1–14, layout edge/quality suites, DSL, SMuFL parsing, validation |
| `partitura` widget tests (70+) | sizing, hit testing, gestures, ghost lifecycle, repaint/relayout policy, asset loading, pixel-level paint verification |
| Golden corpus (25 scenes + hero) | all four clefs, all durations, dots, accidentals, chords, beams, rests, signatures, highlights, kid mode, ghost, fit-to-width (macOS-generated) |
| Example widget tests + integration test | real app boot, gallery scroll, place/select/clear flow, duration & clef controls — `flutter test integration_test -d macos` |
