# Changelog

## 0.4.5 (2026-07-17)

- **`SeventhChord` builder** — the four-note counterpart to `Triad`: voices any
  seventh-chord `ChordType` (dominant / major / minor / half-diminished /
  fully-diminished / minor-major / augmented) on a root, in inversions 0–3,
  spelled with real intervals so accidentals engrave correctly and
  `identifyChord` / `romanNumeralOf` round-trip it (`V7`, `ii7`, `viiø7`,
  `V6/5`, `vii°7`). Adds `Interval.diminishedSeventh` (9 semitones) for the
  fully-diminished chord's seventh.

## 0.4.4 (2026-07-16)

- **Note names under noteheads**: `NoteNameStyle` (`letter` — C D E F G A B;
  `german` — B-natural is **H** and B-flat is **B**; `solfege` — fixed-do
  do re mi fa sol la ti) plus `showNoteNames:` / `noteNameStyle:` on
  `LayoutEngine.layout(...)` and on the staff-system, multi-system, grand-staff
  and multi-part layout entry points. Off by default; a teaching aid for
  early readers. Additive — no signature breaks.

## 0.4.3 (2026-07-15)

- **Runnable example** (`example/crisp_notation_core_example.dart`): a tour of
  the theory model and the terse score DSL. Docs-only; no API changes.

## 0.4.2 (2026-07-15)

- **Configurable staff-line count** (N-line staves): `LayoutEngine.layout(...,
  staffLineCount:)` draws staves with any number of lines — 1 for a neutral
  percussion/rhythm line, 3, 6, or more for non-standard and pedagogical staves
  — instead of assuming a 5-line staff. Every vertical reference (staff lines,
  bounding box, stem direction, stem-length clamps, ledger lines, and beam
  slant clamps) derives from the line count. The default remains 5 lines and is
  byte-for-byte identical to previous output.

## 0.4.1 (2026-07-14)

- **Imported sheet titles**: MusicXML `<credit>` title/composer text is now used
  as metadata fallback when `<work>` / `<identification>` metadata is absent,
  matching common MuseScore/Verovio exports.

- **Multi-part MusicXML writer** (Workshop C11): `multiPartToMusicXml(MultiPartScore,
  {partNames})` serializes an N-part score as one `score-partwise` document that
  round-trips through `multiPartScoreFromMusicXml` — brackets become
  `<part-group>` `<group-symbol>` (brace/bracket), connected barline groups add
  `<group-barline>yes</group-barline>`, and each part keeps its `<transpose>`.

- **Explicit system / page breaks** (Phase 2.5): `layoutSystems(..., systemBreaks:)`
  forces a line break before given measure indices; `layoutPages(...,
  systemBreaks:, pageBreaks:)` forces a new page (a page break implies a system
  break). Width-driven breaking still applies elsewhere.

- **Braille mid-score signature changes** (Phase 7.5): `scoreToBraille` reprints
  the key/time signature at a measure with a `keyChange` / `timeChange`, and the
  running key drives accidental suppression from that point.

- **Measure-repeat (simile) signs** (Phase 2.7): `Measure.measureRepeat` (1, 2
  or 4) draws the SMuFL repeat-bar glyph centred in an otherwise-empty bar —
  repeating the previous 1/2/4 bar(s). Golden 126.

- **ABC lyric alignment skips rests** (hardening G8): the ABC reader no longer
  counts rests as syllable positions, so a `w:` line aligns to notes only. Real
  vocal round-trips (Mozart songs) previously attached syllables to rests, which
  shifted the rest onto later notes and crashed the lyric layout.

- **Braille signatures + chords** (Phase 7.5): `scoreToBraille` now emits a
  leading signature header (standard key signature, then time signature as
  number-sign + upper/lower digits) and renders chords as the top note plus
  downward interval signs (2nd-octave, compound via an octave mark).

- **ABC `!invertedturn!`** (Phase 7.3): the ABC reader maps the `!invertedturn!`
  decoration to `Ornament.invertedTurn` (rounding out the ornament set).

- **Metric-aware secondary beaming** (Phase 4.7 tail): secondary (16th+) beams
  now break at the meter's pulse rather than always the quarter — in compound
  (6/8, 9/8, 12/8) and additive (3+2/8) meters they break at the base unit, so a
  run of sixteenths inside a dotted-quarter beat groups at each eighth. Simple
  and cut-time meters are unchanged (no golden churn); golden 122 shows 6/8.
- **Every-N measure numbering** (Phase 2.7): `LayoutEngine.layout(...,
  measureNumberInterval:)` labels only bar 1 and every Nth counted bar (the
  common "every 5 bars" convention); 1 = every bar (unchanged default).

