# Changelog

## 0.4.0-dev.1 (in progress)

- **Chord / fretboard diagrams** (Phase 6.4): `ChordDiagram(frets, {name,
  fingers, baseFret, fretSpan, barreFret})` + `layoutChordDiagram(diagram,
  settings)` produce a standalone diagram `ScoreLayout` — string×fret grid,
  filled fingering dots, open/muted x·o markers, name, base-fret label, and an
  optional barre — rendering through the SVG/PNG pipeline. Adds an optional
  `round` cap to `LinePrimitive` (a zero-length round line is a filled dot).
- **Tab capo + tuning labels** (Phase 6.2/6.5): `TabLayoutEngine.layout` (and
  `TabStaffView`) gain `capo` (fret numbers read relative to the capo, with a
  "capo N" label) and `showTuning` (each open string's note letter in a left
  gutter). Golden scene 60.
- **Per-note tab string override** (Phase 6.2): `Score.tabVoicings`
  (`TabVoicing(noteId, strings)`) pins each pitch of a tab note to an explicit
  string (0 = top line), overriding the engine's lowest-fret placement (an
  out-of-range pin falls back). The ASCII-tab importer now emits voicings, so
  an imported tab re-renders on the strings it was written on.
- **Plain-text (ASCII) tablature import** (Phase 7.3): `asciiTabToScore(text,
  {tuning, duration})` → `Score` parses the informal web-shared guitar/bass
  tab (dashed string lines + fret numbers) into a pitched, unmetered score:
  chords from aligned columns, barlines from `|`, and techniques `h`/`p` →
  slur, `/`/`\` → glissando, `b` → bend, `~` → vibrato, `x` → dead note.
  Durations are uniform by default, or (with `inferRhythm: true`) *interpreted
  from the horizontal spacing* — smallest gap = an eighth, wider gaps scale up.
  Wired into `partitura_cli` (`.tab`/`.crd`/`.txt`; `--infer-rhythm`).
- **SVG export** (Phase 7.2): `scoreToSvg(layout, {…})` renders a
  `ScoreLayout` to a standalone SVG document (works for both notation and
  tablature); optional `@font-face` embedding of the engraving font. The
  `smuflCodepoints` glyph-name→character table moved into `partitura_core`
  (shared by the Flutter painter and the SVG emitter). Pure Dart.
- **MIDI import** (Phase 7.3): `scoreFromMidi(bytes)` → `Score` parses a
  Standard MIDI File (format 0/1, running status supported). Lossy single-
  staff reconstruction: sharps/treble, sixteenth-grid quantization, chords
  from simultaneous notes, measures packed by the file's time signature with
  cross-barline ties. Round-trips the pitches and quantized rhythm of an
  exported score. Zero new dependencies.
- **MIDI export** (Phase 7.1): `scoreToMidi(score, {quarterBpm,
  ticksPerQuarter})` → a Standard MIDI File (format 0) `Uint8List`, built off
  `playbackTimeline` so repeats / voltas / D.C./D.S./Coda jumps unfold into the
  MIDI. Tempo + time-signature meta, note on/off per pitch, voice 1/2 on
  channels 0/1. Contract-safe (no audio — a byte stream for a consumer's
  synth). Zero new dependencies (`dart:typed_data`).
- **Repeat unfolding — navigation jumps** (Phase 7.4): `playbackTimeline` now
  executes D.C. / D.S. / To Coda / al Fine / al Coda jumps when linearizing a
  score (in addition to repeat barlines and voltas), closing the jump
  execution deferred in v0.7.1. One level: after a D.C./D.S. return the score
  plays straight through (inner repeats not re-taken); a D.S. with no segno or
  an *al Coda* with no coda throws `ArgumentError`.
- **Guitar/bass tablature — foundation** (v0.8): `Tuning` (open-string
  pitches + `fretFor` lowest-fret assignment; standard guitar, drop D, bass
  presets) and `TabLayoutEngine`, which renders a `Score` as fret numbers on
  an N-line string staff with a TAB clef and broken string lines. Includes
  rhythm (stems, flags, per-beat beams below the staff) and playing
  techniques — slides (reuse `Score.glissandos`), hammer-on/pull-off arcs
  (reuse `Score.slurs`), string bends (`Score.bends` — `Bend(noteId,
  {steps})`), vibrato (`Score.vibratos` — `Vibrato(noteId, {wide})`, a wavy
  line above the fret) and palm mute / let ring (`Score.palmMutes` /
  `Score.letRings` — a labelled dashed bracket above the staff) and dead /
  ghost / natural-harmonic notes (`Score.tabNoteMarks` — `TabNoteMark(noteId,
  TabNoteStyle.dead | .ghost | .harmonic)`; "x", a parenthesized fret, or an
  angle-bracketed fret); more techniques land incrementally. Lifts the former
  "tablature out" scope.
- **Forced beam slant** (Phase 1.4): `Score.beamSlants`
  (`BeamSlant(startId, endId, {slant})`) — forces a note run into one beam
  group with a fixed slant (0 = horizontal). Model-only.
- **Feathered beams** (Phase 1.4, engraving quality): `Score.featheredBeams`
  (`FeatheredBeam(startId, endId, {beginBeams, endBeams})`) — forces a note
  run into one beam group and fans the beam count from start to end
  (accelerando/ritardando). Model-only.
- **Sustain-pedal marks** (v0.7.2): `Score.pedals` (`Pedal(startId, endId)`)
  — "Ped." under the start note and a release star under the end, on a line
  below the staff. Model-only; MusicXML `<pedal type=start/stop>`
  round-trips. **Completes the v0.7.2 piano/technical cluster.**
- **Tremolo** (v0.7.2): `NoteElement.tremolo` (1–5 strokes) drawn through
  the stem of a stemmed, unbeamed note. Model-only; MusicXML
  `<ornaments><tremolo type="single">` round-trips (coexists with a trill/
  mordent/turn ornament in the same `<ornaments>`).
- **Glissando / slide** (v0.7.2): `Score.glissandos`
  (`Glissando(startId, endId)`) — a straight line between two notes, same
  id/order validation as slurs. Model-only; MusicXML `<slide>` round-trips.
- **Arpeggio / rolled chord** (v0.7.2): `NoteElement.arpeggio`
  (`Arpeggio.up`/`down`) — a vertical wavy line left of the chord, tiled
  from `wiggleArpeggiatoUp` and capped with a direction arrowhead.
  Model-only (no DSL shorthand, like dynamics/hairpins); MusicXML
  `<arpeggiate direction=…>` round-trips.
- **Fingering numbers** (v0.7.2): `NoteElement.fingerings` (digits 0–9)
  stacked above the note from the notehead upward. DSL `=N` / `=1,3,5`
  suffix (may precede other markers, e.g. `c4:q=2~`); MusicXML
  `<technical><fingering>` round-trips (one per chord tone). Also fixes a
  latent bug where a chord's ornament was dropped on MusicXML import.
- **Navigation marks** (v0.7.1 long-tail parity): `Measure.navigation`
  (`NavigationMark`) — segno/coda targets and the D.C./D.S./To Coda/Fine
  instruction words (incl. *al Coda*/*al Fine*). DSL `!nav=<mark>`; drawn on
  one shared line above the staff per system (glyph targets at the measure
  start, right-aligned instruction words at its end); MusicXML `<direction>`
  (`<segno>`/`<coda>`/`<words>` + `<sound>`) round-trips. Playback timing is
  unchanged — the marks render and round-trip but the timeline does not yet
  execute the jumps.
- **Octave clefs + ottava brackets** (v0.6 polish): `Clef.treble8va`/
  `treble8vb`/`bass8vb` (staff arithmetic, key signatures, MusicXML
  `<clef-octave-change>`); `Ottava(startId, endId, down:)` spans draw
  their notes an octave off sounding pitch under a dashed 8va/8vb
  bracket, and round-trip via MusicXML `<octave-shift>`.
- **Multi-measure rests** (v0.6 polish): `Measure.multiRest` / DSL
  `!mrest=N` — H-bar with end caps on the middle line, count in
  time-signature digits above; playback advances N bars of the current
  meter; MusicXML `<measure-style><multiple-rest>` round-trips.
- **Ornaments** (v0.6 polish): `NoteElement.ornament` — trill, short
  trill (upper mordent), mordent, turn — drawn above the element
  (above a fermata when both exist). DSL markers `%`, `\$`, `&`, `?`;
  MusicXML `<ornaments>` import/export round-trips.
- **Accidental stacking** (v0.6 polish): chord accidentals pack into
  columns — zigzag order from the outside in, each accidental taking
  the rightmost column it clears by ≥ 3 spaces. Octave-apart
  accidentals now share a column; adjacent ones still fan out.
- **Transposition**: `Score.transposedBy(interval, descending:)` moves
  every pitch (chords, both voices, grace notes) plus the key signature
  and mid-score key changes; out-of-range keys wrap enharmonically
  (G♯ major → A♭ major). Ids, rhythm, spans, lyrics unchanged;
  chord-symbol text is not rewritten.
- **Playback-cursor API** (no audio, ever): `playbackTimeline(score)`
  flattens a score into `PlaybackNote`s — exact whole-note `Fraction`
  onsets/durations (tuplet-scaled), rests flagged, two voices in
  parallel, repeats/voltas expanded (`expandRepeats: false` opts out).
  `soundingAt(timeline, t)` yields the ids to highlight;
  `secondsFor(t, quarterBpm:)` maps musical time to wall-clock time.
- **MusicXML export**: `scoreToMusicXml(score)` and
  `grandStaffToMusicXml(grandStaff)` emit `score-partwise` documents
  over the same subset as the importer; every feature round-trips
  through `scoreFromMusicXml` back to a value-equal `Score` (divisions
  chosen as the LCM of all duration denominators, so tuplet durations
  stay integral).
- **MusicXML import (subset)**: `scoreFromMusicXml(xml)` and
  `grandStaffFromMusicXml(xml)` parse `score-partwise` documents —
  pitches/chords/rests, durations (breve…64th, dots), accidentals,
  ties, slurs, tuplets, articulations, grace notes, dynamics, wedges,
  lyrics, `<harmony>` chord symbols, key/time/clef with mid-score
  changes, repeats/voltas, two voices, two-staff parts. Ships its own
  minimal XML reader — the package stays dependency-free. Unsupported
  markup is ignored; unrepresentable documents throw `FormatException`.

- **Chord symbols / annotations**: `Annotation(elementId, text)` on
  `Score.annotations`; DSL `annotations:` parameter (`*` skips a note).
  Text on a shared baseline above all other ink, centered over the
  note; element hit regions grow upward.
- **Lyrics**: `Lyric` (elementId, text, `hyphenToNext`, `extender`) on
  `Score.lyrics`; DSL `lyrics:` parameter (`*` skips a note, trailing
  `-` hyphenates, trailing `_` starts a melisma extender). Layout puts
  all syllables on one baseline below the lowest ink (`TextPrimitive`,
  center-baseline anchored; core estimates widths at 0.5 em/char),
  draws hyphen dashes and extender lines, and grows element hit
  regions. Systems keep their own syllables under line breaking.
- **Line breaking + justification**: `layoutSystems(score, settings,
  maxWidth: …)` breaks a score into `MultiSystemLayout`/`SystemLayout`
  lines — greedy measure packing, clef/key restated per system, the time
  signature only on the first system (but still governing beaming),
  mid-score changes threaded across breaks, slurs/dynamics/hairpins
  spanning a break dropped, non-final systems justified to `maxWidth` by
  binary-searched spacing stretch, thin closing barlines on continuing
  systems. `LayoutEngine.layout` gained `spacingStretch`,
  `drawTimeSignature` and `finalBarline` knobs.
- **Grand staff**: `GrandStaff` + `layoutGrandStaff` — two-pass layout
  aligning leading widths and per-measure widths across staves;
  `LayoutEngine.layout` gained optional `leadingWidth`/`measureWidths`
  minimums.
- **Two voices per staff**: `Measure.voice2` (DSL `;` separator) — voice 1
  stems up, voice 2 stems down; elements sharing an onset align in one
  column (union of both voices' onsets), rests displace vertically,
  cross-voice unisons/seconds shift voice 2 rightward, beams stay per
  voice, ties bind within their voice, accidental state is shared.

## 0.3.0-dev.1


- **Mid-score changes, repeats, voltas**: per-measure `clefChange` /
  `keyChange` (cancellation naturals) / `timeChange` — layout threads the
  current state so positions, accidentals and beam windows follow; repeat
  barlines (`!repeat` / `!endrepeat`), volta brackets (`!volta=n`); DSL
  measure directives.
- **32nd/64th notes and the breve**: new `DurationBase` values (DSL
  letters `t`, `x`, `b`); flags to four hooks, multi-level beams with
  per-level runs and beamlets, extended stems, breve notehead/rest,
  exact 2/1 breve fractions.
- **Grace notes**: `NoteElement.graceNotes` (DSL `{g4}a4:q`), rendered
  as 0.6× slashed eighths before the host; `GlyphPrimitive` gained a
  `scale` field.
- **Dynamics & hairpins**: `Score.dynamics` (pp…ff SMuFL glyphs
  centered under their element) and `Score.hairpins`
  (crescendo/diminuendo wedges), on a shared dynamics line below the
  staff.
- **Articulations**: `NoteElement.articulations` (staccato, tenuto,
  accent, marcato, fermata; DSL markers `' _ > ^ @`), drawn on the
  notehead side opposite the stem, stacked outward; fermatas always
  above and outside the staff.
