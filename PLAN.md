# partitura — roadmap & living tracker

partitura's north star: **match, then surpass, the capabilities of mature
interactive notation renderers and professional engraving software** — while
keeping its own edge and its boundary.

- **Edge (defend it):** first-class interactivity (every element
  hit-testable, selectable, draggable, highlightable), a pure-Dart
  deterministic layout engine testable without a renderer, a pedagogy-shaped
  music-theory core, and a repaint-only highlight pipeline.
- **Boundary (permanent):** partitura renders and supplies a timing map; it
  never synthesizes audio. Apps bring their own synth.

This is the single planning document: what has shipped, and the prioritized
sequence of everything still to build. **Every item ships the full
pipeline** — model + layout + unit tests in `partitura_core`; painting +
goldens + interaction tests in `partitura`; a gallery entry where visual;
CONTRACT/CHANGELOG updates; all gates green (`dart format`, analyze with zero
issues, all tests) — and lands as its own commit. See *How each feature
ships* at the end for the mechanics.

---

## Status (2026-07-11)

- **Shipped: v0.1 → v0.7.2** — the full common-notation set plus the
  piano/technical layer. All green.
- **In progress (partial):**
  - **Phase 1.4 (advanced beaming):** feathered beams (`FeatheredBeam`,
    golden 50), forced beam slant (`BeamSlant`, golden 51) and **beams over
    rests** (golden 64) done. Left: beam subdivision, cross-measure.
  - **Phase 6 (guitar tablature)** — *pulled forward on request.* Done:
    `Tuning` + `fretFor`; `TabLayoutEngine` + `TabStaffView` (N-line staff,
    TAB clef, fret numbers, broken lines, barlines); rhythm (stems/flags/
    per-beat beams); techniques so far — slides (reuse `glissandos`),
    hammer-on/pull-off (reuse `slurs`), string bends (`Bend`), vibrato
    (`Vibrato`), palm mute / let ring (`PalmMute`/`LetRing`), dead / ghost
    notes, natural + **artificial + pinch** harmonics (`TabNoteMark` /
    `TabNoteStyle`), tapping (`Tap`), tremolo bar (`TremoloBar`), chord
    diagrams (`ChordDiagram`/`PlacedChordDiagram`). Goldens 52–63. Contract
    "tablature out" clause lifted.
  - **Phase 7.3/7.4 (interchange):** MusicXML, MIDI, GPIF and the full Guitar
    Pro binary line (GP3/4/5) + GP6 `.gpx` + GP7/8 `.gp` all import, with the
    common techniques; nested repeats now expand in `playbackTimeline`.
- **Test counts:** 701 core + 141 widget + 39 CLI, all gates green.

### ▶ Where the next agent picks up

Remaining, roughly by leverage:

1. **More tab techniques** (Phase 6.4 tail) — tremolo picking, grace notes,
   trill, staccato/accent, slap/pop (bass), p-i-m-a fingering, rasgueado.
   Model each like `Bend` (a `Score.<list>` keyed by note id, rendered in
   `TabLayoutEngine`) or reuse an existing span. The GP binary/GPIF readers
   already parse most of these bytes — wire them through as you add each mark.
   Tab code: `theory/tuning.dart`, `layout/tab_layout.dart`,
   `rendering/tab_staff_view.dart`.
2. **Resume the Phase sequence** at Phase 1.4's remainder (beam subdivision,
   cross-measure beams), then Phase 2 (structure / N-staff — also unblocks
   tab-paired-with-notation, Phase 6.3), Phase 3 (interaction moat), Phase 4
   (theory moat), Phase 5 (breadth).
3. **Interchange tail** — `.ptb` (PowerTab) is blocked on a freely-licensed
   test corpus; Braille export (7.5) is the last unstarted 7.x item.

**Note — a correction the next agent should trust:** Phase 1.1 "optical
spacing" is **already implemented** (`layout_engine.dart` `_advance` spaces
by duration-log2 with a justification stretch). The real Phase-1 gaps are
1.2 skyline collision avoidance and 1.3 pluggable fonts (needs a ~1MB second
font asset added — get owner OK).

Owner conventions (see also the session memory): **one planning doc
(`PLAN.md`), no competitor product names in committed docs.** Each feature
ships the full pipeline (see *How each feature ships* at the end).

---

## Shipped — v0.1 → v0.7

