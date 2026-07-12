# Changelog

## 0.4.0-dev.1 (in progress)

- **Transposing instruments + concert-pitch toggle** (Phase 2.6): a
  `Transposition` (written→sounding interval + direction + octaves, with named
  `bFlat`/`a`/`eFlat`/`f`/`bFlatTenor` constants) on `Score.transposition`.
  `Score.atConcertPitch()` moves the written pitches **and** key signature to
  sounding pitch and clears the tag (`StaffSystem.atConcertPitch()` toggles a
  whole system); `transposedBy` keeps the tag by default (`keepTransposition:
  false` to drop it). MusicXML reads/writes `<transpose>`
  (diatonic/chromatic/octave-change).
- **Pickup / anacrusis measures** (Phase 2.4): `Measure.pickup` marks an
  intentionally incomplete opening bar. A short first bar under a known meter is
  auto-detected as a pickup (both the `Score.simple` DSL and ABC import);
  MusicXML reads/writes it as `<measure implicit="yes">` with anacrusis-aware
  renumbering (the pickup is `number="0"`, real bars count from 1). A new
  `showMeasureNumbers` layout/`StaffView` option draws bar numbers above each
  measure, skipping the pickup so the first full bar reads `1` (golden 80).
  `Measure.copyWith` added.
- **N-staff systems** (Phase 2.1): `StaffSystem` (N `Score` staves + optional
  `StaffBracket` brace/bracket groups) and `layoutStaffSystem` — generalizes
  the two-staff grand staff to any number of staves, laying each out with the
  column-wise-max leading/measure widths so barlines align across the system.
  The Flutter `StaffSystemView` stacks them with connected barlines and left
  brackets/braces, with cross-staff tap hit-testing (golden 75 — a four-staff
  SATB system). *Unblocks multi-voice ABC and tab-paired-with-notation.*
- **ABC multi-voice → staff system**: `staffSystemFromAbc` imports each `V:`
  voice as its own staff — keeping its clef (`V:… clef=…` or the `K:` header)
  and lyrics, with per-voice element-id prefixes so ids stay unique — aligned as
  a `StaffSystem` (golden 76). Both the field-line (`V:1` … `V:2` …) and inline
  (`[V:1]` …) styles are honored; `scoreFromAbc` still returns the first voice.
- **MusicXML multi-part → staff system**: `staffSystemFromMusicXml` imports
  every `<part>` (and every staff of a multi-staff part) as an aligned staff.
  `<part-group>`s from the `<part-list>` become `StaffBracket`s (bracket/brace/
  square/line), and multi-staff parts (piano) are braced; ids get disjoint
  per-staff spaces (golden 77).