- **Forte set-class numbers** (Phase 4.5 tail): `forteNumber(pcs)` names a
  pitch-class set the familiar way — a minor triad → `3-11`, a dominant seventh
  → `4-27`, the major scale → `7-35`, with `Z` on Z-related classes. Trichords
  through pentachords come from the catalogue; septachords through decachords are
  derived from their complement (Forte's shared-ordinal convention). A
  completeness test over all 2¹² subsets verifies the catalogue is exactly
  complete with the canonical per-cardinality class counts. (Hexachords return
  null for now — the prime form stays the canonical identifier.)
- **Explicit irregular-bar length** (Phase 2.4): `Measure.actualDuration` (a
  `Fraction?`) overrides the meter's capacity for a mid-piece irregular bar
  (an inserted 5/4 in 4/4, a cadenza) without a meter change; `capacityGiven(meter)`
  resolves the effective capacity and pickup auto-detection leaves an
  explicitly-sized bar alone.

- **Enharmonic chord re-reads** (Phase 4.4 tail): `chordReadings(pcs, {bassPc})`
  returns *every* tonal reading of a pitch-class set — one per root whose
  template matches — surfacing the ambiguities a single spelled reading hides:
  `{0,4,7,9}` reads as both C6 and Am7; a diminished seventh reads four ways
  (C°7 = E♭°7 = G♭°7 = A°7), an augmented triad three. `bassPc` orders the
  readings and drives inversion. (Spelling-dependent augmented sixths stay with
  `identifyChord`.)

- **Accessible score labels** (Phase 3.9): `semanticLabel(element)` gives a
  spoken, screen-reader-friendly description of a note/rest — pitch names spelled
  out and the duration named (`"C sharp 4 quarter note"`, `"C 4, E 4, G 4 chord,
  half note"`, `"quarter rest"`); `semanticLabels(score)` maps every element id
  to one. Drives the new per-note `Semantics` on `StaffView` (Flutter side).
- **Braille music export** (Phase 7.5): `scoreToBraille(Score)` renders a
  single-staff score as Unicode braille-music cells — note signs (name + value),
  rests, accidentals (only when not implied by the key signature), octave marks
  by the standard interval rule, dotted-note augmentation cells, and blank-cell
  measure separators. A first accessibility export; chords, in-accord voices,
  signatures and dynamics are follow-ups. Backed by `braille_writer_test.dart`.

- **Multi-part document wrapping** (Workshop contract C6, increment 1):
  `layoutStaffSystemSystems(StaffSystem document, …, maxWidth:)` breaks an
  N-part system into justified systems with barlines aligned across every part —
  the multi-part counterpart of `layoutGrandStaffSystems`. It packs measures by
  the widest part, draws the time signature only on the first system, closes
  non-final systems with a plain barline and stretches them to fill the width
  (shared note-spacing stretch), and returns `StaffSystemSystems`
  (`StaffSystemSystem` per line, with its measure range). `layoutStaffSystem`
  gains `spacingStretch` / `drawTimeSignature` / `finalBarline` to support it.
  Backed by `staff_system_systems_test.dart`.

- **Warped-time cursor** (Phase 3.5): `TempoMap` converts musical time
  (whole-note `Fraction`s) ↔ wall-clock seconds under piecewise-constant tempo
  (`TempoSpan`s), extending the fixed-clock `secondsFor` to scores with tempo
  changes (`secondsAt` / `timeAt`, `TempoMap.constant`). `SyncPoints` maps
  app-supplied `(musical time, seconds)` anchors with linear interpolation and
  end-extrapolation, so the cursor can follow a live or slowed-down performance.
  `Tempo.quarterBpm` normalizes any metronome mark (beat unit + dots) to
  quarter-notes-per-minute.

- **Hide empty staves** (Phase 2.3): `layoutStaffSystem(..., hideEmptyStaves:)`
  drops staves that contain only rests across the whole system (keeping at least
  one) and remaps the bracket groups to the surviving staves — a bracket that
  spanned only-hidden staves is removed. The reduced system is carried in
  `StaffSystemLayout.source`, so bracket/barline rendering follows it. Backed by
  `staff_system_test.dart`.

- **Extended-chord & augmented-sixth identification** (Phase 4.4):
  `identifyChord` / `chordSymbolFor` now recognize extended chords via
  standard-voicing templates — `add9`, `m(add9)`, `6/9`, `9`, `maj9`, `m9`,
  `11`, `m11`, `13`, `maj13`, `m13` — and the three augmented sixths
  (`It+6` / `Fr+6` / `Ger+6`), detected by the *spelled* augmented-sixth
  interval between ♭6 and ♯4 so a German sixth is not misread as its enharmonic
  dominant seventh (A♭–C–E♭–F♯ → `Ger+6`, while A♭–C–E♭–G♭ → `Ab7`).
- **`pitchesForElements(score, ids)`** (Phase 3.1): maps a set of element ids
  (e.g. the playback cursor's currently-highlighted ones) to the set of sounding
  MIDI pitch numbers — chords contribute every pitch; rests / grace notes /
  unknown ids contribute nothing; scans every voice. Drives the instrument
  visualizers.
- **Tab paired with a notation staff** (Phase 6.3): `layoutNotationTab` returns
  a `NotationTabLayout` — a notation staff over a tab staff of the same `Score`,
  laid out once for natural widths then re-laid with the column-wise maxima so
  every barline aligns. `TabLayoutEngine.layout` gains `leadingWidth` and
  absolute `barlineXs` (the notation and tab engines use different inter-measure
  gaps, so the tab barlines are pinned to the notation's canonical x rather than
  shared relative widths, which would drift). `notation_tab_test.dart` asserts
  barline alignment across guitar and bass tunings. Rendered by the new Flutter
  `NotationTabView` (golden 118).
- **Tab Tier-3 completeness tail** (Phase 6.4, fully completes 6.4): tapped /
  semi / feedback harmonics (`TabNoteStyle.tappedHarmonic` / `.semiHarmonic` /
  `.feedbackHarmonic` — angle-bracketed fret + `harmonicLabel` "T.H." / "S.H." /
  "Fbk."; round-trip through GP `HType` Tap/Semi/Feedback); named rasgueado
  strum patterns (`Rasgueado.pattern`); golpe (`Golpe` — a "×" body-tap above
  the fret); wah open/close (`Wah` — "o" / "+"); fade-in/out swells (`Fade`
  span — a growing/shrinking wedge above the staff); and instrument-specific
  chord-diagram presets (`ChordPresets` — ukulele/banjo/mandolin common chords).
  All additive and preserved through `transposedBy`; covered by
  `tab_layout_test.dart` / `chord_presets_test.dart`; golden 117.
- **`Score.barNumberAt(index)`** (Workshop contract C9): the displayed bar
  number of a measure with any pickup (anacrusis) uncounted — 1-based over
  non-pickup measures, `null` for a pickup itself. Exposes the numbering the
  measure-number overlay and the MEI writer already computed (both now route
  through it — one source of truth) for app-side bar labels / navigation.
- **System dividers** (Phase 5.6): `ScorePageView.showSystemDividers` draws a
  `//` (the SMuFL `systemDivider` glyph) in the left margin above each system
  after the first on a multi-system page — the engraver's cue that a new system
  begins. Off by default. Golden 116.

## 0.4.0 (2026-07-13)

First tagged release. Everything below shipped during the 0.4.0 cycle.

- **Lyric-driven horizontal spacing** (Phase 5.4, completing it): a lyric
  syllable wider than its note's natural advance now widens the note spacing so
  the following note clears the syllable (rather than only nudging the text).
  Only wide syllables on short notes are affected; narrow syllables leave
  spacing unchanged. Golden 68 re-rendered.
- **Interchangeable / alternating meters** (Phase 5.7): `TimeSignature.alternate` `TimeSignature.alternate`
  carries a companion signature drawn beside the primary at the start of the
  system (e.g. 3/4 with a 2/4 alternate). Display-only — `measureCapacity` and
  `beamGroups()` use the primary meter; individual bars switch via their own
  change. Round-trips through MusicXML `<interchangeable>`. Golden 115.
- **Baroque ornaments** (Phase 5.6): four new `Ornament`s — `invertedTurn` and
  the trill-with-accidental trio (`trillSharp`/`trillFlat`/`trillNatural`, drawn
  as a small standard accidental above the `tr`, so any SMuFL font works). They
  round-trip through MusicXML (`<inverted-turn>`, `<trill-mark>` +
  `<accidental-mark>`); ABC/kern/MEI/LilyPond take documented lossy fallbacks.
  Golden 114.
- **Portamento** (Phase 5.6): `Portamento(startId, endId)` draws a smooth curved
  slide line between two notes — the curved counterpart to a `Glissando`'s
  straight line. Render-only. Golden 113.
- **Tab technique tail — bend curves, whammy, slide in/out, strum** (Phase 6.4,
  completes 6.4): `Bend.curve(id, [BendPoint(offset, steps), …])` draws a
  multi-segment bend contour (bend-release, prebend, bend-release-bend) as a
  pitch-vs-time polyline with an arrow + amount label at each rise target;
  `TremoloBar.curve` is the analogous *separate* whammy system for
  dip/dive/return gestures (down-arrow + label at each trough). `TabSlide`
  (`SlideInOut.inFromBelow/inFromAbove/outUpward/outDownward`) draws a short
  diagonal sliding into or out of a single fret; `PickStroke` draws a downstroke
  (⊓) or upstroke (∨) above the fret; and `NoteElement.arpeggio` now renders on
  tab as a wavy vertical arrow rolling the chord. All additive and preserved
  through `transposedBy`; `tab_layout_test.dart` covers each; golden 115.
- **Cue / small notes** (Phase 5.1, completing it): `Score.cueNoteIds` marks
  note elements drawn small — notehead, stem, flag and augmentation dots at
  0.72× — for cue / ossia passages. Additive (existing scores are byte-identical
  at scale 1.0). Golden 112. (Beamed cue notes scale the head now; their shared
  stems/beam scale in a follow-up.)
- **Pitch-name & solfège noteheads** (Phase 5.1): two more `noteheadScheme`s —
  `NoteheadScheme.pitchName` draws the note's letter (C–G) in place of the
  notehead, and `NoteheadScheme.solfege` the movable-do syllable (do, re, mi, …)
  from the pitch's scale degree in the current key. Teaching aids that complete
  the notehead-scheme family alongside the shape-note schemes. Goldens 109/110.
- **Grace notes on the tab staff** (Phase 6.4): `NoteElement.graceNotes` now
  render on tablature as small fret digits crammed into the gap just left of the
  principal note — each on its tuning string, connected to the principal by a
  legato arc. An acciaccatura (`GraceStyle.acciaccatura`, the default) draws a
  slash through the grace digit; an appoggiatura omits it. Multiple graces stack
  in reading order. `tab_layout_test.dart` asserts the small digit, the arc, and
  the slash-vs-no-slash distinction; golden 107.
- **Extended trills** (Phase 5.6): `TrillExtension(startId, endId)` draws a `tr`
  glyph over the start note followed by a wavy line (tiled `wiggleTrill`
  segments) running to the end of the trilled note's duration. Round-trips
  through MusicXML `<wavy-line>` (a paired trill-mark on read is folded into the
  span, not a redundant single-note trill). Golden 108.
- **Shape-note noteheads** (Phase 5.1): `LayoutSettings.noteheadScheme` draws
  shape noteheads chosen per pitch by its movable-do scale degree in the current
  key — `NoteheadScheme.sacredHarp` (four-shape: fa = triangle, sol = round,
  la = square, mi = diamond; golden 105) and `NoteheadScheme.aikin` (seven-shape:
  do = triangle-up, re = moon, mi = diamond, fa = triangle, sol = round,
  la = square, ti = rounded-triangle; golden 106). The shapes shift with the key
  signature (its relative minor shares them); an explicit `NoteheadShape` still
  wins. Exposed on the Flutter view as `StaffView.noteheadScheme`.
- **ABC robustness — unequal voices are padded, not fatal**: a multi-voice ABC
  tune whose voices have different bar counts (an imperfect encoding) no longer
  crashes `layoutStaffSystem`; `staffSystemFromAbc` pads the short voices with
  trailing full-measure rests so the system still aligns and renders. Backed by
  a new end-to-end `abc_pipeline_test.dart` that drives real tunes through
  parse → single/multi-staff layout (cross-staff gridding) → MusicXML/MEI/kern
  round-trips → SVG, and asserts the two hands align at shared beats (including
  rest-vs-note, accidental-aware and pickup cases).
- **Reusable OMR library** (CLI): the OMR pipeline (CrispEmbed FFI engine + image
  decode/segmentation + model download + the pure-Dart parsers) is exposed as
  `package:crisp_notation_cli/omr.dart`, so any Dart program — the CLI and Flutter
  **desktop** (wherever `dart:ffi` works) — can drive OMR, not just the CLI. Web
  stays out of reach (no `dart:ffi` on web).
- **Additive-aware & compound beam grouping** (Phase 5.7): `TimeSignature`
  gains `beamGroups()` — the metric beam-group lengths per measure (an additive
  meter's `components`; a compound 8th/16th meter grouped in threes; otherwise
  one group per beat) — and the beam engine now groups notes by them. So 6/8,
  9/8 and 12/8 beam in threes (they previously fell back to flags) and 3+2/8
  beams by its components. Simple meters are unchanged. Golden 104 (6/8); golden
  85 re-rendered with additive beaming.
- **Palm-mute / let-ring / vibrato on the notation staff** (Phase 5.6): the
  existing `PalmMute` and `LetRing` spans now draw a "P.M."/"let ring" label
  followed by a dashed bracket (with a downward end hook) above the notation
  staff, and `Vibrato` draws a wavy line above the note — previously these
  rendered on the tab staff only. Golden 103.
- **Tick / short / reverse-final barlines** (Phase 5.6): three new
  `BarlineStyle`s — `tick` (a short stroke crossing only the top staff line),
  `short` (spanning the middle staff lines), and `reverseFinal` (thick+thin, the
  mirror of a final barline). Round-trip through MusicXML `<bar-style>`
  (`tick`/`short`/`heavy-light`). Golden 102.
- **OMR full-page / multi-system** (CLI): `crisp_notation omr --page` splits a
  full-page scan into staff systems (`segmentStaffSystems`, a pure-Dart
  horizontal-projection band splitter) and recognizes each, concatenating them
  into one score — so a scan with several lines of music transcribes end to end,
  not just one crop.
- **Lyric elision (synalepha)** (Phase 5.4): `Lyric.elidesToNext` marks two
  syllables sung on one note; the layout draws an undertie (‿) bridging them and
  MusicXML round-trips them as one `<lyric>` with `<elision>`-separated `<text>`
  runs (split back into per-syllable `Lyric`s on read). Golden 101.
- **Laissez-vibrer ("let ring") ties** (Phase 5.6): `LaissezVibrer`, keyed by
  note id on `Score`, draws a short trailing tie curve off each notehead of the
  marked element with no destination note — the ring-on notation for piano,
  harp and mallet percussion. Placed opposite the stem like an ordinary tie, or
  forced to a side via `down`. Round-trips through MusicXML
  `<tied type="let-ring">` (with over/under orientation). Golden 100.
- **OMR model auto-download** (CLI): `crisp_notation omr --model <name>`
  (`smt-grandstaff` / `tromr` / `flova`) fetches the GGUF from Hugging Face to a
  cache and reuses it, so no OMR engine needs a manually-supplied model path.
- **Figured bass: slashed figures & continuation lines** (Phase 5.3): a trailing
  `\` on a figure (e.g. `6\`) draws the SMuFL raised-digit glyph (a slash through
  the number — the engraver's alternative to a prefixed sharp), using the
  dedicated glyph for 2/4/5/6/7/9 and `figbassCombiningRaising` otherwise. A
  `'_'` figure row draws a horizontal continuation (extension) line reaching the
  next figured-bass column. Both round-trip through MusicXML — slash as
  `<suffix>slash</suffix>`, continuation as an extend-only `<figure>`. Golden 99.
- **Jazz articulations completed** (Phase 5.9): `JazzArticulation` gains `lift`,
  `flip`, `smear`, and `bend`, drawing the SMuFL brass glyphs U+E5D1/E5E1/E5E2/
  E5E3. `JazzArticulation.rises` picks above/below placement per mark. These four
  are render-only (not standard MusicXML `<articulations>`); scoop/doit/fall/plop
  still round-trip. Golden 98.
- **Third OMR engine — Flova (handwritten)** (v0.8): `scoreFromLilyNotes`
  (`src/omr/lilynotes.dart`) parses CrispEmbed's Flova/omr_transformer output —
  a monophonic LilyPond "simple notes" string (`c'2 a''8 r4 …`) from handwritten
  / whiteboard staff images — into an unmetered single-staff `Score`.
  `omrDialectOf` auto-detects it as a third dialect, so `crisp_notation omr` now
  routes all three CrispEmbed engines (SMT → grand staff, TrOMR → polyphonic
  staff, Flova → handwritten) through one command. Verified live end-to-end.
- **Tab ornaments, articulations & rasgueado** (Phase 6.4): the tab engine now
  draws ornaments (trill/mordent/turn) and articulations (staccato/accent/
  marcato/tenuto/fermata) above the fret by **reusing** `NoteElement.ornament`
  and `.articulations` (no new model — the same data the notation engine uses),
  plus a new `Rasgueado` mark (a downward strum arrow). Golden 97.
- **MuseScore slurs** (interchange enrichment): `Slur` now round-trips through
  MuseScore's location-based `<Spanner type="Slur">` (`<next>` on the start
  chord, `<prev>` on the end), paired positionally on read. This closes the last
  codec gap — `Slur` and `TupletSpan` now round-trip through every codec that
  carries the notes (MusicXML, kern, MEI, MuseScore) plus LilyPond/ABC export.
- **More tab techniques** (Phase 6.4): right-hand p-i-m-a fingering
  (`TabFingering` + `RightHandFinger`, drawn as the letter below the fret),
  slap/pop (`SlapPop` — "S"/"P" above), and tremolo picking (`TremoloPicking` —
  stacked slashes). Each is a `Score` list keyed by note id, rendered by the tab
  engine (ignored by standard notation). Golden 96.
- **Figured-bass realization** (Phase 4.6): `figuredChordPitchClasses(bass,
  figure, key)` reads a figure (`6`, `6/4`, `7`, `#`… — stacked single digits,
  per-degree accidentals, a lone accidental → the third) into the chord's pitch
  classes; `realizeFiguredBass(pairs, key)` completes it to four-part SATB,
  choosing each chord's voicing to minimise `Σ|motion| + 100·(voice-leading
  errors)` — graded by the Phase 4.2 `checkVoiceLeading` engine, so common tones
  are held and parallels avoided. Pure theory. Completes Phase 4 (theory moat).
- **Tuplets in more codecs** (interchange enrichment): `TupletSpan` now
  round-trips through MEI (`<tuplet num numbase>`) and MuseScore
  (`<Tuplet>`/`<endTuplet>`), and exports to LilyPond (`\tuplet a/n { … }`).
  Previously tuplets were carried only by MusicXML and Humdrum `**kern`.
- **Theory extras** (Phase 4.8): neo-Riemannian `parallel`/`relative`/
  `leittonwechsel` (P/L/R) transforms on major/minor `Triad`s; twelve-tone row
  forms (`transposeRow`/`retrograde`/`invertRow`/`retrogradeInversion`) and the
  12×12 `twelveToneMatrix`; and `matchingScales(pcs)` — the scales whose content
  fits a pitch-class set, ranked (rooted-in-the-set first, then major, then
  tonic). Pure theory.
- **Post-tonal set theory** (Phase 4.5): `normalForm`, Forte `primeForm`,
  `intervalClassVector` and `zRelated` for a pitch-class set (0–11), plus
  `transposeSet`/`invertSet`/`pitchClassSet` helpers — the analysis toolkit for
  atonal music. Pure theory. (The Forte set-class *number* is a naming table
  over prime forms; the prime form itself is the canonical identifier.)
- **Key finding** (Phase 4.3): Krumhansl-Schmuckler. `findKey(pcWeights)` and
  `keyOf(pitches, {durations})` correlate a pitch-class weight profile against
  the 24 rotated major/minor key profiles and return the best-matching `Key`
  (with a musically sensible tonic spelling); `localKeys(pitches, window)`
  slides that over the melody to track modulation. Pure theory.
- **Slurs in more codecs** (interchange enrichment): `Slur` now round-trips
  through Humdrum `**kern` (`(`/`)` markers) and MEI (`<slur startid endid>`
  control events, re-anchored across the reader's regenerated ids), and exports
  to LilyPond (`(`/`)`). Previously slurs were carried only by MusicXML and ABC.
  *(MuseScore, whose slur is a location-based `<Spanner>`, is the remaining
  follow-up.)*
- **Voice-leading checker** (Phase 4.2): `checkVoiceLeading(chords)` — each chord
  a list of pitches from the top voice down — flags the classic part-writing
  errors: parallel and hidden (direct) perfect fifths/octaves, voice crossing
  (within a chord), voice overlap (between chords) and upper-voice spacing over
  an octave (the bass–tenor gap is exempt). Returns typed `VoiceLeadingIssue`s
  (rule + chord index + the voice pair). Pure theory.
- **Cross-measure beaming** (Phase 1.4): `CrossMeasureBeam(startId, endId)` on
  `Score` beams a run of notes across a barline. The spanned notes are excluded
  from per-measure beaming and their stems deferred; the beam is drawn in a
  post-pass once both measures' x-positions are fixed, so it continues over the
  barline instead of each measure flagging/beaming on its own. Single-system
  only (a beam cannot cross a line break). Fully additive — scores without one
  are unchanged.
- **Cross-staff notes & beaming** (Score-model lacuna, Phase 2.2): a
  `CrossStaffBeam(noteIds)` on `GrandStaff` joins notes written on both staves
  under one beam — the keyboard figure that reaches from the bass staff up into
  the treble. Each note stays on the staff it is written on; the layout engine
  defers the joined notes' stems (a new `deferredStems` argument →
  `ScoreLayout.crossStaffStubs`, reusing the beam-deferral path so no stem/flag
  is drawn), and `layoutGrandStaff` draws the connecting beam between the staves
  where the inter-staff `staffGap` is known — appended to the upper staff's
  layout, so the existing renderer paints it with no view changes. Upper-staff
  notes stem down toward the beam, lower-staff notes stem up. Golden
  `94_cross_staff_beam`; `cross_staff_test.dart`. *Left:* slanted / multi-bar
  (16th) cross-staff beams and a MusicXML `<staff>` round-trip.
- **Fretted-instrument tunings** (Phase 6.5): preset `Tuning`s for DADGAD,
  open-G, 7- and 8-string guitar, 5-string bass, 5-string banjo (reentrant
  high-G drone), ukulele (reentrant high-G) and mandolin, alongside the existing
  standard/drop-D guitar and 4-string bass. The tab engine is already N-line
  generic, so every instrument renders directly with its own line count.
- **Microtonal accidentals** (Phase 5.10): `Pitch.microtone` (an optional
  `MicrotonalAccidental` — half/three-quarter sharp/flat, ±50/±150 cents) draws
  the Stein-Zimmermann quarter-tone glyphs and always shows (a quarter tone is
  never implied by the key signature). `Pitch.centsOffset` exposes the tuning
  for pitch-bend playback; the integer `alter` and MIDI number are unchanged, so
  this is fully additive. The glyphs are remappable for non-Western systems via
  `LayoutSettings.microtonalGlyphs`. **Contract change:** the prior "microtonal
  out" boundary is lifted — quarter-tone notation is in scope (finer
  just-intonation ratios and full non-Western theory remain out).
- **Non-standard key signatures + senza misura** (Score-model lacuna, Phase
  5.7 tail / 5.8): `KeySignature.custom([KeyAccidental(step, alter), …])`
  expresses modal/atonal signatures the circle of fifths cannot — a mixed
  B♭ + F♯, or a non-traditional accidental order. `alterFor`/`alteredSteps`
  drive both the drawn signature (each accidental placed at its own step, with
  mid-score cancellation naturals generalized to custom keys) and
  note-accidental suppression; it round-trips through MusicXML `<key>`
  `<key-step>`/`<key-alter>` pairs. A non-standard signature is left as written
  under transposition — it has no tonic to move (the notes still transpose).
  Senza-misura (unmetered) scores, already `timeSignature: null`, are now locked
  in by a round-trip test. Golden `92_custom_key_signature`.
- **Optical music recognition** (v0.8): `src/omr/` turns a CrispEmbed Sheet
  Music Transformer `bekern` recognition into the score model — `bekernToKern`
  reconstructs Humdrum, and a multi-spine, `**ekern`-aware kern reader
  (`grandStaffFromKern`/`staffSystemFromKern`) yields a `GrandStaff`/`Score`/
  `StaffSystem`. Tuplet reciprocals approximate to their written note value
  instead of throwing. A second engine — **Polyphonic-TrOMR** — is supported via
  `scoreFromSemantic` (`src/omr/semantic.dart`), which parses PrIMuS-style
  *semantic* notation (`clef-G2 note-C4_quarter …`, chords via `|`) into a
  single-staff `Score`; `omrDialectOf` auto-detects which dialect an engine
  returned. Recognition itself plugs in via the `OmrEngine` abstraction (FFI
  engine lives in `crisp_notation_cli`, `crisp_notation omr` — engine auto-detected).
  `grandStaffToSvg` renders a two-staff `GrandStaffLayout` (sharing `scoreToSvg`'s
  emitter, so `scoreToSvg` is unchanged), and `crisp_notation omr` can write `.svg`
  directly.
- **Humdrum tuplets** (interchange enrichment): the `**kern` reader now reads
  tuplet reciprocals (`6`/`12`/… — non-power-of-two) as real `TupletSpan`s over
  the written note value, and the writer emits them back (a quarter in a 3:2
  triplet → `6`), so tuplets round-trip through kern instead of being
  approximated away. Uniform tuplets (the common case, incl. optical-recognition
  output) round-trip exactly. Powers of two are unchanged.
- **Roman-numeral analysis** (Phase 4.1, bidirectional): `romanNumeralOf(pitches,
  key)` reads a chord as a `RomanNumeral` — scale degree (with a chromatic
  `b`/`#` prefix for borrowed/Neapolitan chords), quality-driven case plus
  `°`/`ø`/`+` marks, figured-bass inversion figures (`6`, `6/4`, `6/5`, `4/3`,
  `4/2`), the major-seventh `M` (`IM7`), and secondary dominants / leading-tone
  chords (`V7/V`, `vii°7/V`) with the tonicized target rendered in its own
  diatonic case. Minor keys accept the raised 6/7 as diatonic (so `V` and
  `vii°`). `pitchClassesOf(numeral, key)` realizes a numeral back to its pitch
  classes; `RomanNumeral.symbol` renders it.
