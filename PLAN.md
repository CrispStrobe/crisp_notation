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
    golden 50) and forced beam slant (`BeamSlant`, golden 51) done. Left:
    beam subdivision, beams-over-rests, cross-measure.
  - **Phase 6 (guitar tablature)** — *pulled forward on request.* Done:
    `Tuning` + `fretFor`; `TabLayoutEngine` + `TabStaffView` (N-line staff,
    TAB clef, fret numbers, broken lines, barlines); rhythm (stems/flags/
    per-beat beams); techniques so far — slides (reuse `glissandos`),
    hammer-on/pull-off (reuse `slurs`), string bends (`Bend`), vibrato
    (`Vibrato`). Goldens 52–56. Contract "tablature out" clause lifted.
- **Test counts:** 594 core + 129 widget, all gates green.

### ▶ Where the next agent picks up

Two open threads; either is a valid continuation (ask the owner which):

1. **Finish Phase 6 tab techniques** (the owner asked for tab "fully").
   Vibrato is done (golden 56). Next cheap batch — palm mute / let ring, dead
   & ghost notes (shared decoration patterns), then harmonics, tapping,
   tremolo bar, rasgueado,
   then chord/fretboard diagrams, then Guitar Pro import. Model each like
   `Bend` (a `Score.<list>` keyed by note id, rendered in `TabLayoutEngine`)
   or reuse an existing span. All tab code: `theory/tuning.dart`,
   `layout/tab_layout.dart`, `rendering/tab_staff_view.dart`.
2. **Resume the Phase sequence** at Phase 1.4's remainder, then Phase 2
   (structure / N-staff — also unblocks tab-paired-with-notation), Phase 3
   (interaction moat), Phase 4 (theory moat), Phase 5 (breadth), Phase 7
   (interchange).

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
  round-trip). *Playback jump execution deferred → see Phase 7 (unfolding).*
- **0.7.2 Piano / technical layer** — fingerings, arpeggio, glissando,
  tremolo, sustain pedal.

---

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
      50), forced beam slant / force-horizontal (`BeamSlant`; golden 51).
      **Left:** beam subdivision, beams over rests (a default-behavior change —
      needs per-case golden verification), cross-measure.

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
- [ ] **5.1 Noteheads** — type set (x, diamond/harmonic, slash, triangle,
      circled…), schemes (shape-note, pitch-name, solfège), cue/small notes,
      colored + out-of-range coloring.
- [ ] **5.2 Extra clefs** — French violin, soprano/mezzo/baritone/subbass,
      percussion.
- [ ] **5.3 Figured-bass notation** — stacked figures, accidentals, slashes,
      continuation lines (rendering; realization is 4.6).
- [ ] **5.4 Lyrics** — multiple verses, melisma extenders, elision slurs,
      hyphenation.
- [ ] **5.5 Voices 3 & 4** per staff + rest merging.
- [ ] **5.6 More barlines & lines** — dashed/dotted/tick/short/reverse-final;
      custom-span barlines across staves; laissez-vibrer ties; palm-mute /
      let-ring / vibrato lines; trill extension line + baroque variants;
      portamento; system dividers.
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
- [~] **6.2 Core tab staff** — **done:** N-line string staff, TAB clef, fret
      numbers with broken lines, barlines, `TabStaffView` (golden 52).
      **Left:** rhythm stems/beams below the staff, capo, per-note string
      override.
- [ ] **6.3 Tab paired with a notation staff** (rides on Phase 2.1).
- [~] **6.4 Techniques** — the full set below. **Done:** rhythm stems/flags/
      beams below the staff; slides (reuse `glissandos`) and hammer-on/pull-off
      arcs (reuse `slurs`) — goldens 53, 54; string bends (`Bend`) — golden 55;
      vibrato (`Vibrato`, normal + wide) — golden 56. **Left:** palm mute/let
      ring, dead/ghost notes, harmonics, tapping, and the rest of the checklist.
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
- [ ] **7.1 MIDI file export** off the existing playback timeline —
      contract-safe (no audio). A natural ecosystem unlock.
- [ ] **7.2 Raster + vector export** — PNG (easy via the Flutter canvas) and
      SVG (own emitter).
- [ ] **7.3 Wider import** — additional interchange formats beyond MusicXML
      (e.g. MIDI, and the common tablature file formats for Phase 6).
- [ ] **7.4 Repeat unfolding** — linearize repeats / voltas / D.C. / D.S. into
      performance order for the playback timeline. **This closes the playback
      jump execution deferred in 0.7.1** and drives correct navigation-mark
      playback.
- [ ] **7.5 Braille music export** — rare in this space; a real accessibility
      differentiator.

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
