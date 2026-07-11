# partitura — features and public API contract (v0.4-dev)

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
- `Measure` = ordered `List<MusicElement>` (voice 1) plus an optional
  `voice2` (DSL `;`): voice 1 stems up / voice 2 down, onsets align in
  columns, rests displace vertically, cross-voice unisons/seconds shift
  voice 2 rightward; ties bind per voice, accidental state is shared;
  tuplets and directives are voice-1 only. Plus non-overlapping
  `TupletSpan`s (`actual` notes in the time of `normal` over a contiguous
  element range; cannot cross barlines), optional mid-score changes
  (`clefChange`, `keyChange` — with cancellation naturals, `timeChange`)
  taking effect at the measure, repeat flags (`startRepeat`/`endRepeat`),
  a `volta` ending number and an optional `navigation` mark
  (`NavigationMark`: segno/coda targets drawn at the measure start, and the
  D.C./D.S./To Coda/Fine instruction words — incl. *al Coda*/*al Fine* —
  drawn at its end; rendered and MusicXML-round-tripped, but the playback
  timeline does not yet execute the jumps). `effectiveDurationAt(i)` and
  `totalDuration` sum exactly with tuplet scaling — a triplet eighth
  sounds 1/12 (games compare against `TimeSignature.measureCapacity`; the
  layout engine does **not** enforce it).
- `MusicElement` (sealed) = `NoteElement` (1 pitch = note, n pitches =
  chord; `showAccidental`: `null` auto / `true` force / `false` hide;
  `tieToNext` ties to the next note element — identical pitches only,
  a tie into a rest draws nothing; `articulations`: staccato, tenuto,
  accent, marcato, fermata; `graceNotes`: an acciaccatura group drawn as
  small slashed eighths before the element; `fingerings`: digits 0–9
  stacked above the note, list order from the notehead upward; `arpeggio`:
  `Arpeggio.up`/`down`, a rolled-chord wavy line left of the chord;
  `tremolo`: 1–5 stroke count drawn through the stem, stemmed notes only)
  or `RestElement`.
- `Score.slurs`: `Slur(startId, endId)` phrasing curves between note
  elements; unknown or reversed ids throw at layout time.
- `Score.glissandos`: `Glissando(startId, endId)` straight slide lines
  between two notes (model-only); same id/order rules as slurs.
- `Score.pedals`: `Pedal(startId, endId)` sustain-pedal spans (model-only);
  "Ped." under the start note and a release star under the end, below the
  staff.
- `Score.featheredBeams`: `FeatheredBeam(startId, endId, {beginBeams,
  endBeams})` (model-only) — forces the spanned notes into one beam group and
  fans the beam count from `beginBeams` to `endBeams` (accelerando if growing,
  ritardando if shrinking).
- `Score.beamSlants`: `BeamSlant(startId, endId, {slant})` (model-only) —
  forces the spanned notes into one beam group with a fixed slant (staff
  spaces, y-down; 0 = horizontal).
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
ornament := trailing marker (one per note): % trill, \$ short trill,
            & mordent, ? turn
finger   := '=' digit(s) suffix: =3 one finger, =1,3,5 per chord tone
            (c4:q=3, c4+e4+g4:h=1,3,5); may precede other markers (c4:q=2~)
grace    := '{pitch,pitch}' prefix before the chord ({g4}a4:q)
directive:= measure-level tokens: !clef=bass, !key=-2, !time=3/4,
            !repeat, !endrepeat, !volta=1, !mrest=N,
            !nav=<mark> (segno, coda, toCoda, daCapo, daCapoAlFine,
            daCapoAlCoda, dalSegno, dalSegnoAlFine, dalSegnoAlCoda, fine)
voices   := ';' splits a measure into voice 1 and voice 2
            (c5:q d5 ; c4:h)
```

Durations are sticky (initial default: quarter). `n` = explicit natural
and forces `showAccidental: true`. Elements auto-receive ids `e0, e1, …`
in reading order. Malformed input throws `FormatException` naming the
offending token.

The separate `lyrics:` parameter attaches syllables to voice-1 note
elements in reading order (rests are skipped): whitespace-separated
tokens; `*` skips a note, a trailing `-` hyphenates to the next
syllable, a trailing `_` starts a melisma extender
(`lyrics: 'Twin- kle * star_'`). Model type: `Lyric(elementId, text,
hyphenToNext:, extender:)` in `Score.lyrics`. More tokens than notes
throw `FormatException`.

The `annotations:` parameter works the same way but places text
**above** the staff (chord symbols, rehearsal marks, tempo text): `*`
skips a note (`annotations: 'C * G7 *'`). Model type:
`Annotation(elementId, text)` in `Score.annotations`.

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
  `CurvePrimitive` = cubic Bézier for ties/slurs,
  `TextPrimitive` = plain text anchored center-baseline with an em size
  in staff spaces — core estimates text widths at 0.5 em/char, painters
  center the real text on the anchor), per-element
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
repeat dots · volta brackets with ending numbers above the staff ·
navigation marks on one shared line above the staff per system (segno/coda
glyphs at the measure start, D.C./D.S./To Coda/Fine words right-aligned at
its end) · fingering digits stacked above the note (clear of the notehead,
stem and any articulation/ornament ink) · arpeggio as a vertical wavy line
(tiled `wiggleArpeggiatoUp`) just left of the chord, capped by an up/down
direction arrowhead · glissando as a straight line between two noteheads ·
tremolo strokes (`tremolo1`…`tremolo5`) centered on the stem · sustain-pedal
"Ped."/release-star marks below the staff.

Caveat: interaction quantization (`StaffTarget.pitchFor`) takes an
explicit clef — apps using mid-score clef changes must map per measure.

**Guitar/bass tablature** (v0.8, in progress): `TabLayoutEngine.layout(score,
tuning, settings)` renders a `Score`'s pitches as fret numbers on an N-line
string staff, using a `Tuning` (open-string pitches; `Tuning.standardGuitar`
/ `dropDGuitar` / `standardBass`, or custom). `Tuning.fretFor(pitch)` assigns
the lowest playable (string, fret). `TabStaffView` is the Flutter widget.
Rhythm stems/beams and playing techniques are drawn by the tab engine only
(they are inert in standard-notation rendering) and are added incrementally.
Supported so far: slides (reuse `Score.glissandos`), hammer-on/pull-off
(reuse `Score.slurs`), string bends (`Score.bends` — `Bend(noteId, {steps})`,
an upward arrow with a ½/full/1½ amount label) and vibrato (`Score.vibratos`
— `Vibrato(noteId, {wide})`, a wavy line above the fret; `wide` enlarges the
wave). Still to come: harmonics, palm mute, dead/ghost notes, tapping…
*(This lifts the former "tablature out" clause — a consumer requested it.)*

**Not implemented (v0.x non-goals)**: multi-voice collision avoidance,
cross-staff beaming, audio (never),
transposing instruments, compound-meter beam grouping (x/8
meters render flags). Alto/tenor clefs shipped in v0.2; slurs/ties,
tuplets, grace notes, articulations and dynamics in v0.3; two voices,
grand staff, line breaking, lyrics and chord symbols/annotations in
v0.4.

## 5b. MusicXML import & export (`partitura_core`)

Export: `scoreToMusicXml(score)` / `grandStaffToMusicXml(grandStaff)`
(two parts P1/P2). Round-trip guarantee: re-importing an exported
document yields a value-equal `Score`.

Import: `scoreFromMusicXml(xml, {partIndex})` → `Score`;
`grandStaffFromMusicXml(xml)` → `GrandStaff` (a two-staff part, or the
first two parts). Subset: the v0.3/v0.4 feature set over
`score-partwise` documents; unsupported markup is skipped, documents
the subset cannot represent throw `FormatException`. Elements get ids
`e0, e1, …` in reading order (`e1000…` on the lower staff). No file
I/O — pass the document contents as a string. Dependency-free (core
ships its own minimal XML reader).

## 5c. Playback cursor (`partitura_core`)

`playbackTimeline(score, {expandRepeats = true})` → sorted
`List<PlaybackNote>` (`elementId`, `start`/`duration` as whole-note
`Fraction`s, `isRest`, `voice`, `measureIndex`); repeats play twice,
voltas pick their pass. `soundingAt(timeline, time)` → the ids to
highlight (rests excluded). `secondsFor(wholeNotes, quarterBpm:)` maps
musical time to seconds. **No audio, ever** — apps bring their own
synth and drive `highlightedIds` from this timeline.

## 5d. Transposition (`partitura_core`)

`score.transposedBy(interval, descending: false)` → a new `Score` with
every pitch (chords, both voices, grace notes), the key signature and
mid-score key changes moved; keys beyond ±7 accidentals wrap to the
enharmonic equivalent. Ids, rhythm, spans, lyrics and annotation text
stay unchanged, so highlights/taps/playback keep working. Note:
Flutter's `material.dart` also exports an `Interval` — `hide Interval`
on the material import when using both.

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
  overrides, `kidMode`/`hitSlop`/`lineBoost`, `textFontFamily` for
  lyrics/annotations (null = platform default). Presets: `standard`,
  `kids` (hit slop 1.5 spaces, line boost 1.4). Value type with
  `copyWith`.
- `GrandStaffView(grandStaff, …)` renders a `GrandStaff` (two scores):
  measures align across staves via a two-pass layout
  (`layoutGrandStaff` in core, `leadingWidth`/`measureWidths` minimums
  on `LayoutEngine.layout`), joined by a stretched SMuFL brace and
  connected barlines; element taps resolve on both staves (keep ids
  unique across the two scores).
- `MultiSystemView(score, theme, staffSpace, systemGap, justify,
  highlightedIds, onElementTap)` wraps a score into systems that fit the
  available width (sheet-music style) and rebreaks on resize. Line
  breaking lives in core: `layoutSystems(score, settings, maxWidth: …,
  justify: …)` → `MultiSystemLayout` (greedy packing; clef/key restated
  per system; time signature drawn only on the first system yet still
  governing beaming; slurs/dynamics/hairpins that would span a break are
  dropped; non-final systems justified via uniform spacing stretch; thin
  closing barline on continuing systems, `barlineFinal` only at the
  end). `staffSpace` is fixed here — the width budget drives breaking.
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