- **Voices 3–4 per staff — layout** (Score-model lacuna, increment 2): the
  layout engine now engraves two to four voices per staff. The former
  two-voice `_layoutTwoVoiceMeasure` is generalized to N voices
  (`_layoutMultiVoiceMeasure`): odd voices (1, 3) stem up, even voices (2, 4)
  stem down; onsets align in shared columns; rests stagger away from the staff
  centre per voice; a note colliding (a second/unison) with a higher voice
  already placed in the column shifts rightward; and when every note in a column
  clears the others, their accidentals share one column block. The `Score.simple`
  DSL now accepts up to four `;`-separated voices. New goldens `90_three_voices`
  and `91_four_voices`.
- **Voices 3–4 per staff — representability** (Score-model lacuna, increment 1):
  `Measure` gains `voice3`/`voice4` (four voices per staff, the notation
  maximum) plus a `voices` getter. They round-trip through MusicXML (multi-voice
  `<backup>`), MEI (`<layer>`) and MuseScore (`<voice>`), and are covered by
  playback and transposition. Fully additive — a single- or two-voice measure
  is unchanged. *The layout engine still engraves voices 1–2; generalizing it to
  draw 3–4 (with new goldens) is the deep follow-up increment.*
- **Metrical-accent hierarchy** (Phase 4.7): `TimeSignature.beatStrength(pos)`
  gives the accent strength of a metric position, normalized so the downbeat is
  `1.0` and each level down the meter's hierarchy of subdivisions halves it —
  4/4 makes beat 3 `0.5` and beats 2/4 `0.25`, 3/4 makes both weak beats `0.5`,
  6/8 accents the second dotted beat, and additive meters accent each group
  start; off-grid (e.g. triplet) positions score `0.0`. Built on the exact
  `Fraction` grid (`TimeSignature.metricGrid()`), resolved to the 64th note.