### v0.1–v0.2 — foundations
Theory core (pitch, duration, key/time signatures, interval, scale, triad,
harmonic function); deterministic layout engine; `StaffView`;
`InteractiveStaff` (hit-testing, selection, drag-to-staff, ghost notes);
clefs treble, bass, alto, tenor.

### v0.3 — notation depth
Ties; slurs; tuplets; articulations (staccato, tenuto, accent, marcato,
fermata); dynamics (pp–ff) + hairpins; grace notes; 32nd/64th + breve
durations; mid-score clef/key/time changes; repeat barlines; voltas.

### v0.4 — structure
Two voices per staff; grand staff (2); line breaking + justification; lyrics
(one verse); chord symbols / text annotations (also rehearsal + tempo text).

### v0.5 — interchange & time
MusicXML import + export (round-trip tested); playback-cursor API
(`playbackTimeline` — no audio); `Score.transposedBy(interval)`.

### v0.6 — engraving polish
Accidental stacking for dense chords; ornaments (trill, short trill, mordent,
turn); multi-measure rests; octave clefs (8va/8vb) + ottava brackets.

### v0.7 — long-tail parity
- **0.7.1 Navigation marks** — segno, coda, To Coda, D.C., D.S., D.C./D.S. al
  Fine, D.C./D.S. al Coda, Fine (shared-baseline above the staff; MusicXML
  round-trip). *Playback jump execution now implemented in `playbackTimeline`
  (see Phase 7.4).*
- **0.7.2 Piano / technical layer** — fingerings, arpeggio, glissando,
  tremolo, sustain pedal.

---

## Distance to industry-standard level

partitura's category is a **rendering + model library**, not a WYSIWYG editor,
so parity is measured against serious interactive renderers and against
professional *engraving* quality — not against note-entry apps. Note-entry /
editing and audio synthesis are deliberately **out of category** (the latter a
permanent contract boundary; apps bring their own synth and get a timing map).

Already at or near that bar: core common-notation engraving (noteheads, stems,
flags, accidentals, ties, tuplets, grace notes, articulations, ornaments,
dynamics + hairpins, tremolo, and beaming incl. feathered / forced-slant /
over-rests), repeat & navigation semantics (repeats, voltas, D.C./D.S./coda,
nested repeats), a broad interchange surface (MusicXML, MIDI, the full Guitar
Pro 3–8 line), and the category-unusual extras — a renderer-free deterministic
layout engine, hit-testing, a highlight/timing pipeline, SVG/PNG export, a CLI.

The remaining distance falls in three buckets:

- **Table-stakes gaps** (credibility for real, published scores) — in priority
  order: **(1.2) full-system skyline collision avoidance**, including
  collision-aware slur/tie shaping — the single biggest visual lever and the
  most invasive; **(2.5) a page-layout engine** (pages, margins, vertical
  justification, frames, breaks — today only *system* line-breaking exists);
  **(2.1) N-staff / ensemble systems** with brackets/braces (today capped at a
  grand staff); **(2.6) transposing instruments + concert-pitch + parts
  extraction**; **(2.4) pickup/anacrusis + irregular measures**; and the
  Phase-5 breadth staples (voices 3–4, lyric verses/melisma/hyphenation,
  figured bass, extra clefs, more noteheads, microtonal, additive meters).
  Deeper MusicXML fidelity for arbitrary published files also lives here.
- **Differentiators** (where partitura aims to *exceed*, not match — peers do
  none of these): the **Phase 3** interactivity moat (cursor-synced piano /
  fretboard visualizers, overlays, looping, played-vs-expected, accessibility)
  and the **Phase 4** theory/analysis moat (Roman numerals, voice-leading,
  key finding, chord ID, set theory). High value, but they read as polish
  until the engraving/structure foundation itself looks professional.
- **Out of category / boundary** — WYSIWYG editing (this is a library) and
  audio synthesis (permanent boundary).

Net: content *breadth* and *interchange* are already strong for the category;
the gap to "professional" concentrates in **engraving collision quality (1.2)**
and **score structure / page layout (Phase 2)**, with Phase 5 breadth close
behind. The phase ordering below reflects exactly this.

## Planned — beyond parity

Prioritized top-to-bottom; we implement them **one phase at a time**, and each
phase is several full-pipeline slices. (Ordering reflects value-to-identity ÷
effort plus technical dependencies. Tablature — previously slated as the
immediate next milestone — is sequenced at Phase 6 because it depends on the
N-line-staff generalization delivered in Phase 2 and because the Phase 1–2
foundations lift its quality too. It can be pulled forward on request.)

