# crisp_notation — features and public API contract (v0.4-dev)

This document describes what crisp_notation **does** and which API surface and
behaviors consumers may **rely on**. It reflects the implementation as
shipped; active development follows [PLAN.md](../PLAN.md), and the reasoning
behind non-obvious choices is in [DESIGN.md](DESIGN.md).

Both packages are pre-1.0: minor versions may break APIs, but anything
listed under *Guarantees* below is treated as stable and only changes with
a documented migration note.

---

## 1. Packages

| Package | Platform | Depends on | Contents |
|---|---|---|---|
| `crisp_notation_core` | any Dart | Dart SDK only (zero deps) | music theory, score model, deterministic layout engine, SMuFL metadata types |
| `crisp_notation` | Flutter | Flutter + `crisp_notation_core` (re-exported) | rendering (`StaffView`), interaction (`InteractiveStaff`), bundled Bravura font (SIL OFL 1.1) |

`crisp_notation_core` must never gain a runtime dependency; `crisp_notation` must
never gain one beyond Flutter + `crisp_notation_core`. The Bravura font ships
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

All theory types are immutable value types: `==`/`hashCode` are
value-based, invalid constructor arguments fail asserts in debug builds.

## 4. Score model (`crisp_notation_core`)

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
  drawn at its end; rendered, MusicXML-round-tripped, and executed as jumps
  by `playbackTimeline`). `effectiveDurationAt(i)` and
  `totalDuration` sum exactly with tuplet scaling — a triplet eighth
  sounds 1/12 (games compare against `TimeSignature.measureCapacity`; the
  layout engine does **not** enforce it). A short opening bar under a known
  meter is auto-detected as a `Measure.pickup` (anacrusis).
  `Score.barNumberAt(index)` (C9) gives the displayed bar number with the pickup
  uncounted — 1-based over non-pickup measures, `null` for a pickup itself; the
  measure-number overlay and the MEI writer both use it.
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

## 5. Layout engine (`crisp_notation_core`)

`const LayoutEngine().layout(score, settings)` → `ScoreLayout`.

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
**both** the notation and tab engines (an unknown id throws at layout time).
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

`score.transposedBy(interval, descending: false)` → a new `Score` with
every pitch (chords, both voices, grace notes), the key signature and
mid-score key changes moved; keys beyond ±7 accidentals wrap to the
enharmonic equivalent. Ids, rhythm, spans, lyrics and annotation text
stay unchanged, so highlights/taps/playback keep working. Note:
Flutter's `material.dart` also exports an `Interval` — `hide Interval`
on the material import when using both.

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

`scoreToGpif(score, {tuning})` / `scoreFromGpif(gpif)` write and read the
`score.gpif` XML at the heart of the `.gpx`/`.gp` (v6/7/8) formats — a **subset**
(track tuning, master bars → bars → voices → beats → notes as string+fret, and
rhythms; single voice/track; techniques out of scope), pure Dart. Pitches are
fretted on the `Tuning` for export and recovered from string+fret on import,
so pitches and rhythm round-trip. The `.gp` container is a ZIP of the gpif,
read/written by `readGpifFromGp`/`writeGpFromGpif` — pure Dart (web-safe), using
the in-repo `inflate`/`deflate` (RFC 1951) so entries compress on write and
decompress on read without `dart:io`. Import also reads the common
playing techniques into the tab marks (HO/PO → slur, slide → glissando, bend →
`Bend`, whammy vibrato → `Vibrato`, dead/harmonic → `TabNoteMark`). Validated
against the alphaTab `.gp` (v7) test corpus — pitches/chords/rhythm and those
techniques read correctly. Multi-track files import one track at a time
(`--track N`). The `.gpx` (v6) container (a BCFZ/BCFS wrapper over the same
gpif) is also read by the CLI (validated against the alphaTab `.gpx` corpus).
**`.gp5`** — a version-tagged *binary* format — has its own from-scratch reader
(`gp5ToScore`; pitches/chords/durations/measures/tunings + the note
techniques), validated against the alphaTab `.gp5` corpus.

### MuseScore (`.mscx` / `.mscz`) import & export