- **Beam subdivision at metric points** (Phase 1.4): secondary/tertiary beams
  now break at the quarter-note metric point, so a beam group longer than a
  quarter — a half-note beat in cut time (or any x/2 meter) — keeps one
  continuous primary beam while its secondary beams break at the beat's
  sub-pulse, instead of drawing a single over-long secondary beam. Simple x/4
  meters beam per beat (≤ a quarter), so they are unchanged. Applies to both
  the notation and tablature engines.
- **Structured chord symbols** (Score-model lacuna): a `ChordSymbol` (root
  pitch + `ChordSymbolKind` quality + optional slash bass) on `Score`, replacing
  opaque text for lead-sheet harmony. Because roots are real pitches, chord
  symbols now **transpose** (`Cmaj7` → `Gmaj7` up a fifth) — the old free-text
  annotations never did. Round-trips through MusicXML `<harmony>` (structured
  root/kind/bass); text `annotations` now round-trip via `<direction><words>`,
  cleanly separating chords from rehearsal/expression text. Rendered on the
  shared above-staff row alongside annotations.
- **Appoggiatura grace notes** (Score-model lacuna): `NoteElement.graceStyle`
  distinguishes an **acciaccatura** (slashed stem — the default) from an
  **appoggiatura** (unslashed). The layout engine draws the grace-stem slash
  only for acciaccatura; MusicXML round-trips it via `<grace slash="yes|no">`.
  Existing scores/goldens are unchanged (default = acciaccatura).