### Phase 1 — Engraving quality  *(the biggest visual lever)*
Raises the quality of everything already rendered. Slice order:
**1.4 → 1.2 → 1.3.**
- [x] **1.1 Optical horizontal spacing** — **already present**: `_advance`
      spaces by duration on a log2 scale (`spacingBase + spacingPerLog2 ·
      (4 + log2(duration))`), with a `minNoteGap` ink floor and a
      justification `spacingStretch`. Possible later refinement: optical
      corrections (e.g. accidental-to-note, tighter grace spacing) — but the
      core springs-and-rods model exists.
- [ ] **1.2 Skyline collision avoidance** — the real engraving-quality gap.
      Give every glyph a skyline outline; place accidentals, articulations,
      dynamics, lyrics, slurs and above/below-staff marks to avoid overlap
      across the whole system. Today, above/below marks clear the global ink
      minima but do not skyline against each other per-column. The most
      invasive item in this phase (touches many placement passes).
- [ ] **1.3 Pluggable SMuFL fonts** — bundle and switch between multiple
      engraving fonts (a clean serif default, a jazz/handwritten face, etc.),
      reading engraving metrics (line thicknesses) from each font's metadata.
      The glyph-name abstraction already exists, so this is largely asset +
      config + a font-metrics loader.
- [~] **1.4 Advanced beaming** — feathered/fanned beams (accel./rall.), beam
      subdivision at metric points, custom slope / independent beam-end
      heights, beams over rests, cross-measure beaming. (Cross-staff beaming
      lands with Phase 2.) **Done:** feathered beams (`FeatheredBeam`; golden
      50), forced beam slant / force-horizontal (`BeamSlant`; golden 51),
      beams over rests (a rest inside a beat no longer breaks the beam; golden
      64). **Left:** beam subdivision, cross-measure.

### Phase 2 — Score structure (multi-staff)
- [ ] **2.1 N-staff systems** — generalize the grand staff from 2 → N staves,
      with nested brackets/braces and barline grouping. Also generalizes the
      engine's hard-coded 5-line staff assumption (parameterize line count +
      spacing), which Phase 6 (tablature) depends on.
- [ ] **2.2 Cross-staff notes / stems / beams** — a chord or beam spanning
      both staves of a keyboard system.
- [ ] **2.3 Hide-empty / ossia / divisi / cutaway staves** — dynamic staff
      count: drop empty staves per system, add temporary alternative (ossia)
      staves, split a part into subsections, remove empty bars.
- [ ] **2.4 Pickup / anacrusis + actual-vs-nominal measure duration +
      irregular measures** — foundational; a large fraction of real pieces
      need a partial first bar or a metric length differing from the notated
      one.
- [ ] **2.5 Page-layout engine** — page size/margins, a spatium scaling unit,
      vertical justification (staff/system distances, page-fill), explicit
      page/section breaks, spacers, and frames (title/text/spacer blocks).
- [ ] **2.6 Linked parts + transposing instruments + concert-pitch toggle.**
- [ ] **2.7 Measure-numbering system** (per-system/interval, per-measure
      overrides, section reset) + measure-repeat signs (1/2/4-bar).

### Phase 3 — Interactivity  *(the moat — where partitura wins)*
Rides the existing cursor + selection; no audio needed.
- [ ] **3.1 Cursor-synced instrument visualizers** — a piano keyboard (L/R
      hand) and a guitar fretboard that light up as the playback cursor
      advances. The single highest-differentiation feature; pairs directly
      with the no-audio timing map.
- [ ] **3.2 Note-name & rhythm-count overlays** — letter name above the
      notehead, beat number above the note. Cheap, ubiquitous in education.
- [ ] **3.3 Drag-to-loop + section looping** — select a passage that snaps to
      note/rest/barline; the practice primitive for slowdown/looping apps.
- [ ] **3.4 Error / annotation overlay** — paint specific notes as
      correct/wrong/flagged so assessment and ear-training apps supply their
      own analysis and ask partitura to show it.
- [ ] **3.5 Warped-time cursor + external sync points** — extend the cursor
      from a fixed clock to a variable tempo map and app-supplied sync points
      (follow a slowed-down or live-performance timeline).
- [ ] **3.6 Live transposition / concert-pitch UI** — an interaction wrapper
      over the existing `Score.transposedBy`.