- **ABC `Q:` tempo / `P:` parts / line continuation / dotted bar**: header and
  mid-tune `Q:` tempo import as a metronome annotation (`♩ = 120`, with an
  optional quoted label) above the top staff's first note; mid-tune `P:` part
  labels import as annotations; a trailing `\` line-continuation is honored; a
  dotted barline `.|` maps to `BarlineStyle.dotted` and round-trips (a lone `.`
  is still staccato).
- **Nested staff brackets** render with per-depth leftward offsets in
  `StaffSystemView`, so an outer section bracket clears an inner piano brace
  instead of painting over it (golden 78).
- **Up-bow / down-bow articulations** (`Articulation.upBow`/`downBow`): drawn
  above the staff (SMuFL `stringsUpBow`/`stringsDownBow`), imported from ABC
  (`u`/`v` shorthand and `!upbow!`/`!downbow!`) and MusicXML `<technical>`
  (`<up-bow>`/`<down-bow>`), and written back to both (golden 79). Round-trips
  through both formats, coexisting with fingerings in one `<technical>`.
- **ABC import — toward abcjs parity** (Phase 7.3): the reader now handles
  **variant endings / voltas** (`|1 |2`, `[1 [2`, `:|2` → `Measure.volta`),
  **decorations** (`!trill!`/`!fermata!`/`!accent!`… → articulations, ornaments
  and dynamics; shorthand `~ H T M P`), **inline mid-tune fields** (`[K:…]`
  `[M:…]` `[L:…]` → key/meter/unit changes, with the new key sharpening unmarked
  notes), **multi-measure rests** (`Z`/`Zn` → `Measure.multiRest`), **positioned
  annotations** (`"^…"` `"_…"`), **acciaccatura grace** (`{/…}`), and
  **navigation** (`!segno!`/`!D.C.!`/`!D.S.!`/`!fine!`… → `Measure.navigation`,
  which drives the `playbackTimeline` jumps). The writer
  round-trips voltas, decorations, inline key/meter changes and multi-rests. A
  fidelity harness imports the abcjs example tunes as regressions. (PLAN.md
  tracks the remaining ABC constructs and what's gated on Phase 2.1 / 5.10.)
- **Chord identification** (Phase 4.4): `identifyChord(pitches)` /
  `chordSymbolFor(pitches)` — the inverse of `Triad`: names a set of pitches by
  matching its pitch-class set against the common triad / seventh / sixth / sus
  templates, spelling the root from the input and reporting the inversion as a
  slash chord (`C`, `Am7`, `G7`, `Bm7b5`, `C/E`). When two roots fit (C6 vs
  Am7), the bass wins. Pure theory, part of the analysis moat.
- **ABC notation import + export** (Phase 7.3): `scoreFromAbc` /
  `scoreToAbc` — the plain-text format ubiquitous for folk/traditional tunes,
  pure Dart. The reader handles the `M`/`L`/`K` header (meter, unit length,
  key + modes → key signature, clef), then a tune body of pitched notes
  (accidentals with key + measure state, octave marks, `L`-relative and
  fractional lengths), rests, chords, **broken rhythm** (`>`/`<`), ties,
  **tuplets** (`(3`), **slurs**, **grace notes**, staccato, quoted `"C"` chord
  symbols → annotations, bar lines (repeats, double/final), `w:` **lyrics**,
  and multi-voice tunes (first voice). The writer emits the same, so a score
  round-trips through ABC for the data it shares (13 unit + round-trip tests).
  Wired into the CLI (`.abc` in/out, `--from`/`--to abc`). Validated against
  the abcjs example tune-book.
- **Note-name & rhythm-count overlays** (Phase 3.2): `showNoteNames` draws the
  pitch letter (with accidental — `C`, `F#`, `Bb`) under each note (a chord
  stacks its letters); `showBeatNumbers` draws the counting overlay above the
  staff — the beat number on each beat and `+` on the "and" (`1 + 2 + 3 + 4 +`).
  Both are layout options (so the SVG back-end renders them too) exposed as
  `StaffView.showNoteNames` / `.showBeatNumbers`; they coexist for a full
  teaching view (goldens 73, 74).
- **Per-element note coloring, end to end** (Phase 5.1 / interactivity): the
  Flutter painter already colored elements via `PartituraTheme.elementColors`;
  now it is also a first-class **`StaffView.elementColors`** render param
  (app-supplied, repaint-only, mirrors `highlightedIds` and takes precedence
  over the theme), and the pure-Dart **SVG exporter** honors an `elementColors`
  map too — so colored scores (out-of-range, right/wrong feedback, hand
  coloring) render consistently in both back-ends (golden 72; pixel + SVG
  tests).
- **Breath marks & caesuras** (Phase 5.6): `BreathMark(noteId, symbol)` draws a
  comma or a caesura ("railroad tracks") after a note at the top of the staff
  (golden 71). Reads and writes MusicXML `<breath-mark>` / `<caesura>`.
- **Figured bass** (Phase 5.3): `FiguredBass(noteId, figures)` stacks continuo
  figures under a bass note, drawn with the dedicated SMuFL figured-bass glyphs
  (digits + `#`/`b`/`n`/`+` alterations — so accidentals render in the
  engraving font, no text-font tofu; golden 70). Reads and writes MusicXML
  `<figured-bass>` (`<prefix>`/`<figure-number>`/`<suffix>`), so common figures
  round-trip.
- **Jazz articulations** (Phase 5.9): `JazzMark` / `JazzArticulation` — scoop,
  doit, fall (falloff) and plop — draw a brass glyph just before or after the
  notehead (golden 69). They round-trip as standard MusicXML `<articulations>`
  (`<scoop>` / `<doit>` / `<falloff>` / `<plop>`).
- **Fix — `transposedBy` dropped new note/measure fields**: transposing a score
  silently lost notehead shapes and barline styles (added earlier this cycle).
  Both are now carried through (regression-tested), along with jazz marks.
- **Multi-verse lyrics** (Phase 5.4): `Lyric.verse` (1-based) stacks verses on
  their own baselines below the staff (golden 68). Each verse de-overlaps
  independently and its hyphens/extenders align to its own syllables. Reads and
  writes the MusicXML `<lyric number="N">` attribute, so verses round-trip; a
  note may now carry several `<lyric>` children.
- **Text no longer overlaps** (Phase 1.2, first cut): lyrics and text
  annotations (chord symbols, tempo/rehearsal text) were centered over their
  note with no collision check, so wide chord symbols or long syllables on
  close notes ran together. The layout now reserves a conservative per-glyph
  width (~0.62 em, covering wide glyphs like `m`/uppercase) and nudges each
  text right of the previous by at least a word gap — guaranteeing no
  horizontal overlap within a row while keeping lyric hyphens/extenders
  aligned to the shifted syllables (golden 67; asserted in
  `layout_more_test.dart`).
- **Notehead shapes** (Phase 5.1): `NoteElement.notehead` / `NoteheadShape`
  (x, diamond, triangle-up, slash, circled-x) overrides the default oval; the
  duration still picks the filled/open/whole/double-whole variant (golden 66).
  Reads and writes the MusicXML `<notehead>` element (`x` / `diamond` /
  `triangle` / `slash` / `circle-x`), so it round-trips. SMuFL codepoints for
  the shape heads were added to the shared codepoint table.
- **Barline styles** (Phase 5.6): a measure's closing barline can now be a
  double bar, final (thin+thick), heavy, dashed, dotted, or none
  (`Measure.barline` / `BarlineStyle`; DSL `!barline=<style>`; golden 65). An
  explicit style on the last measure overrides the default final barline. Reads
  and writes MusicXML `<bar-style>` (`light-light` / `light-heavy` / `heavy` /
  `dashed` / `dotted` / `none`), so it round-trips.
- **Nested repeats** (Phase 7.4): `playbackTimeline` now expands repeat
  barlines with a stack instead of a single start/pass pair, so nested
  `|: … |: … :| … :|` structures unfold correctly — the inner repeat finishes
  each time before the outer jumps back — and two sequential repeats are
  tracked in turn. Voltas still select their bracket by the enclosing repeat's
  pass. (A volta measure that is *also* an inner repeat start remains
  ambiguous and unsupported.)
- **Beams over rests** (Phase 1.4): a rest inside a beat no longer breaks a
  beam — the beam spans the gap (golden 64), matching standard engraving (and
  now, e.g., a triplet `[8th, rest, 8th]` beams under its bracket instead of
  flagging). A rest at a beat boundary still separates, so beats stay distinct.
- **Artificial & pinch harmonics** (Phase 6.4): `TabNoteStyle` gains
  `artificialHarmonic` and `pinchHarmonic` (helper `isHarmonicStyle`). The tab
  engine draws all three harmonic variants with the angle-bracketed fret and
  adds an "A.H." / "P.H." label above the staff for the synthetic ones (golden
  63). The GP3/4/5 binary readers classify the harmonic-type byte, and GPIF
  read+write carry `HarmonicType` (Natural/Artificial/Pinch), so the type
  survives a `.gp` round-trip. Confirmed on the alphaTab corpora
  (`harmonic-types.gp4`: 3 natural / 3 artificial / 1 pinch; GP4 and GP5 agree).
- **Guitar Pro binary import — more note effects** (Phase 7.3): the GP3/4/5
  binary readers now surface **vibrato** (`Vibrato`; note-level in GP4/5,
  beat-level "wide" in GP3 and GP5), and **palm mute** / **let ring**
  (per-note flags coalesced into `PalmMute` / `LetRing` bracket spans that a
  rest closes). They already rendered in the tab engine; the readers just
  weren't feeding them. Confirmed against the real alphaTab corpora, where all
  three versions agree (`vibrato.*`, `effects.*` fixtures) — except GP3, which
  has no note-level palm mute.
- **Guitar Pro 3/4 (.gp3/.gp4) import** (Phase 7.3):
  `gp3ToScore` / `gp4ToScore` extend the GP5 binary reader with the older
  layout — one voice per measure, no RSE/page-setup, GP3's beat-level
  harmonics, and the narrower beat/note effect flags. Same technique coverage
  (HO/PO, slides, bends, dead, harmonic). Committed regression tests parse the
  real alphaTab GP3/GP4 corpora and confirm the versions agree note-for-note
  (`gp_fixtures_test.dart`). The reader now lives in `gp_binary_reader.dart`.
- **Guitar Pro 5 (.gp5) import** (Phase 7.3): `gp5ToScore(bytes, {trackIndex})`
  — a from-scratch byte/bit-exact reader for the GP5 *binary* format (ported
  from PyGuitarPro's layout): measures, time signatures, per-track tunings,
  notes as string+fret → pitch, and the note techniques (HO/PO, slides, bends,
  dead, harmonic). Pure Dart. Validated against the alphaTab GP5 corpus —
  `chords.gp5` renders identically to `chords.gp` (GP7). Wired into the CLI.
- **Guitar Pro technique import** (Phase 7.3): `scoreFromGpif` now reads the
  common GPIF playing techniques into partitura's tab marks — hammer-on/
  pull-off → slur, slide → glissando, bend (with amount) → `Bend`, whammy
  vibrato → `Vibrato`, dead → `TabNoteMark.dead`, harmonic →
  `TabNoteMark.harmonic`. Validated against the alphaTab GP7 corpus (e.g.
  `bends.gp` renders correct "full"/"1½" bend arrows).
- **Tab chord voicing** (fix): `TabLayoutEngine` now assigns each chord tone to
  a **distinct string** (higher pitches to higher strings, lowest fret first)
  instead of placing every pitch at its independent lowest fret — so two notes
  of a chord no longer collide on one line (visible on dense real Guitar Pro
  chords). Pinned `TabVoicing`s still win; hand-designed goldens are unchanged.
- **Guitar Pro (GPIF) import/export** (Phase 7.3): `scoreFromGpif` /
  `scoreToGpif` read and write the `score.gpif` XML of the Guitar Pro 6/7/8
  formats — a subset (tuning, bars → voices → beats → string+fret notes,
  rhythms; single track/voice), pure Dart. Pitches and rhythm round-trip. The
  `.gp` ZIP container is handled in `partitura_cli` (needs `dart:io`), which
  also gains `.gp`/`.gpif` input+output. Because every codec funnels through
  the one `Score` model, formats round-trip transparently for the data they
  share (see `interchange_transparency_test.dart`). Validated against real
  files: the GPIF reader reads the alphaTab GP7 test corpus (incl. a 96-bar
  song) correctly, and the MusicXML/MIDI importers read real music21 corpus
  files (Bach chorales, Corelli) — verified by rendering.
- **Chord diagrams above the staff** (Phase 6.4): `Score.chordDiagrams`
  (`PlacedChordDiagram(elementId, diagram, {scale})`) places a fretboard
  diagram over a note on a shared row above the staff — the lead-sheet
  convention (multiple diagrams over notes) — drawn by **both** the notation
  and tab engines. `ChordDiagram`/`PlacedChordDiagram` moved into the model.
- **Tapping + tremolo-bar** (Phase 6.4, tab techniques): `Score.taps`
  (`Tap(noteId)` — a "T" above the fret) and `Score.tremoloBars`
  (`TremoloBar(noteId, {steps})` — a whammy-bar V with the dip amount, separate
  from string bends). Golden scene 61.
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