- **Extended dynamics vocabulary** (Score-model lacuna): `DynamicLevel` gains
  `ppp/pppp/fff/ffff` and the sforzando family (`sf/sfz/sffz/fz/fp/rf`) on top
  of `pp…ff` — each mapped to a real SMuFL glyph (`dynamicPPP`, `dynamicSforzato`,
  …) and round-tripping through MusicXML/ABC (which name dynamics by element).
  New levels are appended, so the original indices are unchanged.
- **Structured tempo** (Score-model lacuna): a first-class `Tempo` (bpm + beat
  unit + dots) on `Score` (and `Score.simple`), replacing the "text-only /
  playback-arg" gap. Carried through MusicXML (`<metronome>`+`<sound tempo>`),
  MEI (`scoreDef @mm`/`@mm.unit`), MuseScore (`<Tempo>`), Humdrum (`*MM`) and
  LilyPond (`\tempo`). Beat unit + dots round-trip through MusicXML/MEI/LilyPond;
  kern and MuseScore store the quarter-note-per-minute equivalent, so a
  quarter-beat tempo round-trips exactly there. Layout does not draw it yet.
- **Score metadata** (first Score-model lacuna implemented): a new
  `ScoreMetadata` on `Score` — title, composer, lyricist, copyright and
  instrument name — carried through the MusicXML (`<work>`/`<identification>`),
  MEI (`<meiHead>`), MuseScore (`<metaTag>`/`<trackName>`), Humdrum (`!!!` OTL/
  COM/… records + `*I"`) and LilyPond (`\header`) headers. `Score.simple` gains
  a `metadata:` argument; empty metadata (the default) round-trips as empty
  (mandatory header fields like a part name are sentinel-nulled). Layout ignores
  it. See PLAN.md for the model-lacuna backlog this begins.