`scoreToMscx(score, {partName})` / `scoreFromMscx(mscx, {staffIndex})` write and
read a MuseScore-4 `.mscx` document — a **subset** (clef with mid-score changes,
key/time signatures, measures, notes/chords, rests, durations breve…64th with
dots, up to four voices, ties, pickup measures, articulations, ornaments, and —
via the location-based `<Spanner>` — **slurs** (`<Spanner type="Slur">`, paired
positionally on read) and **tuplets** (`<Tuplet>`/`<endTuplet>`)), pure Dart.
Pitch spelling round-trips through the MuseScore tonal-pitch-class (`tpcOf`), so
enharmonics are preserved. Common/cut time degrades to numeric; lyrics,
dynamics, grace notes and repeat/navigation structure are out of scope. The reader also accepts the shapes real MuseScore 3/4 files use for the
supported subset (`<KeySig>` as `concertKey`/`accidental`/`subtype`,
whole-measure `durationType>measure` rests). The `.mscz` container is a ZIP of
the `.mscx`, read/written by `readMscxFromMscz` / `writeMsczFromMscx` — pure
Dart (web-safe), using the in-repo `inflate`/`deflate` (RFC 1951) so entries
compress on write and decompress on read without `dart:io`.
Pitches, rhythm and structure round-trip through the
shared `Score` model.

### MEI (`.mei`) import & export

`scoreToMei(score, {title})` / `scoreFromMei(mei)` write and read an `<mei>`
(v5) document — a **subset** (clef with mid-score changes via inline
`<clef>`/`<keySig>`/`<meterSig>`, key/time signatures incl. common/cut and
additive, measures, notes/chords, rests, durations breve…64th with dots, two
voices as `<layer>`s, ties, pickup via `@metcon="false"`), pure Dart. Pitch
spelling round-trips through gestural accidentals (`@accid.ges`), so enharmonics
are preserved; written accidentals (`@accid`) map to `showAccidental`. Slurs
(`<slur>`), tuplets (`<tuplet>`), articulations and ornaments round-trip;
lyrics and dynamics are out of scope.

### Humdrum `**kern` (`.krn`) import & export

`scoreToKern(score)` / `scoreFromKern(kern)` write and read a single-spine
`**kern` document — a **subset** (clef with mid-score changes, key/time incl.
common/cut and additive, measures, notes/chords, rests, durations breve…64th
with dots, ties), pure Dart. Enharmonic spelling and natural courtesy
accidentals round-trip; a short first measure is read back as a pickup. Slurs
(`(`/`)`), tuplets (reciprocals), articulations and ornaments round-trip; two
voices and lyrics are out of scope.

### LilyPond (`.ly`) export

`scoreToLilyPond(score)` emits a LilyPond `.ly` source — **export only** (its
input is a full language, so there is no importer), generated from the
documented syntax. Covers clef (with changes), key/time signatures,
notes/chords, rests, durations breve…64th with dots, two voices, ties and
pickup (`\partial`). Uses Dutch note names; 4/4 and 2/2 engrave as the C /
cut-C symbols by LilyPond default (numeric meters force numerals). Slurs,
tuplets, articulations, lyrics and repeat structure are out of scope.

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

## 6. Rendering (`crisp_notation`)

- `Bravura.load()` — parses the bundled font metadata once (async,
  cached, single-flight; failures are not cached and retry). Apps should
  `await` it in `main()`; otherwise the first `StaffView` frame is empty
  and the widget self-heals when the load completes.
- `StaffView(score, theme, staffSpace, highlightedIds, elementColors,
  onElementTap, noteheadScheme, showNoteNames, showBeatNumbers,
  showMeasureNumbers)` — a `LeafRenderObjectWidget`. `staffSpace` = px per staff
  space; `null` fits the available width. Glyphs paint via `TextPainter`
  (baseline-anchored, font size = 4 × staff space). `noteheadScheme` selects the
  shape-note / pitch-name / solfège heads; `showNoteNames` draws each note's
  letter below it and `showBeatNumbers` the counting overlay above — teaching
  overlays that also render through the SVG back-end. `elementColors` is a
  repaint-only per-id color map that mirrors `highlightedIds`.
- `CrispNotationTheme` — `staffColor` (furniture), `noteColor` (element ink),
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
| `crisp_notation_core` unit tests (230+) | theory tables + property sweeps, layout rules 1–14, layout edge/quality suites, DSL, SMuFL parsing, validation |
| `crisp_notation` widget tests (70+) | sizing, hit testing, gestures, ghost lifecycle, repaint/relayout policy, asset loading, pixel-level paint verification |
| Golden corpus (25 scenes + hero) | all four clefs, all durations, dots, accidentals, chords, beams, rests, signatures, highlights, kid mode, ghost, fit-to-width (macOS-generated) |
| Example widget tests + integration test | real app boot, gallery scroll, place/select/clear flow, duration & clef controls — `flutter test integration_test -d macos` |