- **Tuplets**: `TupletSpan` on `Measure` (DSL `3[…]` / `5:4[…]`);
  exact effective durations (`Measure.effectiveDurationAt`), tuplet-aware
  spacing and beam windows (beams never cross a tuplet boundary), ratio
  digit + bracket on the stem side.
- **Slurs**: `Score.slurs` (`Slur(startId, endId)`, DSL `(`/`)` token
  suffixes); the curve goes above unless every spanned note stems up and
  arcs clear of the spanned elements' ink.
- **Ties**: `NoteElement.tieToNext` (DSL suffix `~`) draws tie curves to
  identically-pitched noteheads of the next note element, also across
  barlines; sits opposite the stem. New `CurvePrimitive` (cubic Bézier)
  in the display list — the foundation slurs reuse.

## 0.2.0-dev.1

- **Alto and tenor clefs**: `Clef.alto` (C clef on the middle line, bottom
  line F3) and `Clef.tenor` (C clef on the fourth line, bottom line D3).
  Staff positions, `pitchAt`, layout anchoring and per-clef key-signature
  placement (incl. the tenor sharp pattern) are fully supported; beaming,
  stems, accidentals and interaction generalize unchanged.

## 0.1.0-dev.1

Initial release.

- **Theory**: `Pitch` (MIDI numbers, staff positions per clef, diatonic
  transposition, enharmonics, parsing), `Interval` (P1..P8, d/m/M/A,
  `Interval.between`), `NoteDuration` with exact `Fraction` arithmetic,
  `KeySignature` (−7..7), `TimeSignature`, `Scale` (major, natural/
  harmonic/melodic minor), `Triad` (four qualities, inversions), `Key`
  with `HarmonicFunction` primary triads.
- **Model**: `Score`/`Measure`/`NoteElement`/`RestElement` value types and
  the `Score.simple` string DSL (sticky durations, chords via `+`,
  measures via `|`, auto element ids).
- **Layout**: deterministic `LayoutEngine` producing a `ScoreLayout`
  display list (glyphs, lines, beams) plus element hit regions and measure
  regions, in staff spaces: clefs, key/time signatures, noteheads, stems
  with middle-line extension, flags, beat-based beaming with secondary
  beams and beamlets, ledger lines, accidentals with measure memory,
  augmentation dots, chord clustering, rests, proportional spacing,
  barlines.
- **SMuFL**: `SmuflMetadata` parser for SMuFL font metadata (engraving
  defaults, glyph bounding boxes, stem anchors) and glyph-name constants.