- **Interchange enrichment — articulations & ornaments** (Phase 7.3): the MEI,
  MuseScore and Humdrum `**kern` codecs now round-trip **articulations**
  (staccato/tenuto/accent/marcato/fermata + up/down-bow) and **ornaments**
  (trill/short-trill/mordent/turn), and LilyPond export emits both — closing
  that gap with the MusicXML reference. MEI ornaments use `<trill>`/`<mordent>`/
  `<turn>` control events anchored by `xml:id`; MuseScore and kern attach them
  per note. See PLAN.md "Interchange parity & Score-model lacunae" for the full
  coverage matrix, enrichment backlog and the model lacunae.
- **Humdrum `**kern` import & export** (Phase 7.3): `scoreToKern` /
  `scoreFromKern` write and read a single-spine `**kern` document — the open,
  documented representation used in computational musicology (spec is public;
  no toolkit code used). A **subset** (clef with mid-score changes, key/time
  incl. common/cut and additive, measures, notes/chords, rests, durations
  breve…64th + dots, ties), pure Dart. Enharmonic spelling and (natural)
  courtesy accidentals round-trip; pickup is detected from a short first bar.
  Two voices, slurs, tuplets and lyrics are out of scope.
- **LilyPond (`.ly`) export** (Phase 7.3): `scoreToLilyPond` emits a `.ly`
  source for the LilyPond engraver (best-in-class output). **Export only** — its
  input is a full language — generated from the documented syntax (no LilyPond
  code used), pure Dart. Covers clef (with changes), key/time, notes/chords,
  rests, durations breve…64th + dots, two voices (`<< \\ >>`), ties and pickup
  (`\partial`). Dutch note names; 4/4 · 2/2 render as C · cut-C by default.
