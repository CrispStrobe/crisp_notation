# crisp_notation — features and public API contract (v0.4)

This document describes what crisp_notation **does** and which API surface and
behaviors consumers may **rely on**. It reflects the implementation as
shipped; active development follows [PLAN.md](../PLAN.md), and the reasoning
behind non-obvious choices is in [DESIGN.md](DESIGN.md).

All three packages are pre-1.0: minor versions may break APIs, but anything
listed under *Guarantees* below is treated as stable and only changes with
a documented migration note.

---

## Contents

- [1. Packages](#1-packages)
- [2. Binding conventions](#2-binding-conventions)
- [3. Theory layer](#3-theory-layer-crisp_notation_core)
- [4. Score model](#4-score-model-crisp_notation_core) · [`Score.simple` DSL](#scoresimple-dsl)
- [5. Layout engine](#5-layout-engine-crisp_notation_core) · [Engraving rules](#engraving-rules-implemented) · [Systems & gridding](#systems--cross-staff-onset-column-gridding) · [Pagination](#pagination)
- Interchange & export: [5b. MusicXML](#5b-musicxml-import--export-crisp_notation_core) · [5c. Playback cursor](#5c-playback-cursor-crisp_notation_core) · [5d. Transposition](#5d-transposition-crisp_notation_core) · [5e. MIDI](#5e-midi-import--export-crisp_notation_core) · [5f. SVG](#5f-svg-export-crisp_notation_core) · [5g. ABC](#5g-abc-notation-crisp_notation_core) · [5h. Multi-part & staff systems](#5h-multi-part-scores--staff-systems-crisp_notation_core) · [5i. OMR](#5i-optical-music-recognition-crisp_notation_core--crisp_notation_cli)
- [6. Rendering](#6-rendering-crisp_notation)
- [7. Interaction](#7-interaction-crisp_notation)
- [8. Guarantees](#8-guarantees)
- [9. Quality gates](#9-quality-gates)

---

## 1. Packages

| Package | Platform | Depends on | Contents |
|---|---|---|---|
| `crisp_notation_core` | any Dart | Dart SDK only (zero deps) | music theory, score model, deterministic layout engine, SMuFL metadata types |
| `crisp_notation` | Flutter | Flutter + `crisp_notation_core` (re-exported) | rendering (`StaffView`), interaction (`InteractiveStaff`), bundled Bravura font (SIL OFL 1.1) |
| `crisp_notation_cli` | any Dart | `crisp_notation_core` + `ffi`, `image` | the `crisp_notation` command: inspect, convert, render SVG/PNG, OMR |

`crisp_notation_core` must never gain a runtime dependency; `crisp_notation` must
never gain one beyond Flutter + `crisp_notation_core`. The zero-dependency rule
binds those two only — `crisp_notation_cli` is a tool, not a library, and may
take dependencies. The Bravura font ships unconverted, unsubset and unrenamed
(OFL Reserved Font Name clause).

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

## 3. Theory layer (`crisp_notation_core`)

| Type | Contract |
|---|---|
| `Step` | 7 diatonic letters, `semitonesFromC` |
| `Pitch` | `midiNumber`, `diatonicIndex`, `staffPosition(clef)`, `transposeBy(interval, descending:)` (diatonic spelling; throws `ArgumentError` beyond double alterations), `isEnharmonicWith`, `Pitch.parse('f#3')` |
| `Clef` | `treble`, `bass`, `alto`, `tenor`, octave clefs (`treble8va`/`treble8vb`/`bass8vb`), the C/F positions `frenchViolin`/`soprano`/`mezzoSoprano`/`baritone`/`subbass`, and neutral `percussion`; `pitchAt(staffPosition)`, `bottomLineDiatonicIndex` |
| `Interval` | quality d/m/P/M/A × number 1–8 (class-checked by assert); 15 named constants; `semitones`; order-insensitive `Interval.between(a, b)` ≤ one octave (throws if unnameable) |
| `NoteDuration` | base breve/whole…sixty-fourth × 0–2 dots; exact `(int, int) fraction` and `toFraction()` (breve = 2/1) |
| `Fraction` | exact, always reduced, sign on the numerator; `+ − × < ≤ > ≥ compareTo toDouble`; equal values are `==` and hash equally |
| `KeySignature` | fifths −7…7; `alteredSteps` in writing order (♯ F C G D A E B, ♭ B E A D G C F); `alterFor(step)` |
| `TimeSignature` | beats ≥ 1 over a power-of-two unit 1…16; `measureCapacity` as reduced fraction of a whole note |
| `Scale` | major, natural/harmonic/melodic (ascending) minor; `pitches` = 8 ascending pitches from the tonic, each letter used once, spelled diatonically |
| `Triad` | major/minor/diminished/augmented on a root, inversions 0–2 (`pitches` from the bass upward, ascending) |
| `Key` | `Key.major` / `Key.minor`; `signature` (throws beyond ±7 fifths); `triadFor(HarmonicFunction)`: major keys → all major; minor keys → t and s minor, **D major** (harmonic-minor convention) |
| `ChordAnalysis` | chord identification (the inverse of `Triad`): `identifyChord(pitches)` → root/`ChordType`/inversion/bass (null under 3 distinct pitch classes or with no template match), `symbol` (`Am7`, `C/E`), `chordSymbolFor(pitches)`, `chordReadings(pcs, {bassPc})` for all enharmonic re-readings. `ChordType` is an enhanced enum of 29 templates (triads, sevenths, sixths, 9ths/11ths/13ths, and the augmented sixths `It+6`/`Fr+6`/`Ger+6`, matched by spelling — `isAugmentedSixth`) |
| `RomanNumeral` | bidirectional harmonic analysis: `romanNumeralFor(chord, key)`, `romanNumeralOf(pitches, key)` → degree, `alteration`, `ChordType`, `inversion`, secondary `appliedTo`; `figure` (figured-bass) and `symbol` (`V6/5`, `vii°7`, `bVI`, `V7/V`); `pitchClassesOf(rn, key)` realizes it back to pitch classes |
| Key finding | Krumhansl-Schmuckler over Krumhansl-Kessler profiles: `findKey(weights)` (12-element vector, index 0 = C; null if empty/all-zero), `keyOf(pitches, {durations})`, `localKeys(pitches, {window = 8, step = 1})` as a sliding-window modulation tracker |
| Voice leading | `checkVoiceLeading(chords)` → `List<VoiceLeadingIssue>` (`rule`, `chordIndex`, `upperVoice`, `lowerVoice`) over `VoiceLeadingRule`: parallel/hidden fifths & octaves, voice crossing, voice overlap, spacing. Each chord is ordered top voice (index 0) down to bass; for motion rules `chordIndex` is the **second** chord of the pair |
| Set theory | post-tonal pitch-class sets: `pitchClassSet(pitches)`, `transposeSet`, `invertSet`, `normalForm`, `primeForm` (Forte), `intervalClassVector`, `zRelated(a, b)`, `forteNumber(pcs)` (null for the empty set **and for hexachords** — that catalogue is not transcribed) |
| Twelve-tone | serial row operations: `transposeRow(row, n)`, `retrograde`, `invertRow` (about the row's **first** note), `retrogradeInversion`, `twelveToneMatrix(row)` (throws `ArgumentError` unless `row` is a permutation of 0–11) |
| Neo-Riemannian | `extension NeoRiemannian on Triad` — `parallel` (P), `relative` (R), `leittonwechsel` (L). All three throw `StateError` on a non-major/minor triad |
| Scale matching | `matchingScales(pcs)` → every `Scale` (all 12 tonics × `ScaleType`) containing `pcs`, best fit first (rooted-in-set before merely-containing, then major before minor modes, then by tonic); `[]` if none |
| `Tempo` | `Tempo(bpm, {beatUnit = DurationBase.quarter, dots = 0})` (asserts 0–2 dots); `quarterBpm` normalizes beat unit + dots to quarter-BPM (dotted-quarter@80 → 120). Carried by `Score` (initial) and `Measure.tempoChange` |

All theory types are immutable value types: `==`/`hashCode` are
value-based, invalid constructor arguments fail asserts in debug builds.

## 4. Score model (`crisp_notation_core`)

- `Score` = clef + `KeySignature` (default C) + optional `TimeSignature`
  (null = unmetered: no time signature drawn, measure sums unchecked) +
  `List<Measure>`.
- `Measure` = ordered `List<MusicElement>` (voice 1) plus up to three more
  voices (`voice2`/`voice3`/`voice4`, DSL `;`): odd voices (1, 3) stem up, even
  voices (2, 4) stem down, onsets align in columns, rests displace vertically,
  cross-voice unisons/seconds shift the lower voice rightward; ties bind per
  voice, accidental state is shared;
  tuplets and directives are voice-1 only. Plus non-overlapping
  `TupletSpan`s (`actual` notes in the time of `normal` over a contiguous
  element range; cannot cross barlines), optional mid-score changes
  (`clefChange`, `keyChange` — with cancellation naturals, `timeChange`)
  taking effect at the measure, repeat flags (`startRepeat`/`endRepeat`),
  a `volta` ending number and an optional `navigation` mark
  (`NavigationMark`: segno/coda targets drawn at the measure start, and the
  D.C./D.S./To Coda/Fine instruction words — incl. *al Coda*/*al Fine* —
  drawn at its end; rendered, MusicXML-round-tripped, and executed as jumps
  by `playbackTimeline`). `effectiveDurationAt(i)` and
  `totalDuration` sum exactly with tuplet scaling — a triplet eighth
  sounds 1/12 (games compare against `TimeSignature.measureCapacity`; the
  layout engine does **not** enforce it). A short opening bar under a known
  meter is auto-detected as a `Measure.pickup` (anacrusis).
  `Score.barNumberAt(index)` (C9) gives the displayed bar number with the pickup
  uncounted — 1-based over non-pickup measures, `null` for a pickup itself; the
  measure-number overlay and the MEI writer both use it. Further `Measure`
  fields: `inlineClefs` (`List<InlineClefChange>` — `InlineClefChange(onset,
  clef)`, a clef change drawn mid-measure at its onset), `measureRepeat` (`int?`
  — a 1/2/4-bar simile repeat sign, requires empty `elements`), `actualDuration`
  (`Fraction?` — an explicit intended bar length overriding the meter for an
  irregular bar; it also suppresses pickup auto-detection), `barline`
  (`BarlineStyle`, default `normal` — the closing right-barline style, overridden
  when `endRepeat` is set) and `tempoChange` (`Tempo?` — a metronome change at
  the measure start).
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
  elements; a span whose ids are unknown or reversed is **skipped**, not drawn
  (see *Dangling spans* below).
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
- `Score.chordSymbols`: `ChordSymbol(elementId, root, quality, {bass})`
  structured lead-sheet harmony above a note — unlike text `annotations`, the
  root/bass are real `Pitch`es, so they transpose with the music (model-only).
- `Score.portamentos`: `Portamento(startId, endId)` curved-slide lines between
  note elements (model-only); same id/order rules as slurs.
- `Score.crossMeasureBeams`: `CrossMeasureBeam(startId, endId)` (model-only) —
  forces the spanned notes into one beam group continued across a barline.
- `Score.ottavas`: `Ottava(startId, endId, {down})` an 8va (`down: false`,
  bracket above) or 8vb (`down: true`, bracket below) octave-transposition line
  over the spanned notes (model-only).
- `Score.breathMarks`: `BreathMark(noteId, BreathSymbol)` breath mark / caesura
  drawn after a note element (model-only).
- `Score.jazzMarks`: `JazzMark(noteId, JazzArticulation)` jazz / brass
  articulations (scoop, doit, fall, plop, and lift/flip/smear/bend) on a note
  element — the model container behind the §5 jazz-articulation rendering.
- **Lists are treated as immutable.** Model equality is deep value
  equality over the given lists; mutating a list in place makes an "old"
  and "new" score compare equal and defeats change detection downstream
  (`StaffView` skips relayout for `==` scores). Copy lists per rebuild.

- **Accessibility**: `semanticLabel(element)` → a screen-reader string
  (`"C sharp 4 quarter note"`, `"C 4, E 4, G 4 chord, half note"`,
  `"quarter rest"`); `semanticLabels(score)` → `Map<String, String>` id → label
  for every **identified** element across `measure.elements` and
  `voice2`…`voice4`. Handles microtonal accidentals and breve…64th with
  dotted/double-dotted prefixes.

### `Score.simple` DSL

```text
notes    := measure ('|' measure)*        measures split on '|'
token    := rest | chord                  tokens split on whitespace
rest     := 'r' (':' duration)?
chord    := pitch ('+' pitch)* (':' duration)?
pitch    := [a-gA-G] ('##'|'#'|'bb'|'b'|'n')? octaveInt
duration := ('b'|'w'|'h'|'q'|'e'|'s'|'t'|'x') ('.' | '..')?
            b breve, w whole, h half, q quarter, e eighth,
            s sixteenth, t thirty-second, x sixty-fourth
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
            !barline=<style> (doubleBar, finalBar, heavy, dashed, dotted, none),
            !nav=<mark> (segno, coda, toCoda, daCapo, daCapoAlFine,
            daCapoAlCoda, dalSegno, dalSegnoAlFine, dalSegnoAlCoda, fine)
voices   := ';' splits a measure into up to four voices
            (c5:q d5 ; c4:h) — more than four throws
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

`Score.simple` also takes `clef:`, `keySignature:`, `timeSignature:`, a
`metadata:` (`ScoreMetadata`, default empty) and an initial `tempo:`
(`Tempo?`) — the same fields as the `Score` constructor.

## 5. Layout engine (`crisp_notation_core`)

`const LayoutEngine().layout(score, settings, {…})` → `ScoreLayout`. Named
options: `leadingWidth` / `measureWidths` (minimum widths for barline alignment
across a grand staff), `targetWidth` (pad the staff without stretching note
spacing), `spacingStretch` (= 1.0, uniform justification widening),
`drawTimeSignature` (= true), `finalBarline` (= true; a plain thin close when
false), `showNoteNames` / `noteNameStyle` (= `NoteNameStyle.letter`),
`showBeatNumbers`, `showMeasureNumbers` / `measureNumberInterval` (= 1),
`deferredStems` (id → stem-down override), `forcedColumns` (shared onset→x table
for cross-staff gridding) and `staffLineCount` (= 5).

- `LayoutSettings(metadata: …)`: engraving values (staff line/stem/ledger/
  beam/barline thicknesses, ledger extension) default to the font's
  `engravingDefaults`; spacing policy (padding, gaps, `spacingBase`,
  `spacingPerLog2`, `minNoteGap`, `stemLength` 3.5) is crisp_notation's own and
  overridable per instance.
- `SmuflMetadata.fromJson(...)` parses a SMuFL font metadata file
  (engraving defaults, glyph bounding boxes, stem anchors); core never
  loads assets itself. Unknown glyph lookups throw `ArgumentError`.
- `ScoreLayout` exposes `width`, `height`, `top` (≤ 0; ink rises above
  the top staff line), `bounds`, a flat painting-ordered `primitives`
  list (`GlyphPrimitive` = SMuFL name + origin, `LinePrimitive` (with an
  optional `round` cap — a zero-length round line is a filled dot),
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
"Ped."/release-star marks below the staff · quarter-tone **microtonal
accidentals** (`Pitch.microtone` → `MicrotonalAccidental`: half/three-quarter
sharp/flat, ±50/±150 cents) drawn with the Stein-Zimmermann glyphs and always
shown (never implied by the key), remappable via
`LayoutSettings.microtonalGlyphs` · **notehead schemes**
(`LayoutSettings.noteheadScheme`: `NoteheadScheme.sacredHarp` four-shape,
`.aikin` seven-shape, `.pitchName` letter, `.solfege` movable-do syllable —
the shape/label chosen per pitch by its scale degree in the current key; an
explicit `NoteheadShape` still wins) · **cue / small notes** (`Score.cueNoteIds`
— notehead, stem, flag and augmentation dots at 0.72×) · **extended trills**
(`TrillExtension(startId, endId)` — a `tr` glyph over the start note then a
tiled `wiggleTrill` wavy line to the end of the trilled span) · **laissez-vibrer
ties** (`LaissezVibrer(noteId, {down})` — a short trailing tie off each notehead
with no destination) · **lyric elision / synalepha** (`Lyric.elidesToNext` — an
undertie bridging two syllables sung on one note) · **figured-bass** slashed
figures (trailing `\` → the raised-digit glyph) and continuation/extension lines
(`_` row) — with theory helpers `figuredChordPitchClasses(bass, figure, key)`
and `realizeFiguredBass(pairs, key)` (four-part SATB realization) · **jazz
articulations** lift/flip/smear/bend (`JazzArticulation`, brass glyphs,
render-only) alongside scoop/doit/fall/plop · **tick / short /
reverse-final barlines** (`BarlineStyle.tick`/`.short`/`.reverseFinal`) ·
**additive / compound metric beam grouping** (`TimeSignature.beamGroups()` — 6/8,
9/8, 12/8 beam in threes; `3+2/8` beams by its components; simple meters
unchanged) · **non-standard key signatures** (`KeySignature.custom` — each
accidental placed at its own step, with mid-score cancellation naturals
generalized to custom keys) · **French violin / soprano / mezzo-soprano /
baritone / sub-bass** C- and F-clef positions and the neutral percussion clef
(on-staff key signatures derived by fifth-stacking where no hand-tuned table
exists) · **two-to-four voices per staff** (`_layoutMultiVoiceMeasure`: odd
voices 1/3 stem up, even 2/4 down; onsets share columns; rests stagger away from
the centre per voice; a colliding second/unison shifts rightward; a clear
column's accidentals share one block) · **per-column skyline collision
avoidance** — accidentals, articulations, dynamics, ornaments, annotations,
lyrics, navigation marks, figured bass and chord diagrams clear only the ink in
their own horizontal span (passes run notes → ties → slurs → … → text, each
later mark clearing earlier ink), and slurs arch above the full local interior
skyline, not just the spanned noteheads · **palm-mute / let-ring / vibrato on
the notation staff** (`PalmMute`/`LetRing` as a "P.M."/"let ring" dashed bracket,
`Vibrato` as a wavy line above the note — previously tab-only).

Caveat: interaction quantization (`StaffTarget.pitchFor`) takes an
explicit clef — apps using mid-score clef changes must map per measure.

### Systems & cross-staff onset-column gridding

Simultaneous notes align vertically across the staves of a system — the rule
serious engravers enforce. Core `alignedColumns(staves, settings)` builds a
shared per-measure column table (onset → x), splitting each element's ink into a
left (accidental) and right (notehead/stem/dots) part so a column's right ink
never collides with the next column's left ink and the noteheads themselves line
up even when only some carry an accidental at that beat. It is fed to the
single-voice path via `LayoutEngine.layout(..., forcedColumns:)` (and, for
multi-voice staves, `_layoutMultiVoiceMeasure` honours the shared columns).
`layoutGrandStaff` / `layoutGrandStaffSystems` / `layoutStaffSystem` take a
`gridAlign` flag (default true) to enable it across a grand staff or an N-staff
ensemble system; it is accidental-aware and composes with justification (the
`spacingStretch` scales the shared columns rather than fighting them).

**Guitar/bass tablature** (v0.8, complete — Phase 6, all technique tiers plus a
notation-paired staff via `layoutNotationTab` / `NotationTabView`):
`TabLayoutEngine.layout(score,
tuning, settings)` renders a `Score`'s pitches as fret numbers on an N-line
string staff, using a `Tuning` (open-string pitches; `Tuning.standardGuitar`
/ `dropDGuitar` / `standardBass`, or custom). `Tuning.fretFor(pitch)` assigns
the lowest playable (string, fret). `TabStaffView` is the Flutter widget.
`layout(…, {capo, showTuning})` (and the matching `TabStaffView` params)
clamps a capo (fret numbers read relative to it, plus a "capo N" label) and
draws each open string's note letter in a left gutter.
Rhythm stems/beams and playing techniques are drawn by the tab engine only
(they are inert in standard-notation rendering) and are added incrementally.
Supported so far: slides (reuse `Score.glissandos`), hammer-on/pull-off
(reuse `Score.slurs`), string bends (`Score.bends` — `Bend(noteId, {steps})`,
an upward arrow with a ½/full/1½ amount label), vibrato (`Score.vibratos`
— `Vibrato(noteId, {wide})`, a wavy line above the fret; `wide` enlarges the
wave), and palm mute / let ring (`Score.palmMutes` / `Score.letRings` —
`PalmMute(startId, endId)` / `LetRing(startId, endId)`, a labelled dashed
bracket above the staff over the spanned notes), and dead / ghost / natural-harmonic notes
(`Score.tabNoteMarks` — `TabNoteMark(noteId, TabNoteStyle.dead | .ghost |
.harmonic)`; dead shows "x" on each string, ghost draws the fret in
parentheses, harmonic in angle brackets `<12>`). `Score.tabVoicings`
(`TabVoicing(noteId, strings)`) pins a note/chord's pitches to explicit strings
(0 = top line), overriding the default lowest-fret placement (an out-of-range
pin falls back). `ChordDiagram(frets, {name, fingers, baseFret, fretSpan,
barreFret})` + `layoutChordDiagram(diagram, settings)` produce a standalone
fretboard-diagram `ScoreLayout` (string×fret grid, filled fingering dots,
open/muted x·o markers, name, base-fret label, optional barre) that renders
through the SVG/PNG pipeline. `Score.chordDiagrams`
(`PlacedChordDiagram(elementId, diagram, {scale})`) drops a diagram above a
note on a shared row above the staff — the lead-sheet convention — rendered by
**both** the notation and tab engines (a diagram on an unknown id is skipped).
`Score.taps` (`Tap(noteId)` — a "T" above the
fret) and `Score.tremoloBars` (`TremoloBar(noteId, {steps})` — a whammy-bar V
with the dip amount, a system separate from string bends) add tapping and
tremolo-bar. `TabNoteStyle` also covers `artificialHarmonic` / `pinchHarmonic`
(angle-bracketed fret + an "A.H."/"P.H." label). The tab engine additionally
draws **grace notes** (small fret digits with a legato arc; acciaccatura slash
per `GraceStyle`), **ornaments and articulations** (reusing
`NoteElement.ornament` / `.articulations` above the fret), **rasgueado**
(`Score.rasgueados` — `Rasgueado(noteId)`, a downward strum arrow), **right-hand
p-i-m-a fingering** (`Score.tabFingerings` — `TabFingering(noteId,
RightHandFinger)`, the letter below the fret), **slap / pop**
(`Score.slapPops` — `SlapPop(noteId, …)`, "S"/"P" above), and **tremolo
picking** (`Score.tremoloPickings` — `TremoloPicking(noteId)`, stacked slashes).
Also **slide-in/out** (`Score.slideInOuts` — `TabSlide(noteId, SlideInOut)`, a
slide stroke into or out of a single note), **pick-stroke direction**
(`Score.pickStrokes` — `PickStroke(noteId, {up})`), **golpe**
(`Score.golpes` — `Golpe(noteId)`, a body-tap mark), **wah**
(`Score.wahs` — `Wah(noteId, {open})`), and **volume fade / swell**
(`Score.fades` — `Fade(startId, endId, {out})`, a span) — all tab-engine-only.
*(This lifts the former "tablature out" clause — a consumer requested it.)*

**Now in scope** (formerly non-goals): per-column skyline collision avoidance,
voices 3–4 per staff, quarter-tone microtones, cross-staff (grand-staff)
beaming, transposing instruments, and compound/additive-meter beam grouping all
ship. **Still in progress**: page frames / spacers and a physical mm/spatium
unit (layout is in staff spaces). **Never**: audio (finer just-intonation ratios
and full non-Western theory also remain out). Alto/tenor clefs shipped in v0.2;
slurs/ties, tuplets, grace notes, articulations and dynamics in v0.3; two
voices, grand staff, line breaking, lyrics and chord symbols/annotations in
v0.4.


### Pagination

`layoutPages(score, settings, {required PageMetrics metrics, systemGap = 8,
justifyVertically = true, justify = true, systemBreaks = const {},
pageBreaks = const {}})` → `PagedLayout`. Line-breaks the score to the content
width (via `layoutSystems`), then packs systems top-to-bottom into pages no
taller than the content height, `systemGap` staff-spaces apart.

- `PageMetrics({required width, required height, marginTop = 8,
  marginBottom = 8, marginLeft = 8, marginRight = 8})` — the page box, all in
  **staff spaces** (the caller converts from physical sizes via the spatium).
  `contentWidth` / `contentHeight` are the page minus its margins. Asserts a
  positive page and margins that do not exceed it.
- `PagedLayout` — `pages` (`List<PageLayout>`), the `metrics` used, and
  `systemWidth` (== content width, the width every non-final system was
  justified to).
- `PageLayout` — `systems` (`List<PositionedSystem>`, top to bottom) and
  `justified` (whether this page's systems were spread to fill).
- `PositionedSystem` — the `SystemLayout` and its `top` offset in staff spaces
  **from the content-box top** (add `PageMetrics.marginTop` for the
  page-relative position).

With `justifyVertically` (the default) every page except the last spreads its
systems to fill the content height, surplus shared equally across the
inter-system gaps; the last page and any single-system page keep the natural
`systemGap`. `justify: false` skips *horizontal* justification of the systems
themselves. A forced `pageBreaks` entry implies a system break at the same
measure. A system taller than the content height still gets its own page rather
than failing.

## 5b. MusicXML import & export (`crisp_notation_core`)

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

**Compressed MusicXML (`.mxl`).** `writeMusicXmlToMxl(musicXml)` /
`readMusicXmlFromMxl(bytes)` wrap/unwrap the standard `.mxl` ZIP (the
interchange format Sibelius / Finale / Dorico / MuseScore share), composing
with `scoreTo`/`scoreFromMusicXml`. Reading follows the
`META-INF/container.xml` rootfile, else the first non-`META-INF` `.xml`. Pure
Dart (web-safe): the archive deflates/inflates through the in-repo `zip.dart`.

## 5c. Playback cursor (`crisp_notation_core`)

`playbackTimeline(score, {expandRepeats = true})` → sorted
`List<PlaybackNote>` (`elementId`, `start`/`duration` as whole-note
`Fraction`s, `isRest`, `voice`, `measureIndex`). With `expandRepeats`
(default) the score is linearized into performance order: repeats play
twice, voltas pick their pass, and navigation marks execute their jumps —
**D.C.** / **D.S.** return to the top / segno; **al Fine** stops at the
`fine` measure; **al Coda** arms `toCoda` so the next time it is reached
play jumps to the `coda`. Each D.C./D.S. fires once and, after it, the
score plays straight through (inner repeats not re-taken). A D.S. with no
segno, or an *al Coda* with no coda, throws `ArgumentError`. With
`expandRepeats: false` the measures play once in document order (all repeat/
navigation structure ignored). `soundingAt(timeline, time)` → the ids to
highlight (rests excluded). `secondsFor(wholeNotes, quarterBpm:)` maps
musical time to seconds. **No audio, ever** — apps bring their own
synth and drive `highlightedIds` from this timeline.

## 5d. Transposition (`crisp_notation_core`)

`score.transposedBy(interval, {descending: false, keepTransposition: true})` →
a new `Score` with every pitch (chords, all voices, grace notes), the key
signature and mid-score key changes moved; keys beyond ±7 accidentals wrap to
the enharmonic equivalent. Structured `chordSymbols` move with the music; ids,
rhythm, spans, lyrics and free-text annotations stay unchanged, so
highlights/taps/playback keep working. `keepTransposition` (default true)
carries the score's `Transposition` tag onto the result — pass false to drop it.

For **transposing instruments**, `Score.transposition` (`Transposition?`, null =
concert pitch) records how written pitch relates to sounding pitch
(`Transposition(interval, {down = true, octaves = 0})`; presets `bFlat` / `a` /
`eFlat` / `f` / `bFlatTenor`). `score.atConcertPitch()` returns the sounding
score — written pitches and key moved per the tag, the tag cleared; a
concert-pitch part is returned unchanged.

Note: Flutter's `material.dart` also exports an `Interval` — `hide Interval` on
the material import when using both.

## 5e. MIDI import & export (`crisp_notation_core`)

Export: `scoreToMidi(score, {quarterBpm = 120, ticksPerQuarter = 480})` →
`Uint8List`: a Standard MIDI File (format 0). Built on `playbackTimeline`,
so repeats, voltas and D.C./D.S./Coda jumps unfold into the note stream.
One tempo and (if the score is metered) one time-signature meta event at
tick 0; each note/chord emits a note-on per pitch at velocity 80 and a
matching note-off; voice 1 → channel 0, voice 2 → channel 1. Grace notes
carry no time and are omitted. **Contract-safe**: this is a byte stream for
a consumer's own synth/DAW — crisp_notation still produces no audio.

Import: `scoreFromMidi(Uint8List bytes)` → `Score` (format 0 and 1; all
tracks merged). MIDI carries no spelling, clef, key, ties, voices or
articulations, so this is a **lossy** single-staff reconstruction: pitches
spelled with sharps in the treble clef; onsets/durations quantized to a
sixteenth-note grid; simultaneous notes merged into chords; durations packed
into measures by the file's time signature (default 4/4) with ties across
barlines; ids `e0, e1, …` in order. It round-trips the pitches and quantized
rhythm of a simple exported score (enharmonic flats return as sharps).
Malformed bytes or an unsupported SMPTE division throw `FormatException`.

Both are dependency-free (`dart:typed_data`) and deterministic.

### GPIF (`.gp`) import & export

`scoreToGpif(score, {tuning, frettings})` / `scoreFromGpif(gpif, {trackIndex})`
write and read the `score.gpif` XML at the heart of the `.gpx`/`.gp` (v6/7/8)
formats — pure Dart. Pitches are fretted on the `Tuning` for export and recovered
from string+fret on import. This is a **high-fidelity round-trip**: on top of
pitches, chords, rhythm and per-track tuning it preserves **voice 2**
(`Measure.voice2` ↔ a second GPIF `<Voice>`), **tuplets** (`<PrimaryTuplet>`),
**key signature** incl. mid-score changes (`<Key><AccidentalCount>`), **dynamics**
(PPP…FFF), **grace notes** (`BeforeBeat`), **articulations** (staccato/accent),
and **lyrics** (track-level `<Lyrics>`, one `<Line>` per verse). Each of these is
emitted only when present, so a plain single-voice C-major score stays
byte-identical. The tab techniques round-trip too: HO/PO ↔ slur, slide ↔
glissando, bend & bend contours → `Bend`, normal/whammy vibrato → `Vibrato`,
dead/ghost/natural-artificial-pinch-tap-harmonic marks → `TabNoteMark`. Verified
across 25 real Guitar-Pro files and the alphaTab `.gp`/`.gpx`/`.gp5` corpora.
Notes unreachable on the tuning are dropped on export. Import records a
`TabVoicing` per note, so the file's **fingering (the string each note was
played on)** survives — re-rendering as tab keeps the original position instead
of re-arranging to the lowest fret.

The `.gp` container is a ZIP of the gpif, read/written by
`readGpifFromGp`/`writeGpFromGpif`; the `.gpx` (v6) container (a BCFZ/BCFS wrapper
over the same gpif) is read by `readGpifFromGpx` — both pure Dart (web-safe), using
the in-repo `inflate`/`deflate` (RFC 1951) so entries compress/decompress without
`dart:io`. Multi-track files import one track at a time (`scoreFromGpif` with
`trackIndex`, CLI `--track N`) or as a whole via `multiPartScoreFromGpif`;
`multiPartToGpif` writes one GPIF track per part with per-track tunings, and
`gpifTrackNames` lists the tracks. The legacy version-tagged **binary** formats
have their own from-scratch clean-room readers — `gp3ToScore` / `gp4ToScore` /
`gp5ToScore` (each `trackIndex`), plus `gpToMultiPart` which auto-detects the
version and reads one part per track — covering pitches/chords/durations/measures/
tunings and the note techniques (bend, slide, HO/PO, vibrato, palm-mute, let-ring,
dead note, natural/artificial/pinch harmonics). The binary readers are
fuzz-hardened: malformed input throws `FormatException`, never crashes or hangs.

### MuseScore (`.mscx` / `.mscz`) import & export

`scoreToMscx(score, {partName})` / `scoreFromMscx(mscx, {staffIndex})` write and
read a MuseScore-4 `.mscx` document — a **subset** (clef with mid-score changes,
key/time signatures, measures, notes/chords, rests, durations breve…64th with
dots, up to four voices, ties, pickup measures, articulations, ornaments, and —
via the location-based `<Spanner>` — **slurs** (`<Spanner type="Slur">`, paired
positionally on read) and **tuplets** (`<Tuplet>`/`<endTuplet>`)), pure Dart.
Pitch spelling round-trips through the MuseScore tonal-pitch-class (`tpcOf`), so
enharmonics are preserved. Common/cut time degrades to numeric; lyrics,
dynamics, grace notes and repeat/navigation structure are out of scope. The reader
also accepts the shapes real MuseScore **1.x, 3 and 4** files use for the
supported subset (`<KeySig>` as `concertKey`/`accidental`/`subtype`,
whole-measure `durationType>measure` rests, and 1.x files that hang
`<Part>`/`<Staff>` directly off `<museScore>` with no `<Score>` wrapper and write
the meter as `<nom1>`/`<den>`; 1.x pitches still come from `<tpc>`). The `.mscz` container is a ZIP of
the `.mscx`, read/written by `readMscxFromMscz` / `writeMsczFromMscx` — pure
Dart (web-safe), using the in-repo `inflate`/`deflate` (RFC 1951) so entries
compress on write and decompress on read without `dart:io`.
Pitches, rhythm and structure round-trip through the
shared `Score` model. `staffSystemFromMscx` reads a multi-staff document and
`multiPartToMscx` writes one part per staff (targeting MuseScore format 4.20).

### MEI (`.mei`) import & export

`scoreToMei(score, {title})` / `scoreFromMei(mei)` write and read an `<mei>`
(v5) document — a **subset** (clef with mid-score changes via inline
`<clef>`/`<keySig>`/`<meterSig>`, key/time signatures incl. common/cut and
additive, measures, notes/chords, rests, durations breve…64th with dots, two
voices as `<layer>`s, ties, pickup via `@metcon="false"`), pure Dart. Pitch
spelling round-trips through gestural accidentals (`@accid.ges`), so enharmonics
are preserved; written accidentals (`@accid`) map to `showAccidental`. Slurs
(`<slur>`), tuplets (`<tuplet>`), articulations, ornaments
(`<trill>`/`<mordent>`/`<turn>`), **dynamics** (`<dynam>`), **lyrics**
(`<verse>`/`<syl>`), **repeats/voltas** (`@left`/`@right` + `<ending>`),
**navigation** (`<repeatMark>`) and **single-note tremolo** (`@stem.mod`) also
round-trip on the writer. `staffSystemFromMei` reads a multi-staff document and
`multiPartToMei` writes one part per staff.

### Humdrum `**kern` (`.krn`) import & export

`scoreToKern(score)` / `scoreFromKern(kern)` write and read a `**kern` document —
a **subset** (clef with mid-score changes, key/time incl. common/cut and additive,
measures, notes/chords, rests, durations breve…64th with dots, ties), pure Dart.
Enharmonic spelling and natural courtesy accidentals round-trip; a short first
measure is read back as a pickup. Slurs (`(`/`)`), tuplets (reciprocals),
articulations and ornaments round-trip. **Multiple voices** round-trip via kern's
`*^`/`*v` spine split/join (the reader handles up to four sub-spine voices per
staff); **dynamics** ride a parallel `**dynam` spine and **lyrics** a `**text`
spine. `grandStaffFromKern` (2 spines) and `staffSystemFromKern` (N spines) read
multi-staff documents; `multiPartToKern` writes one spine per part. Long/maxima
(`00`/`000`) are approximated to a breve on import.

### LilyPond (`.ly`) import & export

`scoreToLilyPond(score)` / `scoreFromLilyPond(ly)` write and read LilyPond `.ly`
source (writer targets version 2.24.0, Dutch note names), pure Dart. Because
LilyPond input is a full (Turing-complete) language, the **importer covers a
subset** via a real lexer → parser → AST pipeline (`lilypond_lexer`/`_parser`/
`_ast`/`_reader`): `\relative` octave tracking, `\new Staff` / `\with` / `\score`
context wrappers, simultaneous/parallel music (`<< … >>`), variables
(`\name = …`, expanded on use), clef, `\key` (circle-of-fifths, major **and
minor**), time signatures, `\partial` (the anacrusis pre-loads the bar so the
first auto-barline falls after the pickup), durations breve…64th with dots,
chords, rests, **tuplets** (both `\tuplet a/n {…}` and `\times a/b {…}`
→ `TupletSpan`), and **lyrics** — `\addlyrics`, `\lyricsto` and `\lyricmode`, with
`--` → `hyphenToNext`, `__` → `extender`, `_` a skip, and multiple verses tracked;
lyric blocks nested inside a simultaneous main voice are picked up too.
`\chordmode` / `\chords` / `\figuremode` / `\drummode` blocks are consumed as
wrapper arguments and skipped as non-melodic, so a common "chord track + melody +
lyrics" sheet reads the melody cleanly. Export
covers clef (with changes), key/time signatures, notes/chords, rests, durations,
two voices, ties, pickup (`\partial`), articulations, ornaments, slurs (`(`/`)`)
and tuplets; 4/4 and 2/2 engrave as the C / cut-C symbols by default. Lyrics,
dynamics and repeat structure are export-only gaps. `multiPartToLilyPond` writes
one staff per part.

### GABC (Gregorian chant) import

`scoreFromGabc(gabc)` → `Score` reads the Gregorio plain-text chant format
(`key:value;` header, `%%` separator, then `syllable(neumes)` body), pure Dart;
`gabcHeader(gabc)` → `GabcHeader` exposes the typed header fields (`name`,
`officePart`, `mode`, `transcriber`, `book`). **Import only** — there is no GABC
writer. It reads do-clefs `c1`–`c4` and fa-clefs `f1`–`f4` (with mid-body clef
changes and an optional flat signature `cb3`), diatonic letters `a`–`m`,
accidentals (`x` flat / `y` natural / `#` sharp, persisting to the next division
bar), the mora dot (`.`, lengthening a note), and division bars (`,` `;` `:` `::`,
which split measures and reset in-measure accidentals). Lyric syllables attach to
the first note of their neume and hyphenate within a word. Chant is unmetered, so
it maps to `Clef.treble` with an empty key signature and no time signature; notes
default to eighths (mora dot → quarter). Neume-shape/articulation characters
(`v w o s ~ / ! _ ' < >`, digits, brackets) carry no pitch and are skipped. A
missing `%%` separator throws `FormatException`.

### MusicRender / muspy JSON (PDMX corpus) import

`multiPartScoreFromMusicRender(json)` / `scoreFromMusicRender(json, {partIndex})`
read the muspy "MusicRender" performance JSON used by the PDMX corpus (tick
onsets/durations, MIDI pitches; no spelling or voices) — **import only**. Because
that representation is performance-level, it is transcoded to a Standard MIDI File
and fed through `scoreFromMidi`, so it inherits MIDI's lossy sixteenth-grid
quantization, chord merging and rest packing. `musicRenderToMidi(json)` exposes the
note-exact JSON→SMF transcoder directly (no notation quantization).

### Braille music (`.brl`) export

`scoreToBraille(score)` emits Unicode braille-music notation (U+2800…) for a
single-staff score — **export only** — an accessibility differentiator. Covers
note signs (name + value), rests, accidentals (shown only when not implied by
the key), octave marks (by the standard interval rule), dotted-note
augmentation cells, chords (top note + downward interval signs), a leading
signature header (standard key signature + numeric time signature), and
blank-cell measure separation. In-accord voices, mid-score signature changes,
dynamics, slurs and formatting rules are follow-ups.

### Plain-text (ASCII) tablature import

`asciiTabToScore(text, {tuning, duration})` → `Score` parses the informal
web-shared guitar/bass tab (N dashed string lines with fret numbers) into a
pitched score for a `Tuning` (default standard guitar). It is **lossy**: ASCII
tab has no reliable rhythm, so by default every event takes the same
`duration` (default an eighth) and the score is unmetered — or, with
`inferRhythm: true`, durations are **interpreted from the horizontal spacing**
(smallest inter-event gap = an eighth; wider gaps scale to quarter/dotted/half/
whole), a heuristic that recovers plausible rhythm from well-spaced tabs.
Barlines come from `|` columns;
`(string, fret)` becomes a pitch; simultaneous columns become chords.
Recognized techniques (single-note events): `h`/`p` → a slur, `/`/`\` → a
glissando, `b` → a `Bend`, `~` → a `Vibrato`, `x` → a dead `TabNoteMark`. The
importer also emits `TabVoicing`s so re-rendering as tab keeps each note on the
string it was written on (rather than the engine's default lowest-fret).
No tab lines → a single whole-rest measure. Dependency-free, deterministic.

## 5f. SVG export (`crisp_notation_core`)

`scoreToSvg(layout, {staffSpace, glyphFontFamily, textFontFamily, color,
background, fontFaceDataUri})` → a standalone SVG document string. It renders
a laid-out `ScoreLayout` — so it works for **both** notation (`LayoutEngine`)
and tablature (`TabLayoutEngine`) — mapping the display list to SVG shapes
(SMuFL glyphs as `<text>` in the engraving font, lines/curves/beams/text as
native SVG). Pass `fontFaceDataUri` (a `data:` URI of the engraving font) to
embed it via `@font-face` for a self-contained file. The
`smuflCodepoints` name→character table also lives in core now (shared by the
Flutter painter and this emitter). Pure Dart, deterministic. *(Raster/PNG
export rides the Flutter renderer — see the `crisp_notation` package.)*


## 5g. ABC notation (`crisp_notation_core`)

Import: `scoreFromAbc(abc)` → `Score` (first tune, first voice).
`staffSystemFromAbc(abc)` → `StaffSystem` — one notation staff per `V:` voice,
top to bottom in declaration order, each keeping its own clef (`V:… clef=…` or
the `K:` header) and lyrics; ids are prefixed per voice so they stay unique.
Voices with fewer bars than the longest are padded with trailing whole rests so
the system still aligns rather than failing. `multiPartScoreFromAbc(abc)` →
`MultiPartScore`, so a tune line-breaks and paginates straight into
`layoutMultiPartPages` / `MultiPartView`. All three throw `FormatException` if no
tune body / `K:` field is found.

Subset: a broad slice of **ABC 2.1** — the `M`/`L`/`K` header, then pitched notes
(accidentals from the key + in-measure state, octave marks, `L`-relative and
fractional lengths), rests, chords, broken rhythm (`>`/`<`), ties, tuplets,
slurs, grace notes (incl. `{/…}`), decorations (`!…!` and the shorthand
`. ~ H T M P u v` → articulations / ornaments / dynamics / bowing), navigation
(`!segno!`/`!D.C.!`/`!D.S.!`/`!fine!`…), quoted `"C"` and positioned `"^…"`
annotations, bar lines (repeats, double/final, variant endings `|1`/`[2`),
multi-measure rests (`Z`), inline fields (`[K:…]`/`[M:…]`/`[L:…]`), `w:` lyrics
and `s:` symbol lines, `Q:` tempo and `P:` part labels (as annotations), and line
continuation (`\`). Unmodeled decorations are skipped so real tunes still import.

Export: `scoreToAbc(score, {unitLength, index = 1, title})` → an ABC tune string.
`unitLength` is the `L:` field (default 1/8), `index` the `X:` tune number,
`title` the optional `T:`. Emits the `M`/`L`/`K` header then notes, rests,
chords, ties, tuplets, slurs, grace notes, staccato, `"C"` chord symbols and bar
lines (repeats, double/final); a single lyric verse becomes a `w:` line.
Accidentals are written relative to the key **in force**, so mid-tune `[K:…]`
changes read back at pitch. **Export is single-voice** — there is no
`staffSystemToAbc`.

Round-trip: both codecs funnel through the one `Score` model, so a score
round-trips for the data ABC can represent. Export is a narrower subset than
import (no navigation marks, dynamics, multi-measure rests or multi-voice), so an
imported tune is **not** guaranteed to re-export byte-identically. Pure Dart,
web-safe, no file I/O — pass the tune as a string.

## 5h. Multi-part scores & staff systems (`crisp_notation_core`)

**Model.** `StaffSystem(staves, {brackets, connectBarlines, barlineGroups,
systemBreaks})` is N `Score`s rendered as **one aligned system**.
`MultiPartScore(parts, {brackets = const [], barlineGroups = const []})` is the
paginating counterpart: a whole piece as N parts (same measure count and meter)
that line-breaks into multi-staff systems and paginates as one document. Asserts
at least one part; element ids should be unique across parts so interaction stays
unambiguous. `MultiPartScore.fromStaffSystem(system)` promotes a single system
into a document, preserving barline semantics; `toStaffSystem()` goes back;
`atConcertPitch()` untransposes every part.

`BarlineGroup(first, last)` is a contiguous run of part indices whose barlines
connect through the group (`contains(index)`; asserts `last >= first`,
`first >= 0`). An **empty** `barlineGroups` means barlines connect through the
whole system. One group spanning every staff reproduces `connectBarlines: true`;
two groups (strings connected, winds connected, the barline broken between them)
is what all-or-nothing `connectBarlines` could not express.
`StaffBracket(first, last, kind)` with `StaffBracketKind` draws the left-edge
brackets/braces (may be empty or nested).

**Import.** `staffSystemFromMusicXml(xml)` → `StaffSystem`: every part — and
every staff of a multi-staff part — becomes one aligned staff. Multi-staff parts
(e.g. piano) are joined by a brace; `<part-group>`s in the `<part-list>` (with a
`bracket`/`brace`/`square`/`line` group-symbol) become the corresponding
`StaffBracket`s. Ids get disjoint spaces per staff.
`multiPartScoreFromMusicXml(xml)` wraps that as a `MultiPartScore`. Throws
`FormatException` on documents the subset cannot represent.

**Layout.** `layoutStaffSystemSystems(document, settings, {required maxWidth,
staffGap = 4.0, justify = true, gridAlign = true, hideEmptyStaves = false,
systemBreaks = const {}, showNoteNames = false, noteNameStyle =
NoteNameStyle.letter})` → `StaffSystemSystems` breaks a `StaffSystem` into
systems no wider than `maxWidth`. Measures are packed by the **widest** part so
barlines stay aligned across every part; the time signature draws only on the
first system (and at explicit changes); every non-final system closes with a
plain barline and, unless `justify` is false, stretches to fill `maxWidth` via a
shared note-spacing stretch. With `hideEmptyStaves`, a part whose measures over a
system's range are entirely rests is dropped from that system (the orchestral
space-saver) — the first system always shows every part, a would-be-blank system
keeps all its parts, and brackets/barline groups clip to what remains. Throws if
the parts disagree on measure count or `maxWidth` ≤ 0. `StaffSystemSystems`
carries `systems` / `maxWidth` and `heightWith(systemGap)`; each
`StaffSystemSystem` has `layout`, `firstMeasure`, `lastMeasure`.

`layoutMultiPartPages(document, settings, {required metrics, staffGap = 4.0,
systemGap = 8, justifyVertically = true, justify = true, hideEmptyStaves = false,
showNoteNames = false, noteNameStyle})` → `MultiPartPagedLayout` (`pages` /
`metrics` / `systemWidth`) paginates a `MultiPartScore` on the same rules as
`layoutPages`: pages of `MultiPartPageLayout` (`systems`, `justified`) holding
`PositionedMultiPartSystem` (`system`, `top`).

## 5i. Optical music recognition (`crisp_notation_core` + `crisp_notation_cli`)

Staff image → `Score`. The **recognition** is done by an external engine; core
ships only the pure-Dart back half of the pipeline, so the whole image-to-model
chain is testable without a native library (feed a known token string, assert on
the `Score`).

**Core (pure Dart, no FFI).** `OmrEngine` is an abstract one-method interface
(`Future<String> recognize(OmrImage image)`); `OmrImage(pixels, {required width,
required height, channels = 1})` is a row-major buffer (1 = gray, 3 = RGB,
4 = RGBA). `omrDialectOf(tokens)` → `OmrDialect` sniffs which engine produced the
tokens: `bekern` (SMT, a linearised grand-staff Humdrum), `semantic` (TrOMR
PrIMuS-style `clef-G2 note-C4_quarter …`), or `lilyNotes` (Flova LilyPond simple
notes). Parsers: `bekernToScore` (first spine), `bekernToGrandStaff`,
`bekernToStaffSystem`, `bekernToKern` (→ Humdrum `**kern`), `scoreFromSemantic`,
`scoreFromLilyNotes`. Helpers `recognizeGrandStaff(engine, image)` /
`recognizeScore(engine, image)` compose an engine with the parsers.

**Engine (`crisp_notation_cli`).** `package:crisp_notation_cli/omr.dart` is the
whole pipeline in one import (it re-exports the core parsers). The engine is
`CrispEmbedOmrEngine.load(modelPath, {lib})` — a `dart:ffi` bridge to
**`libcrispembed`**, required at runtime; `recognizeSync(image)` / `recognize`,
and `dispose()` when done. Failures throw `OmrEngineException`. Image helpers:
`decodeOmrImage(path)`, `decodeImageFile(path)`, `omrImageOf(img.Image)`, and
`segmentStaffSystems(...)` to split a full-page scan into per-system crops.
`resolveOmrModel(model, {cacheDir, onStatus})` returns an existing path as-is, or
downloads a registered name from Hugging Face into `cacheDir` (default
`$XDG_CACHE_HOME/crisp_notation/omr`) and returns the cached path.
`omrModelRegistry` maps `smt-grandstaff` / `smt` / `tromr` / `flova` → (repo,
GGUF file).

**Platforms.** FFI-only: the CLI and Flutter **desktop** (macOS / Windows /
Linux). **Not web** — Dart/Flutter web has no `dart:ffi`, and CrispEmbed's WASM
build does not expose the OMR engines. Core's parsers remain web-safe.

**CLI.** `crisp_notation omr <image> <out.(musicxml|mxl|krn|svg|png)>
--model <gguf|name> [--lib <path>] [--threads <n>] [--single] [--page]`. The
engine is auto-detected from the returned dialect. `--model` accepts a GGUF path
or a registry name (auto-downloads); or set `CRISP_NOTATION_OMR_MODEL`. `--lib`
points at `libcrispembed`; or set `CRISPEMBED_LIB`. `--single` imports the first
spine only; `--page` splits a full-page scan into staff systems and recognizes
each, concatenated.

## 6. Rendering (`crisp_notation`)

- `Bravura.load()` — parses the bundled font metadata once (async,
  cached, single-flight; failures are not cached and retry). Apps should
  `await` it in `main()`; otherwise the first `StaffView` frame is empty
  and the widget self-heals when the load completes.
- `StaffView(score, theme, staffSpace, highlightedIds, elementColors,
  onElementTap, noteheadScheme, showNoteNames, showBeatNumbers,
  showMeasureNumbers, measureNumberInterval)` — a `LeafRenderObjectWidget`.
  `measureNumberInterval` (default 1) labels bar 1 and every Nth bar.
  `staffSpace` = px per staff
  space; `null` fits the available width. Glyphs paint via `TextPainter`
  (baseline-anchored, font size = 4 × staff space). `noteheadScheme` selects the
  shape-note / pitch-name / solfège heads; `showNoteNames` draws each note's
  letter below it and `showBeatNumbers` the counting overlay above — teaching
  overlays that also render through the SVG back-end. `elementColors` is a
  repaint-only per-id color map that mirrors `highlightedIds`.
- `CrispNotationTheme` — `staffColor` (furniture), `noteColor` (element ink),
  `highlightColor` (wins over everything), `elementColors` per-id
  overrides, `kidMode`/`hitSlop`/`lineBoost`, `textFontFamily` for
  lyrics/annotations (null = platform default), and `musicFont` (the SMuFL
  engraving face, default `MusicFont.bravura`). Presets: `standard`,
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
- `InteractiveGrandStaffView(grandStaff, …)` is the grand-staff counterpart:
  it wraps a two-clef `GrandStaff` into width-fitting systems (core
  `layoutGrandStaffSystems`), bracing and barline-connecting each system, with
  `gridAlign`/`justify` shared across both staves. Element and empty-staff taps
  resolve on both staves (the `StaffTarget` carries `systemIndex` and
  `staffIndex`, 0 = upper), plus hover / caret / ghost / drag editor hooks.
- `RenderStaffView` is public as the geometry service: `scoreLayout`,
  `scale`, `localToStaff`/`staffToLocal`, `elementIdAt`,
  `quantizeStaffPosition`, `ghostNote`.
- `renderLayoutToPng(layout, {staffSpace, theme, highlightedIds,
  background})` → `Future<Uint8List>` rasterizes a `ScoreLayout` (notation or
  tab) to PNG via `dart:ui` — the raster counterpart to core's `scoreToSvg`.
  It runs inside a Flutter binding (an app or `flutter test`) and needs the
  engraving font registered (`Bravura.load()`).
- **C8** one-call export: `exportScoreToPng(score, {theme, staffSpace,
  highlightedIds, background})` → `Future<Uint8List>` and `exportScoreToSvg(score,
  {theme, staffSpace, embedFont, elementColors})` → `Future<String>` take a
  **`Score`** (not a pre-built `ScoreLayout`) and own the whole chain — the
  layout pass, the SMuFL metadata lookup, and (for SVG) embedding the engraving
  font as a data-URI. `exportGrandStaffToPng` / `exportGrandStaffToSvg` are the
  `GrandStaff` overloads. `MusicFont.fontAsset` supplies the font bytes for the
  SVG embed.

- `PianoKeyboardView({highlightedPitches = const {}, firstMidi = 48,
  lastMidi = 84, pitchColors, highlightColor, theme, whiteKeyWidth = 16,
  height = 80})` — a piano keyboard lighting MIDI numbers; the range snaps out to
  white keys, lit color resolves `pitchColors?[midi] ?? highlightColor ??
  theme.highlightColor`. Purely visual — no audio.
- `FretboardView({tuning = FretboardView.standardGuitar, frets = 12,
  highlightedPitches = const {}, pitchColors, highlightColor, theme,
  fretWidth = 26, stringSpacing = 14})` — a fretboard with the low string at the
  bottom, a thick nut, and inlays at 3/5/7/9 (double at 12). Lights **every**
  (string, fret) whose pitch is highlighted, so a pitch playable on several
  strings lights all of them; open notes draw left of the nut. Statics
  `standardGuitar` (`[40, 45, 50, 55, 59, 64]`) and `standardBass`
  (`[28, 33, 38, 43]`).
- `ScorePageView({required score, required metrics, theme, staffSpace = 8,
  systemGap = 8, justifyVertically = true, pageIndex = 0,
  drawPageBorder = false, showSystemDividers = false})` — paginates a `Score` via
  `layoutPages` and paints the single page `pageIndex` at exactly
  `metrics.width × staffSpace` by `metrics.height × staffSpace`. An out-of-range
  `pageIndex` paints an empty page. **`metrics` is core's `PageMetrics`** —
  Flutter's `widgets.dart` also exports one, so `hide PageMetrics` on the Flutter
  import when using both. `RenderScorePageView` is public (`pagedLayout`,
  `pageCount` — 0 and null until `MusicFonts.load` resolves, then it self-heals).
- `MultiPartView(document, metrics, {theme, staffSpace = 8, staffGap = 4,
  systemGap = 10, justifyVertically = true, hideEmptyStaves = false,
  pageIndex = 0, drawPageBorder = false, onElementTap})` — paints one page of a
  paginated `MultiPartScore` (§5h). `RenderMultiPartView` is public and
  implements `ElementRegionProvider`.
- `StaffSystemView(system, {theme, staffSpace, staffGap = 4.0, gridAlign = true,
  hideEmptyStaves = false, highlightedIds, onElementTap})` — a single
  un-paginated `StaffSystem` (`staffSpace` null = fit to width).
  `RenderStaffSystemView` is public.

## 7. Interaction (`crisp_notation`)

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
- Selection is app state: pass `highlightedIds` down; crisp_notation never
  stores a selection.

### Editor surface (the multi-line and grand-staff views)

`MultiSystemView` and `InteractiveGrandStaffView` add the app-owned editing
moat — all repaint-only, no relayout:

- `errorOverlay: Map<String, EditorMark>` — draws the flagged note in the mark's
  `color` (with a small wedge above its staff) for assessment / ear-training /
  proofreading; `EditorMark(color, {message})` carries an optional
  app-surfaced message (not drawn).
- `loopRange: (String startId, String endId)?` — a translucent loop / selection
  band spanning the range across systems (and both staves on the grand staff).
- `rectOfElement(id) -> Rect?` on the render object — the local pixel rect of any
  element, for scroll-to-note geometry; `elementRegions`
  (`(id, Rect bounds, measureIndex)` across systems / both staves) and
  `elementIdsIn(Rect)` back marquee / shift-click range selection.
- **C7** `ElementRegionController` (alias `MultiSystemViewController`) exposes
  those last two on the **public widget**: `MultiSystemView(controller:)` /
  `InteractiveGrandStaffView(controller:)`. After the first layout,
  `controller.elementRegions` / `controller.elementIdsIn(Rect)` return the hit
  geometry (marquee-select, drag-to-reorder); the controller re-binds when
  swapped and detaches on unmount (empty until attached).
- Desktop placement: `onHover(StaffTarget?)`, a `caret` (`EditorCaret`, a
  full-height insertion bar) and a `ghostTarget` + `ghostDuration` preview
  notehead; element drag hooks `onElementDragStart(id)` /
  `onElementDragUpdate(id, target)` / `onElementDragEnd(id, target)` report a
  drag on an existing element (crisp_notation only reports; the app rebuilds the
  score). `StaffTarget` carries `systemIndex` + `staffIndex`.
- **C10a** `suppressElementIds: Set<String>` — omits those elements from paint
  entirely (notehead, stem, flag, beam, ledger, curve), a clean
  theme-independent hide with no ink bleed. The companion to the drag hooks: the
  app hides the dragged note and draws its own `ghostTarget` in its place,
  instead of the old "paint it the background colour" trick (which broke on the
  handwritten font / coloured staves). Repaint-only; ids match on either staff.
- **C10b** `dragPreviewOpacity: double?` — when non-null, the view **owns the
  live drag**: while an element is dragged it is suppressed from the normal
  layout and re-painted translated to follow the pointer — the *real* glyph
  (notehead, stem, accidental, flag, ledgers), snapped vertically to the target
  line/space (pitch) and free horizontally — faded to this opacity (1.0 =
  solid). The app needs no `ghostTarget` / `suppressElementIds` bookkeeping for
  moves; the render object repaints itself on each drag update. null (default)
  keeps the report-only behavior. On the grand staff the snap follows the
  pointer's staff.
- `ScoreEditorController` (a `ChangeNotifier`) is the single source of truth for
  a view's overlay state: `setLoop`/`clearLoop`, `mark`/`unmark`/`setMarks`/
  `clearMarks`, `highlight`/`clearHighlight`. It also drives scroll-to-note on an
  **app-owned** `ScrollController` — `attachViewport(scrollController:,
  rectOfElement:)`, then `scrollToNote(id, {alignment})` (or `offsetToReveal(id)`
  to compute the offset and animate yourself).

- `evaluateDrill({required score, required expectedIds, required played,
  correctColor, wrongColor})` → `DrillResult` (`overlay` as
  `Map<String, EditorMark>`, `extraPitches`, `missingPitches`, `isPerfect`)
  compares expected element ids against the sounding MIDI set: each expected
  element marks `'correct'` or `'missing N note(s)'`. Elements with no pitches
  (rests / grace / unknown ids) are skipped and produce no overlay entry. Feeds a
  view's `errorOverlay` or `ScoreEditorController.setMarks`/`showDrill`.
- `TranspositionController(Score base)` — a `ChangeNotifier` over
  `Score.transposedBy` / `atConcertPitch`: `base`, `score`, `isTransposed`,
  `transposeBy(interval, {descending = false})`, `octaveUp()`, `octaveDown()`,
  `showConcertPitch()`, `reset()`. `transposeBy` **composes** (it transposes the
  current `score`, not `base`); `showConcertPitch` and `reset` restart from
  `base`. A redundant change fires no notification. Renders nothing — the app
  rebuilds a view off `controller.score`.
- `InteractiveMultiPartView(document, metrics, {…, controller, caret,
  showMeasureNumbers, showNoteNames, noteNameStyle})` — the editor surface over a
  paginated `MultiPartScore`; staff-tap / hover / drag callbacks carry
  `(partIndex, StaffTarget)`. See §5h.

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
4. **Loud failures for bad values**: unspellable transpositions, out-of-range
   signatures, unnameable intervals and unknown glyphs throw
   (`ArgumentError`); malformed DSL throws `FormatException`; invalid
   constructor arguments fail asserts in debug builds.
5. **Dangling spans are skipped, not fatal**: a span whose `startId`/`endId`
   is unknown, or whose ends are reversed or equal, is dropped and the rest of
   the score still renders. This is deliberate — real imports carry spans whose
   other end sits in a part that was not imported, and the renderer must not
   crash on real input. It applies to slurs, glissandos, portamentos, laissez
   vibrer, dynamics, hairpins, pedals and chord diagrams.

   Two cases have **not** been converted and still throw `ArgumentError` on an
   unknown id: palm-mute/let-ring spans and annotation/chord-symbol placement.
   Treat that asymmetry as a known inconsistency rather than a guarantee — the
   direction of travel is to skip.
5. **Zero dependencies** and the licensing rules of §1.

## 9. Quality gates

Every commit: `dart format` clean, `flutter analyze` zero issues under
strict lints (incl. `public_member_api_docs`), all tests green, and the
AOT layout benchmark within its linear-scaling gate (see [PERF.md](PERF.md)):

| Suite | Scope |
|---|---|
| `crisp_notation_core` unit tests (~1390, 114 files) | theory tables + property sweeps, layout rules 1–14, layout edge/quality suites, DSL, SMuFL parsing, interchange round-trips, validation |
| `crisp_notation` widget tests (~300, 36 files) | sizing, hit testing, gestures, ghost lifecycle, repaint/relayout policy, asset loading, pixel-level paint verification |
| `crisp_notation_cli` tests (~75, 7 files) | command wiring, convert/render/info flows, interchange fixtures |
| Golden corpus (135 scenes + hero) | all four clefs, all durations, dots, accidentals, chords, beams, rests, signatures, highlights, kid mode, ghost, fit-to-width, multi-part/grand-staff systems (macOS-generated) |
| Example widget tests + integration test | real app boot, gallery scroll, place/select/clear flow, duration & clef controls — `flutter test integration_test -d macos` |