- [ ] **3.7 Played-vs-expected MIDI-input highlighting** — power
      play-the-right-note drills (the highlight half; input is the app's).
- [ ] **3.8 Rich imperative control API** — seek-to-note, set-loop,
      overlay-annotations, toggle-part, set-visualizer: the surface apps drive
      the renderer through.
- [ ] **3.9 Accessible & sonified navigable score** — Flutter `Semantics`
      over the score tree; a genuine gap across interactive players.

### Phase 4 — Music theory & analysis  *(the moat — extends the theory core)*
No peer renderer does any of this; all build on the existing pitch / interval
/ scale / triad / harmonic-function core.
- [ ] **4.1 Roman-numeral analysis (bidirectional)** — infer the numeral +
      inversion + secondary dominants from a chord in a key, and render the
      numeral + figured-bass symbols. Highest pedagogy payoff.
- [ ] **4.2 Part-writing / voice-leading checker** — flag parallel
      fifths/octaves, hidden intervals, voice crossing/overlap, spacing. The
      defining teaching-library feature.
- [ ] **4.3 Key finding** — weighted pitch-class correlation (+ windowed local
      key for modulation).
- [ ] **4.4 Chord identification from a pitch set** — root/inversion/quality,
      seventh and augmented-sixth recognition (the inverse of triad
      construction).
- [ ] **4.5 Post-tonal set theory** — normal order, prime form, set-class
      number, interval-class vector, Z-relation.
- [ ] **4.6 Figured-bass realization** — SATB completion with a voice-leading
      rule engine (pairs with 4.2).
- [ ] **4.7 Metrical-accent hierarchy** (`beatStrength`) on the exact-duration
      core — also improves automatic beaming.
- [ ] **4.8 Extras** — scale derivation (rank matching scales for a pitch
      set), triad L/P/R transforms, twelve-tone matrix, an analysis text I/O
      format.

### Phase 5 — Notation breadth
- [~] **5.1 Noteheads** — **Done:** the shape set (x, diamond, triangle-up,
      slash, circled-x — `NoteheadShape`, duration-aware variants, MusicXML
      `<notehead>` round-trip, golden 66). **Left:** shape-note / pitch-name /
      solfège schemes, cue/small notes, colored + out-of-range coloring.
- [ ] **5.2 Extra clefs** — French violin, soprano/mezzo/baritone/subbass,
      percussion.
- [ ] **5.3 Figured-bass notation** — stacked figures, accidentals, slashes,
      continuation lines (rendering; realization is 4.6).
- [ ] **5.4 Lyrics** — multiple verses, melisma extenders, elision slurs,
      hyphenation.
- [ ] **5.5 Voices 3 & 4** per staff + rest merging.
- [~] **5.6 More barlines & lines** — **Done:** closing-barline styles
      (double / final / heavy / dashed / dotted / none — `BarlineStyle`, MusicXML
      `<bar-style>` round-trip, golden 65). **Left:** tick/short/reverse-final;
      custom-span barlines across staves; laissez-vibrer ties; palm-mute /
      let-ring / vibrato lines (exist in tab; add to notation); trill extension
      line + baroque variants; portamento; system dividers.
- [ ] **5.7 Time-signature breadth** — common/cut symbols, additive/composite
      meters, local per-staff meters.
- [ ] **5.8 Custom / atonal key signatures + cancelling-naturals policy.**
- [ ] **5.9 Jazz articulations** — scoops, falls, doits, plops, flips, smears.
- [ ] **5.10 Microtonal accidentals + remappable alteration glyphs**
      (quarter tones; non-Western systems). *Requires lifting the current
      "microtonal out" clause — a conscious contract change.*

### Phase 6 — Guitar tablature (full techniques)
A parallel notation mode. Depends on Phase 2.1 (N-line staff generalization —
the engine's `y = (8 − staffPosition)/2` and pitch-based staff positioning
assume exactly 5 lines; tab needs an N-line staff where each line is a
*string* and the mark is a *fret number*). Needs a new `Tuning` model and a
pitch → (string, fret) assignment. Also requires lifting the current
"tablature out" clause in the contract.

- [x] **6.1 Design + contract amendment** — `Tuning` (open-string pitches +
      `fretFor` lowest-fret assignment; guitar/dropD/bass presets), N-line
      staff, TAB clef; contract "tablature out" clause lifted. (Pulled forward
      on request, 2026-07-11.)
- [x] **6.2 Core tab staff** — N-line string staff, TAB clef, fret numbers
      with broken lines, barlines, `TabStaffView` (golden 52); rhythm
      stems/beams below the staff; per-note string override
      (`Score.tabVoicings` — `TabVoicing(noteId, strings)`); capo + tuning
      labels (golden 60).
- [ ] **6.3 Tab paired with a notation staff** (rides on Phase 2.1).
- [~] **6.4 Techniques** — the full set below. **Done:** rhythm stems/flags/
      beams below the staff; slides (reuse `glissandos`) and hammer-on/pull-off
      arcs (reuse `slurs`) — goldens 53, 54; string bends (`Bend`) — golden 55;
      vibrato (`Vibrato`, normal + wide) — golden 56; palm mute / let ring
      (`PalmMute`/`LetRing`, dashed brackets) — golden 57; dead / ghost notes
      (`TabNoteMark` — "x" / parenthesized fret) — golden 58; natural harmonics
      (`TabNoteStyle.harmonic` — angle-bracketed fret) — golden 59; chord /
      fretboard diagrams (`ChordDiagram` + `layoutChordDiagram` — grid, dots,
      x·o, barre, base-fret label; `PlacedChordDiagram` places them above the
      notation or tab staff over a note — golden 62); tapping (`Tap` — "T") and
      tremolo-bar (`TremoloBar` — whammy V) — golden 61; artificial + pinch
      harmonics (`TabNoteStyle.artificialHarmonic`/`.pinchHarmonic` — bracketed
      fret + "A.H."/"P.H." label) — golden 63. **Left:** tremolo picking, grace
      notes, trill, staccato/accent, slap/pop, fingering, rasgueado, and the
      rest of the checklist.
- [ ] **6.5 Tunings & other fretted instruments** (bass, drop-D, DADGAD…;
      7/8-string, banjo, ukulele, mandolin).

**Exhaustive technique checklist** (adopt the well-established point-grid /
enum encodings so files round-trip cleanly), tiered by importance:

- *Tier 1 (almost every tab):* hammer-on / pull-off / legato; slide (shift &
  legato); bend + bend-release + prebend (½ / full / 1½); vibrato; palm mute;
  dead/muted note; let ring; chord name + fret diagram.
- *Tier 2 (a "full techniques" release):* slide in/out (below/above,
  out-up/down); multi-point bend curves (quarter-tone point grids);
  natural + artificial + pinch harmonics; tapping (two-hand + left-hand);
  whammy/tremolo-bar with dip/dive/return curves (a system *separate* from
  string bends); wide vibrato; tremolo picking; ghost/accent/staccato; grace
  notes with transition type; trill; slash/rhythm mode; multiple voices;
  left-hand & picking-hand (p-i-m-a) fingering; slap / pop (bass).
- *Tier 3 (completeness):* tapped/semi/feedback harmonics; bend-release-bend &
  prebend-release curves; brush up/down, arpeggio up/down, pick-stroke;
  rasgueado (named strum patterns); golpe; wah open/close; fade-in/out;
  banjo/ukulele/mandolin presets & diagrams; beaming controls.

### Phase 7 — Interchange & export
- [x] **7.1 MIDI file export** — `scoreToMidi` emits a format-0 Standard MIDI
      File off the playback timeline (repeats/jumps unfolded; tempo +
      time-signature meta; voice→channel). Contract-safe (no audio).
- [x] **7.2 Raster + vector export** — SVG (`scoreToSvg`, pure-Dart emitter
      over `ScoreLayout`; notation and tab; optional embedded font) and PNG
      (`renderLayoutToPng` in the `partitura` package, via `dart:ui`). Both
      serve notation and tablature.
- [~] **7.3 Wider import** — additional interchange formats beyond MusicXML.
      **Done:** MIDI import (`scoreFromMidi`); plain-text/ASCII tab import
      (`asciiTabToScore`); Guitar Pro import **and** export (`scoreFromGpif` /
      `scoreToGpif` GPIF subset + the `.gp` ZIP container in `partitura_cli`).
      GP import also reads the common playing techniques (HO/PO, slides, bends,
      vibrato, palm mute, let ring, dead, natural/artificial/pinch harmonic)
      into the tab marks. All formats round-trip transparently through the
      shared `Score` model for the data they share. The full Guitar Pro binary
      line imports via `gp_binary_reader.dart` — GP3 (`.gp3`), GP4 (`.gp4`),
      GP5 (`.gp5`), a from-scratch byte-exact reader — plus GP6 `.gpx`
      (BCFZ/BCFS) and GP7/8 `.gp` (GPIF-in-ZIP), all wired into the CLI and
      regression-tested against real vendored alphaTab fixtures
      (`partitura_cli/test/gp_fixtures_test.dart`; GP3/4/5 agree note-for-note
      on the shared techniques). **Left:** `.ptb` (PowerTab, no freely-licensed
      test corpus).
- [x] **7.4 Repeat unfolding** — `playbackTimeline` linearizes repeats /
      voltas / D.C. / D.S. / To Coda / al Fine / al Coda into performance
      order, executing the navigation jumps. Repeat barlines expand with a
      stack, so **nested** `|: … |: … :| … :|` unfolds correctly (inner
      completes before the outer jumps back); voltas select by the enclosing
      repeat's pass. After a D.C./D.S. return the score plays straight through.
      **Closes the playback jump execution deferred in 0.7.1.** *Left:* a
      repeat-count model field (every `:|` currently repeats once); volta
      brackets that are also inner-repeat starts (ambiguous); repeat
      re-expansion after a D.C./D.S. return.
- [ ] **7.5 Braille music export** — rare in this space; a real accessibility
      differentiator.
- [x] **7.6 CLI tool** (`partitura_cli`) — a pure-Dart command line for
      `info` / `timeline` / `convert` (MusicXML ↔ MIDI) / `render` (SVG or,
      by delegating to the Flutter SDK, PNG; notation or `--tab`), with live
      process tests. *Left (nice-to-have):* reading the DSL / more input
      formats.

---

## Permanently out of scope

partitura is an interactive **rendering + theory substrate**, not an editor or
a DAW. Explicitly not pursued:

- **Audio synthesis / playback / mixing of any kind** (the timing map and MIDI
  export are the contract-safe substitutes).
- **Note-input / editing mechanics** (caret, insert, force-duration, input
  popovers) — consumers build editing on top of the model.
- **Application backends** — collaboration servers, learning-management
  integration, grade sync, content libraries, cloud publishing, version
  history.
- **Audio/video export**, VST/expression-map playback, and general
  plugin/extension frameworks.
- **Percussion notation** — until a consumer asks.

---

## How each feature ships (the standard pipeline)

Mirror the v0.3–v0.7 pattern. A note-attached mark, a score-level span, and a
measure-level mark each thread through a fixed set of touch points:

1. **Model** — `partitura_core/lib/src/model/{element,measure,score}.dart`:
   a field on `NoteElement`/`Measure`, or a new span class + a `Score.<list>`;
   update the constructor, `==`, `hashCode`, `toString`.
2. **Plumbing** — carry the field through `Score.transposedBy`, the
   `multi_system.dart` per-line rebuild (filter spans by contained ids), and
   the MusicXML reader's chord-merge rebuild.
3. **Glyphs** — names + helper in `smufl/glyph_names.dart`; codepoints in
   `partitura/lib/src/rendering/smufl_glyphs.dart`. Verify the glyph exists in
   the bundled font metadata first (`bBoxOf` throws on a missing name).
4. **Layout** — a `_layoutXxx()` pass in `layout_engine.dart`, or draw inside
   `_layoutNote` when stem/notehead geometry is needed. Use `_addGlyph` /
   `_addLine` (they update the ink bounds and any element hit region).
5. **DSL** (optional) — `Score.simple`. The trailing-marker characters are
   nearly exhausted, so most recent marks are **model-only** (no DSL
   shorthand), which is an accepted convention.
6. **Interchange** — MusicXML reader + writer, round-trip tested. Spans mirror
   the slur/wedge number-pairing pattern; note-attached marks live in
   `<notations>`.
7. **Tests** — a `*_test.dart` in `partitura_core/test/` (value semantics,
   layout assertions on emitted primitives, MusicXML round-trip, transpose).
8. **Golden + gallery** — a numbered scene in `partitura/test/golden_test.dart`
   (regenerate with `flutter test --update-goldens --plain-name '<name>'`) and
   an entry in `partitura/example/lib/gallery.dart`. **Always view the
   generated PNG** — several real bugs have been caught only by looking.
9. **Docs** — `docs/CONTRACT.md` (model bullet + capabilities paragraph), both
   `CHANGELOG.md` files, and check the item off here.
10. **Commit** per feature, then the gates: `dart analyze` + `dart test` in
    `partitura_core`, `flutter analyze` + `flutter test` in `partitura`,
    `dart format`.

**Gotcha:** `smufl_glyphs.dart` stores codepoints as literal escape text
(`'\uE0xx'`) that renders invisibly in editors — after editing those lines,
verify the bytes (e.g. a quick script that prints each name → codepoint)
rather than trusting the on-screen display.