- **MEI (Music Encoding Initiative) import & export** (Phase 7.3): `scoreToMei`
  / `scoreFromMei` write and read an `<mei>` (v5) document — the open,
  standards-body notation XML used across digital musicology (Verovio,
  music21). A **subset** codec (clef with mid-score changes as inline
  `<clef>`/`<keySig>`/`<meterSig>`, key/time signatures incl. **common/cut and
  additive**, measures, notes/chords, rests, durations breve…64th + dots, two
  voices/layers, ties, pickup via `@metcon`), pure Dart (web-safe). Pitch
  spelling round-trips through gestural accidentals (`@accid.ges`), so C♯ stays
  C♯. Slurs, tuplets, articulations, lyrics and dynamics are out of scope.
- **Compressed MusicXML (`.mxl`) import & export** (Phase 7.3): `.mxl` — the
  zipped MusicXML that Sibelius, Finale, Dorico and MuseScore all read and write
  — pairs the existing MusicXML codec with the new web-safe ZIP.
  `writeMusicXmlToMxl` / `readMusicXmlFromMxl` (the latter follows the
  `META-INF/container.xml` rootfile, falling back to the first non-`META-INF`
  `.xml`); the CLI gains `.mxl` in+out. A shared `zip.dart` (`zipArchive` /
  `readZipEntry`) now backs the container codecs. Round-trips through the shared
  `Score`; verified in the WASM smoke too.
- **Pure-Dart DEFLATE encoder**: `deflate` (RFC 1951 — greedy LZ77 over a 32 KB
  hash-chain window + fixed Huffman) completes the compression pair with
  `inflate`. The `.gp`/`.mscz` ZIP writers now emit **compressed** (method-8)
  entries instead of stored, so written archives are smaller — with no
  `dart:io`, so it works in the browser / WASM too. Validated against `dart:io`'s
  `ZLibDecoder` (its output is standard DEFLATE) and via a randomised
  deflate→inflate sweep.
- **Web-safe interchange containers** (pure-Dart DEFLATE): a from-scratch
  `inflate` (RFC 1951 — stored / fixed / dynamic Huffman) replaces `dart:io`'s
  `ZLibDecoder`, so the `.gp`/`.gpx`/`.mscz` ZIP + BCFS container reading no
  longer needs `dart:io`. The `gp_container` / `mscz_container` codecs moved
  from `crisp_notation_cli` into web-safe `crisp_notation_core`
  (`readGpifFromGp`/`readGpifFromGpx`/`writeGpFromGpif`, `readMscxFromMscz`/
  `writeMsczFromMscx`), so **reading real compressed `.gp`/`.mscz` files now
  works in the browser / WASM**, not just the CLI. `inflate` is validated
  against `dart:io`'s encoder and the real alphaTab/MuseScore fixtures; the WASM
  smoke inflates a DEFLATE stream and round-trips a `.mscz` under Node.
- **WebAssembly target**: `crisp_notation_core` compiles to and runs as a WasmGC
  module via `dart compile wasm` (dart2wasm) — it uses no
  `dart:io`/`dart:html`/`dart:ffi`/`dart:isolate` (only `dart:typed_data`), so
  the theory, layout and text-interchange codecs run in the browser or any WASM
  host. Added [`example/wasm/`](example/wasm/): an asset-free smoke entry
  (`wasm_smoke.dart`) verified both on the VM and as WASM under Node, a browser
  `dart:js_interop` demo (`main.dart` + `index.html` exposing
  `crisp_notationConvert`/`crisp_notationInfo`), a `build.sh` and a Node runner. The
  `dart:io`-based `.gp`/`.gpx`/`.mscz` container unwrapping stays in
  `crisp_notation_cli`; the `.mscx`/`.gpif` XML payloads are web-safe.
- **MuseScore (`.mscx` / `.mscz`) import & export** (Phase 7.3): `scoreToMscx`
  / `scoreFromMscx` write and read a MuseScore-4 `.mscx` document — a **subset**
  codec (clef with mid-score changes, key/time signatures, measures,
  notes/chords, rests, durations breve…64th + dots, two voices, ties, pickup
  measures), pure Dart (web-safe). Spelling round-trips via the MuseScore
  tonal-pitch-class (`tpcOf`), so C♯ stays C♯. The `.mscz` ZIP container is
  handled in `crisp_notation_cli` (`readMscxFromMscz` / `writeMsczFromMscx`, needs
  `dart:io`), which also gains `.mscx`/`.mscz` input+output. Common/cut meters
  degrade to numeric on this hop; slurs, tuplets, articulations, lyrics and
  dynamics are out of scope. The reader also accepts the shapes real MuseScore
  3/4 files use (`KeySig` as `concertKey`/`accidental`/`subtype`, whole-measure
  `durationType>measure` rests). Because every codec funnels through the one
  `Score`, `.mscx` round-trips transparently with MusicXML, MIDI, ABC and the
  `.gp` line for the data they share.
- **Per-column skyline collision avoidance** (Phase 1.2): the layout engine
  records every glyph's ink and exposes `_skylineTop`/`_skylineBottom` queries,
  so above-/below-staff marks clear only the ink in their own horizontal span
  instead of the whole system's extremes. Applied to text annotations (golden
  86), figured bass, lyrics, navigation marks and chord diagrams — each now hugs
  its own span rather than being pushed by a distant high/low note. **Slurs**
  arch above the full local skyline (interior articulations/accidentals/other
  marks), not just the spanned noteheads. Because the passes run in order
  (notes → ties → slurs → … → annotations/lyrics), each later mark clears the
  earlier ink. **Cross-voice accidentals** in a shared two-voice column are now
  laid out jointly — both voices' accidentals share one zig-zag column block and
  the noteheads align, so they never overlap (golden 88).
- **Extra clefs** (Phase 5.2): the neutral **percussion** clef
  (`Clef.percussion` → `unpitchedPercussionClef1`, no key signature; MusicXML
  `<sign>percussion</sign>` and ABC `clef=perc`, header and per-voice; golden
  83), plus the **French violin / soprano / mezzo-soprano / baritone /
  sub-bass** C- and F-clef positions (golden 84). Each has a correct bottom-line
  pitch reference and on-staff key signatures — for clefs without a hand-tuned
  accidental table, positions are derived by the standard fifth-stacking rule
  (each accidental a fifth from the last, dropping an octave to stay on the
  staff). All round-trip through MusicXML `<clef>` (sign + line).
- **Common / cut time symbols + additive meters** (Phase 5.7): `TimeSymbol`
  (numeric/common/cut) on `TimeSignature`, with `TimeSignature.commonTime` (4/4
  drawn as C) and `cutTime` (2/2 drawn as ¢) from the SMuFL `timeSigCommon`/
  `timeSigCutCommon` glyphs (golden 82). `TimeSignature.additive([3, 2], 8)`
  models a composite meter, drawn `3+2` over `8` with the `timeSigPlus` glyph
  (golden 85). All round-trip through MusicXML `<time>` (`symbol=` /
  `<beats>3+2</beats>`) and ABC `M:` (`M:C`, `M:C|`, `M:3+2/8`, `M:(2+2+3)/8`).
- **Pagination / page layout** (Phase 2.5): `layoutPages` groups the
  line-broken systems into pages of a `PageMetrics` box (page size + margins,
  in staff spaces), packing systems by content height and vertically justifying
  every page except the last (page-fill; extra space shared between systems).
  The Flutter `ScorePageView` renders a single page at its exact aspect ratio
  with margins and an optional page frame (golden 81).
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
  Flutter painter already colored elements via `CrispNotationTheme.elementColors`;
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
  63). The .gp3/.gp4/.gp5 binary readers classify the harmonic-type byte, and GPIF
  read+write carry `HarmonicType` (Natural/Artificial/Pinch), so the type
  survives a `.gp` round-trip. Confirmed on the alphaTab corpora
  (`harmonic-types.gp4`: 3 natural / 3 artificial / 1 pinch; `.gp4` and `.gp5` agree).
- **`.gp` binary import — more note effects** (Phase 7.3): the `.gp3`/`.gp4`/`.gp5`
  binary readers now surface **vibrato** (`Vibrato`; note-level in `.gp4`/`.gp5`,
  beat-level "wide" in `.gp3` and `.gp5`), and **palm mute** / **let ring**
  (per-note flags coalesced into `PalmMute` / `LetRing` bracket spans that a
  rest closes). They already rendered in the tab engine; the readers just
  weren't feeding them. Confirmed against the real alphaTab corpora, where all
  three versions agree (`vibrato.*`, `effects.*` fixtures) — except `.gp3`, which
  has no note-level palm mute.
- **`.gp3`/`.gp4` import** (Phase 7.3):
  `gp3ToScore` / `gp4ToScore` extend the `.gp5` binary reader with the older
  layout — one voice per measure, no RSE/page-setup, `.gp3`'s beat-level
  harmonics, and the narrower beat/note effect flags. Same technique coverage
  (HO/PO, slides, bends, dead, harmonic). Committed regression tests parse the
  real alphaTab `.gp3`/`.gp4` corpora and confirm the versions agree note-for-note
  (`gp_fixtures_test.dart`). The reader now lives in `gp_binary_reader.dart`.
- **`.gp5` import** (Phase 7.3): `gp5ToScore(bytes, {trackIndex})`
  — a from-scratch byte/bit-exact reader for the `.gp5` *binary* format (ported
  from PyGuitarPro's layout): measures, time signatures, per-track tunings,
  notes as string+fret → pitch, and the note techniques (HO/PO, slides, bends,
  dead, harmonic). Pure Dart. Validated against the alphaTab `.gp5` corpus —
  `chords.gp5` renders identically to `chords.gp` (v7). Wired into the CLI.
- **`.gp` technique import** (Phase 7.3): `scoreFromGpif` now reads the
  common GPIF playing techniques into crisp_notation's tab marks — hammer-on/
  pull-off → slur, slide → glissando, bend (with amount) → `Bend`, whammy
  vibrato → `Vibrato`, dead → `TabNoteMark.dead`, harmonic →
  `TabNoteMark.harmonic`. Validated against the alphaTab `.gp` (v7) corpus (e.g.
  `bends.gp` renders correct "full"/"1½" bend arrows).
- **Tab chord voicing** (fix): `TabLayoutEngine` now assigns each chord tone to
  a **distinct string** (higher pitches to higher strings, lowest fret first)
  instead of placing every pitch at its independent lowest fret — so two notes
  of a chord no longer collide on one line (visible on dense real `.gp`
  chords). Pinned `TabVoicing`s still win; hand-designed goldens are unchanged.
- **GPIF (`.gp`) import/export** (Phase 7.3): `scoreFromGpif` /
  `scoreToGpif` read and write the `score.gpif` XML of the `.gpx`/`.gp` (v6/7/8)
  formats — a subset (tuning, bars → voices → beats → string+fret notes,
  rhythms; single track/voice), pure Dart. Pitches and rhythm round-trip. The
  `.gp` ZIP container is handled in `crisp_notation_cli` (needs `dart:io`), which
  also gains `.gp`/`.gpif` input+output. Because every codec funnels through
  the one `Score` model, formats round-trip transparently for the data they
  share (see `interchange_transparency_test.dart`). Validated against real
  files: the GPIF reader reads the alphaTab .gp (v7) test corpus (incl. a 96-bar
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
  Wired into `crisp_notation_cli` (`.tab`/`.crd`/`.txt`; `--infer-rhythm`).
- **SVG export** (Phase 7.2): `scoreToSvg(layout, {…})` renders a
  `ScoreLayout` to a standalone SVG document (works for both notation and
  tablature); optional `@font-face` embedding of the engraving font. The
  `smuflCodepoints` glyph-name→character table moved into `crisp_notation_core`
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
