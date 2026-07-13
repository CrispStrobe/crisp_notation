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

> **Actively working on:** completing the interactive grand staff — bringing the
> C2/C3 hooks (`onHover`/`caret`/`ghostTarget`, drag-move) and per-system
> justification to `InteractiveGrandStaffView`, the follow-up left from C5. All
> additive. Worktree `partitura-public-lacunae`. *(Workshop contracts C1–C5 are
> done and on `main`; C6 deferred. The three deep Score-model lacunae are done;
> microtones landed via the parallel agent.)*

> **Actively working on (tuplets interchange):** round-trip `TupletSpan` through
> the codecs that don't carry it yet — LilyPond (`\tuplet a/n { … }`, export),
> MEI (`<tuplet num numbase>`) and MuseScore (`<Tuplet>`). Codec files only
> (`lilypond/`, `mei/`, `musescore/`) — no views/model. Worktree
> `partitura-tup2`, branch `feat/tuplets-codecs`.

### Workshop editor contracts (C1–C6)

External consumer (KlangUniversum "Composition Workshop",
`mus-workshop/docs/WORKSHOP_PARTITURA_CONTRACTS.md`) needs these interactive-
editor APIs on `partitura-public@main`. All **additive / backward-compatible**
(new optional params / new widgets; no signature breaks). Convention:
`StaffTarget`, element `id` strings, `PartituraTheme`, `staffSpace`, staff-space
y-down coords. Priority: **C1+C2 → C3 → C5 → C4**.

- [x] **C1 — Staff-tap on the multi-line view.** `MultiSystemView.onStaffTap`
  (`StaffTarget` with `systemIndex`/`staffIndex`, backward-compatible defaults);
  `resolveStaffTarget` picks the nearest system band, quantizes to the nearest
  line/space and resolves the global measure. `multi_system_view_test.dart`.
- [x] **C2 — Hover preview + persistent caret.** `MultiSystemView.onHover`
  (`MouseTrackerAnnotation`; null on exit), a painted `EditorCaret` (before an
  element or at a measure/position), and a `ghostTarget`/`ghostDuration`
  translucent preview notehead with ledger lines. Repaint-only.
  `multi_system_view_test.dart`.
- [x] **C3 — Drag an existing element.** `onElementDragStart/Update/End`
  (elementId + live `StaffTarget`) on `InteractiveStaff` and `MultiSystemView`
  (the latter via a new `PanGestureRecognizer`); a drag on empty staff still
  drives the placement ghost / `onStaffTap`. `interactive_staff_test.dart`,
  `multi_system_view_test.dart`.
- [x] **C4 — Range hit-testing / region geometry.** `elementRegions`
  (`(id, Rect bounds, measureIndex)` in local pixels) + `elementIdsIn(Rect)` on
  `RenderStaffView`, `RenderMultiSystemView` and `RenderInteractiveGrandStaffView`
  — for marquee / shift-click ranges. `multi_system_view_test.dart`,
  `interactive_grand_staff_view_test.dart`.
- [x] **C5 — Interactive multi-line grand staff** *(the big one)*. New
  `InteractiveGrandStaffView` wraps a two-clef `GrandStaff` into systems
  (`layoutGrandStaffSystems`, packing by the wider staff so barlines align, time
  signature on the first system only) with `onElementTap` + `onStaffTap`
  (`StaffTarget` carries `systemIndex`/`staffIndex`). Golden 95;
  `grand_staff_systems_test.dart`, `interactive_grand_staff_view_test.dart`.
  🚧 *Follow-up in progress:* per-system justification, and hover/caret/drag
  (C2/C3 hooks) on `InteractiveGrandStaffView`.
- [ ] **C6 — (later) multi-part document model.** First-class multi-part
  document (shared barlines across parts) + multi-part page layout. Deferred;
  C1–C5 unblock the near-term editor.

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
  - **Phase 7.3/7.4 (interchange):** MusicXML (+ compressed `.mxl`), MEI,
    Humdrum `**kern`, MIDI, MuseScore (`.mscx`/`.mscz`), GPIF and the full
    `.gp3`–`.gp` binary line (`.gp3`/`.gp4`/`.gp5`) + `.gpx` (v6) + `.gp` (v7/8)
    all import (MusicXML/`.mxl`/MEI/kern/MuseScore/GPIF also export; LilyPond
    `.ly` export-only), with the common techniques; nested repeats now expand
    in `playbackTimeline`. The container codecs (ZIP + BCFS) and DEFLATE are
    pure Dart, so the whole surface is web-safe / WASM-compilable.
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

### v0.8 — optical music recognition (OMR)
- **Staff image → score.** The [CrispEmbed](https://github.com/CrispStrobe/CrispEmbed)
  Sheet Music Transformer recognizes a staff-notation image into `bekern`
  tokens; `bekernToKern` reconstructs Humdrum, and a multi-spine kern reader
  (`grandStaffFromKern`/`staffSystemFromKern`, `**ekern`-aware) maps it to a
  `GrandStaff`/`Score`/`StaffSystem` — all pure Dart, in `partitura_core`
  (`src/omr/`). Tuplet reciprocals read as real `TupletSpan`s (see the Humdrum
  tuplet round-trip below), so recognized triplets keep their sounding rhythm.
  The recognition engine is reached over `dart:ffi`
  (`CrispEmbedOmrEngine`) behind the `OmrEngine` abstraction, exposed as the
  `partitura omr` CLI command (image → MusicXML/`.mxl`/`.krn`). Verified
  end-to-end: FFI bekern is byte-identical to the reference engine on the
  GrandStaff samples, and each round-trips through MusicXML.
- **Second engine — Polyphonic-TrOMR.** CrispEmbed's TrOMR engine emits PrIMuS-
  style *semantic* notation (`clef-G2 note-C4_quarter …`, chords via `|`) for a
  single polyphonic staff; `scoreFromSemantic` (`src/omr/semantic.dart`, pure
  Dart) parses it to a `Score`. The `partitura omr` command **auto-detects the
  dialect** (`omrDialectOf`) and routes SMT→`GrandStaff`, TrOMR→`Score` through
  the same FFI engine and output formats. Verified end-to-end on the TrOMR
  sample (image → `Score` → MusicXML).
- **Scan → rendered notation.** `grandStaffToSvg` (`svg/svg_export.dart`) renders
  a two-staff `GrandStaffLayout` — the per-staff emitter is shared with
  `scoreToSvg`, so `scoreToSvg` is byte-for-byte unchanged. `partitura omr` now
  writes `.svg` directly (a grand staff for SMT, a single staff for TrOMR;
  falling back to the upper staff if a recognized grand staff's staves disagree
  on measure count). Verified live: both engines render a scan to SVG.
  `.png` output works too — the CLI delegates to the Flutter raster harness, and
  `renderGrandStaffLayoutToPng` (`rendering/png_export.dart`, the raster twin of
  `grandStaffToSvg`) rasterizes both staves. Verified live: a scan → a two-staff
  PNG.

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
nested repeats), a broad interchange surface (MusicXML, MIDI, the full
`.gp3`–`.gp` line, plus MuseScore `.mscx`/`.mscz`), and the category-unusual
extras — a renderer-free deterministic layout engine, hit-testing, a
highlight/timing pipeline, SVG/PNG export, a CLI, and a **WasmGC-compilable**
core (`dart compile wasm`; see `packages/partitura_core/example/wasm/`).

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
- [x] **1.2 Skyline collision avoidance** — the real engraving-quality gap.
      Give every glyph a skyline outline; place accidentals, articulations,
      dynamics, lyrics, slurs and above/below-staff marks to avoid overlap
      across the whole system. Today, above/below marks clear the global ink
      minima but do not skyline against each other per-column. The most
      invasive item in this phase (touches many placement passes).
      **Done:** horizontal **text** de-overlap (golden 67); and a per-column
      **skyline** — every glyph's ink feeds `_inkRects`, queried by
      `_skylineTop`/`_skylineBottom`, so above/below marks clear only the ink in
      their own horizontal span (not the whole system's extremes). Applied to
      text annotations (golden 86), figured bass, lyrics, navigation marks and
      chord diagrams; **slurs** now arch above the full local skyline (interior
      articulations/accidentals/other marks), not just the spanned noteheads.
      The pass order (notes → ties → slurs → … → annotations/lyrics) means each
      later mark clears the earlier ink. Dense accidental + articulation runs
      render without collision (accidentals reserve horizontal space before the
      note; chord accidentals stack in zig-zag columns — golden 87).
      **Cross-voice accidentals** in a shared two-voice column are laid out
      jointly — both voices' accidentals share one zig-zag block and the
      noteheads align, so they never overlap (golden 88). The accidental-to-note
      gap is a single tuned constant (no visible defect; optical per-context
      micro-spacing deferred as true polish). Educational overlays keep one line
      (they span the full width, so per-column == global there). This closes
      1.2's engraving-quality scope.
- [~] **1.3 Pluggable SMuFL fonts** — **Done:** the engine is already
      font-agnostic (metrics — line/stem thicknesses — flow from whatever
      `SmuflMetadata` it is handed; a heavier-stemmed font renders heavier
      stems, proven by `font_metrics_test`). A `MusicFont` descriptor (family +
      package + metadata asset) plus a `MusicFonts` per-font metadata loader
      make the font swappable via `PartituraTheme.musicFont` (default Bravura);
      the painter draws glyphs in the theme's font and **every view** (staff,
      multi-system, system, page, grand-staff, tab, PNG export) loads the
      theme font's metadata and relayouts on a font change. An end-to-end
      widget test proves a swapped font drives the layout metrics (heavier staff
      lines). SMuFL fixes every glyph's codepoint, so a new face is a pure asset
      drop: ready-made `MusicFont.petaluma`/`leland`/`leipzig` descriptors plus a
      three-step drop-in guide (`assets/smufl/FONTS.md`) with each font's
      verified license and source. **Left (optional packaging):** vendor a real
      `.otf` (each ~1 MB). Licensing is settled — every mainstream SMuFL face is
      SIL OFL 1.1 (bundles cleanly in this MIT repo, as Bravura does); the one
      public-domain option is Gonville/Gootville. The engine work is complete.
- [~] **1.4 Advanced beaming** — feathered/fanned beams (accel./rall.), beam
      subdivision at metric points, custom slope / independent beam-end
      heights, beams over rests, cross-measure beaming. (Cross-staff beaming
      lands with Phase 2.) **Done:** feathered beams (`FeatheredBeam`; golden
      50), forced beam slant / force-horizontal (`BeamSlant`; golden 51),
      beams over rests (a rest inside a beat no longer breaks the beam; golden
      64), secondary-beam subdivision at the quarter-note metric point (a
      group longer than a quarter — e.g. a half-note beat in cut time — keeps
      one continuous primary beam but breaks the secondary beams at the beat's
      sub-pulse; staff + tab), and **cross-measure beaming** —
      `CrossMeasureBeam(startId, endId)` beams a run of notes across a barline
      (excluded from per-measure beaming, deferred stems, drawn in a post-pass
      once both measures' x-positions are fixed; single-system only, since a
      beam cannot cross a line break). **Left:** finer per-level subdivision
      (32nds at the half-beat) — deferred, as it would contradict the tested
      "continuous within a beat" rule.

### Phase 2 — Score structure (multi-staff)
- [~] **2.1 N-staff systems** — **Done:** `StaffSystem` (N `Score` staves +
      `StaffBracket` brace/bracket groups) + `layoutStaffSystem` align barlines
      across the system (column-wise-max widths); `StaffSystemView` stacks them
      with connected barlines and left brackets/braces, cross-staff hit-testing
      (golden 75, a four-staff SATB system). ABC multi-voice (`V:`) imports as a
      system via `staffSystemFromAbc` (golden 76); MusicXML multi-part /
      multi-staff imports via `staffSystemFromMusicXml`, with `<part-group>`
      brackets and per-part braces (golden 77). Nested brackets render with
      per-depth leftward offsets so an outer bracket clears an inner brace
      (golden 78). **Left:** the hard-coded 5-line-staff generalization (tab
      already has its own N-line engine).
- [~] **2.2 Cross-staff notes / stems / beams** — a beam spanning both staves
      of a keyboard system. **Done:** `CrossStaffBeam(noteIds)` on `GrandStaff`;
      the engine defers the joined notes' stems (`deferredStems` →
      `ScoreLayout.crossStaffStubs`) and `layoutGrandStaff` draws the connecting
      beam between the staves using `staffGap` (upper notes stem down, lower up).
      Golden 93; `cross_staff_test.dart`. **Left:** slanted / multi-bar (16th)
      cross-staff beams, cross-staff chords/stems (a single stem's noteheads on
      both staves), and a MusicXML `<staff>` round-trip.
- [ ] **2.3 Hide-empty / ossia / divisi / cutaway staves** — dynamic staff
      count: drop empty staves per system, add temporary alternative (ossia)
      staves, split a part into subsections, remove empty bars.
- [~] **2.4 Pickup / anacrusis + actual-vs-nominal measure duration +
      irregular measures** — foundational; a large fraction of real pieces
      need a partial first bar or a metric length differing from the notated
      one. **Done:** `Measure.pickup` (anacrusis) with auto-detection of a
      short opening bar under a known meter (DSL + ABC), MusicXML
      `implicit="yes"` read/write with anacrusis-aware renumbering, and a
      `showMeasureNumbers` overlay that skips the pickup so the first full bar
      reads `1` (golden 80). Layout already tolerates irregular measures
      (content-proportional, no meter enforcement). **Left:** an explicit
      actual-vs-nominal measure length (for mid-piece irregular bars).
- [~] **2.5 Page-layout engine** — **Done:** `layoutPages` paginates the broken
      systems into `PageMetrics` pages (size + margins in staff spaces), packing
      systems by content height and vertically justifying every page but the
      last (page-fill); `ScorePageView` renders a single page at its exact
      aspect ratio with margins and an optional frame (golden 81). **Left:** a
      physical spatium/mm scaling unit, explicit page/section breaks, spacers,
      and title/text frames.
- [~] **2.6 Linked parts + transposing instruments + concert-pitch toggle** —
      **Done:** `Transposition` (interval + direction + octaves, with named
      B♭/A/E♭/F/tenor constants), `Score.transposition`, `Score.atConcertPitch()`
      (moves written pitch **and** key to sounding, clears the tag) and
      `StaffSystem.atConcertPitch()`; MusicXML `<transpose>` read/write
      (diatonic/chromatic/octave-change). **Left:** linked parts / part
      extraction (one edit reflected in score + part) and a written-vs-concert
      view toggle in the renderer.
- [~] **2.7 Measure-numbering system** — **Done:** a `showMeasureNumbers`
      overlay numbering every measure (anacrusis-aware; delivered with 2.4).
      **Left:** per-system-only / every-N numbering, per-measure overrides,
      section reset, and measure-repeat signs (1/2/4-bar).

### Phase 3 — Interactivity  *(the moat — where partitura wins)*
Rides the existing cursor + selection; no audio needed.
- [ ] **3.1 Cursor-synced instrument visualizers** — a piano keyboard (L/R
      hand) and a guitar fretboard that light up as the playback cursor
      advances. The single highest-differentiation feature; pairs directly
      with the no-audio timing map.
- [x] **3.2 Note-name & rhythm-count overlays** — the note-name overlay
      (`showNoteNames`; pitch letter + accidental under each note, chords
      stacked; golden 73) and the rhythm-count overlay (`showBeatNumbers`; beat
      number + `+` above each note — `1 + 2 + 3 + 4 +`; golden 74). Both are
      layout options (rendering in both back-ends) exposed on `StaffView`, and
      coexist for a full teaching view.
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
- [x] **4.1 Roman-numeral analysis (bidirectional)** — `romanNumeralOf(pitches,
      key)` reads a chord as a `RomanNumeral` (scale degree with chromatic
      prefix, quality case + °/ø/+ marks, figured-bass inversion figures 6…4/2,
      major-seventh `M`, and secondary dominants/leading-tone chords like
      `V7/V`, `vii°7/V` with the target rendered in its own case). Minor keys
      accept the raised 6/7 as diatonic (V, vii°). `pitchClassesOf(numeral, key)`
      realizes the numeral back to its pitch classes (the reverse direction).
      `RomanNumeral.symbol` renders it. Highest pedagogy payoff.
- [x] **4.2 Part-writing / voice-leading checker** — `checkVoiceLeading(chords)`
      (each chord a list of pitches top-to-bottom) flags parallel and hidden
      (direct) perfect fifths/octaves, voice crossing (within a chord), voice
      overlap (between chords) and upper-voice spacing (> an octave, bass–tenor
      exempt), returning typed `VoiceLeadingIssue`s (rule + chord + voice pair).
      Pure theory (`theory/voice_leading.dart`).
- [x] **4.3 Key finding** — Krumhansl-Schmuckler: `findKey(pcWeights)` /
      `keyOf(pitches, {durations})` correlate a pitch-class weight profile
      against the 24 rotated major/minor key profiles and return the best `Key`;
      `localKeys(pitches, window)` slides that over the line to track modulation.
      Pure theory (`theory/key_finding.dart`).
- [~] **4.4 Chord identification from a pitch set** — **Done:**
      `identifyChord` / `chordSymbolFor` — root, quality (triads, sevenths,
      sixths, sus) and inversion (as a slash chord) from a pitch set, spelled
      from the input, bass disambiguating (C6 vs Am7). **Left:** extended
      chords (9/11/13), augmented-sixth recognition, alternate spellings.
- [x] **4.5 Post-tonal set theory** — `normalForm`, Forte `primeForm`,
      `intervalClassVector` and `zRelated` for a pitch-class set, plus
      `transposeSet`/`invertSet`/`pitchClassSet` helpers
      (`theory/set_theory.dart`). *Left:* the Forte set-class *number* naming
      table (the prime form is the canonical identifier).
- [x] **4.6 Figured-bass realization** — `figuredChordPitchClasses(bass, figure,
      key)` parses a figure (`6`, `6/4`, `7`, `#`, …; single-digit stacked
      numbers, per-degree accidentals, lone accidental → the third) into the
      chord's pitch classes; `realizeFiguredBass(pairs, key)` completes it to
      four-part SATB, picking each chord's voicing to minimise `Σ|motion| +
      100·(voice-leading errors)` — using the 4.2 `checkVoiceLeading` engine as
      the grader, so common tones hold and parallels are avoided.
      `theory/figured_bass.dart`.
- [x] **4.7 Metrical-accent hierarchy** (`beatStrength`) — a `TimeSignature`
      extension mapping each metric position to an accent strength (downbeat
      1.0, halving down the meter's hierarchy): 4/4 → beat 3 = ½, beats 2/4 = ¼;
      3/4 → both weak beats ½; 6/8 accents the second dotted beat; additive
      meters accent each group start; off-grid (triplet) positions score 0.
      Exact-`Fraction` grid resolved to the 64th. Wiring it into automatic
      beaming is a follow-up.
- [x] **4.8 Extras** — neo-Riemannian `parallel`/`relative`/`leittonwechsel`
      (P/L/R) on major/minor `Triad`s (`neo_riemannian.dart`); twelve-tone row
      forms + the 12×12 matrix (`twelve_tone.dart`); and `matchingScales(pcs)`
      scale derivation, ranked (`scale_matching.dart`). *Left:* the analysis
      text I/O format (deferred — no established interchange format to target).

### Phase 5 — Notation breadth
- [~] **5.1 Noteheads** — **Done:** the shape set (x, diamond, triangle-up,
      slash, circled-x — `NoteheadShape`, duration-aware variants, MusicXML
      `<notehead>` round-trip, golden 66); per-element **coloring** end to end
      (`StaffView.elementColors` render param + SVG `elementColors`; golden 72).
      **Left:** shape-note / pitch-name / solfège schemes, cue/small notes.
- [x] **5.2 Extra clefs** — neutral / unpitched **percussion** clef
      (`Clef.percussion` → `unpitchedPercussionClef1`, no key signature; ABC
      `clef=perc`; golden 83), and the **French violin / soprano / mezzo-soprano
      / baritone / sub-bass** C- and F-clef positions (golden 84) — each with a
      correct bottom-line reference and on-staff key signatures (derived by the
      standard fifth-stacking rule for clefs without a hand-tuned table). All
      round-trip through MusicXML `<clef>` (sign + line).
- [~] **5.3 Figured-bass notation** — **Done:** stacked figures with digit +
      `#`/`b`/`n`/`+` alterations, drawn from the SMuFL figured-bass glyphs;
      MusicXML `<figured-bass>` round-trip (golden 70). **Left:** slashed
      figures (e.g. 6\\) and horizontal continuation lines; realization is 4.6.
- [~] **5.4 Lyrics** — **Done:** hyphenation + melisma extenders (v0.4);
      multiple **verses** stacked on their own baselines (`Lyric.verse`,
      MusicXML `<lyric number>` round-trip, golden 68). **Left:** elision
      slurs, lyric-driven horizontal spacing (wide syllables pushing notes
      apart).
- [x] **5.5 Voices 3 & 4** per staff. **Increment 1 (representability):**
      `Measure.voice3`/`voice4` + a `voices` getter (four voices per staff),
      round-tripping through MusicXML/MEI/MuseScore and covered by playback +
      transposition (`voices_three_four_test.dart`). **Increment 2 (layout):**
      `_layoutTwoVoiceMeasure` generalized to N voices
      (`_layoutMultiVoiceMeasure`) — odd voices stem up / even down, shared onset
      columns, per-voice staggered rests, cross-voice collision shift, joint
      accidental columns; the `Score.simple` DSL takes up to four `;`-voices;
      goldens `90_three_voices` + `91_four_voices`.
- [~] **5.6 More barlines & lines** — **Done:** closing-barline styles
      (double / final / heavy / dashed / dotted / none — `BarlineStyle`, MusicXML
      `<bar-style>` round-trip, golden 65); breath marks + caesura
      (`BreathMark`, MusicXML `<breath-mark>`/`<caesura>`, golden 71).
      **Left:** tick/short/reverse-final;
      custom-span barlines across staves; laissez-vibrer ties; palm-mute /
      let-ring / vibrato lines (exist in tab; add to notation); trill extension
      line + baroque variants; portamento; system dividers.
- [~] **5.7 Time-signature breadth** — **Done:** common/cut symbols
      (`TimeSymbol`, `TimeSignature.commonTime`/`cutTime` → the C / ¢ glyphs;
      golden 82) and **additive/composite meters** (`TimeSignature.additive`
      `[3,2]` → 3+2/8 drawn with the `timeSigPlus` glyph; golden 85). Both
      round-trip through MusicXML `<time>` and ABC `M:`. **Senza misura /
      open meter** is `timeSignature: null` — no signature drawn, no metric
      subdivision (round-trip locked in by `non_standard_key_test.dart`).
      **Left:** local per-staff meters, interchangeable/alternating meters, and
      additive-aware beam grouping.
- [x] **5.8 Custom / atonal key signatures + cancelling-naturals policy.**
      `KeySignature.custom([KeyAccidental(step, alter), …])` — modal/atonal
      signatures the circle of fifths can't express (mixed B♭ + F♯, or a
      non-traditional order). `alterFor`/`alteredSteps` drive the drawn
      signature (each accidental at its step) and note-accidental suppression;
      mid-score key changes emit cancellation naturals for custom keys too.
      Round-trips through MusicXML `<key-step>`/`<key-alter>`; left as written
      under transposition. Golden 92; `non_standard_key_test.dart`.
- [~] **5.9 Jazz articulations** — **Done:** scoop, doit, fall (falloff), plop
      (`JazzMark`/`JazzArticulation`, brass glyphs before/after the notehead,
      MusicXML `<articulations>` round-trip, golden 69). **Left:** lift, flip,
      smear, bend (render-only; not standard MusicXML articulations).
- [x] **5.10 Microtonal accidentals + remappable alteration glyphs** —
      `Pitch.microtone` (optional `MicrotonalAccidental`: half/three-quarter
      sharp/flat, ±50/±150 cents) draws the Stein-Zimmermann quarter-tone glyphs
      and always shows (never implied by the key). `Pitch.centsOffset` exposes
      the tuning for pitch-bend playback; the integer `alter`/MIDI number are
      unchanged (additive). Glyphs are remappable for non-Western systems via
      `LayoutSettings.microtonalGlyphs`. **Contract change:** the "microtonal
      out" clause is hereby lifted (quarter-tone notation is now in scope; finer
      just-intonation ratios and full non-Western theory remain out).

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
- [x] **6.5 Tunings & other fretted instruments** — preset `Tuning`s for
      DADGAD, open-G, 7- and 8-string guitar, 5-string bass, 5-string banjo
      (reentrant high-G drone), ukulele (reentrant high-G) and mandolin, on top
      of the existing standard/drop-D guitar and 4-string bass. The N-line tab
      engine already engraves any string count, so these render directly
      (verified: ukulele → 4 lines, 7-string → 7, low B1 open).

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
      (`asciiTabToScore`); `.gp` import **and** export (`scoreFromGpif` /
      `scoreToGpif` GPIF subset + the `.gp` ZIP container in `partitura_cli`).
      That import also reads the common playing techniques (HO/PO, slides, bends,
      vibrato, palm mute, let ring, dead, natural/artificial/pinch harmonic)
      into the tab marks. All formats round-trip transparently through the
      shared `Score` model for the data they share. The full `.gp3`–`.gp` binary
      line imports via `gp_binary_reader.dart` — `.gp3`, `.gp4`,
      `.gp5`, a from-scratch byte-exact reader — plus `.gpx` (v6, BCFZ/BCFS)
      and `.gp` (v7/8, GPIF-in-ZIP), all wired into the CLI and
      regression-tested against real vendored alphaTab fixtures
      (`partitura_cli/test/gp_fixtures_test.dart`; `.gp3`/`.gp4`/`.gp5` agree note-for-note
      on the shared techniques). **ABC notation import + export**
      (`scoreFromAbc` / `scoreToAbc`) — the folk/traditional plain-text format:
      `M`/`L`/`K` header (meter, unit length, key + church modes, clef), notes
      with accidentals (key + in-measure state), octave marks and fractional /
      broken-rhythm (`>`/`<`) lengths, rests, chords, ties, tuplets (`(3`),
      slurs, grace notes, staccato, `"C"` chord symbols → annotations, bar
      lines (repeats, double/final), `w:` lyrics, and multi-voice (first voice);
      round-trips through the score model, wired into the CLI (`.abc`),
      validated against the abcjs example tune-book. **Left:** the ABC subset's
      tail (decorations beyond staccato, multi-voice → grand staff, symbol
      lines); `.ptb` (PowerTab, no freely-licensed test corpus).
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

## ABC notation — coverage toward abcjs parity

Goal: **fully parse and render every ABC 2.1 construct that abcjs supports.**
Both codecs (`abc_reader.dart` / `abc_writer.dart`) funnel through the one
`Score` model, so anything the model can hold renders in both back-ends. Items
are executed **one after another, each with tests**. Status: `[x]` done,
`[~]` partial, `[ ]` to do, `⛔` gated on another roadmap item.

**Pitch, rhythm, grouping** *(largely done)*
- [x] Notes `A–G`/`a–g`, accidentals `^ ^^ _ __ =`, octaves `,`/`'`
- [x] Note lengths: multipliers, `/`, `/n`, `n/m` fractions
- [x] Rests `z`/`x`; chords `[CEG]`; ties `-`; slurs `( )`; grace `{…}`
- [x] Tuplets `(p` / `(p:q` / `(p:q:r`; broken rhythm `>`/`<`/`>>`
- [x] Acciaccatura grace `{/…}` (slashed)
- [ ] Spacer `y`; truly-invisible `x` (imports as a visible rest)
- [ ] Microtones (`^/`, `_3/2`…) — now representable (`Pitch.microtone`, Phase
      5.10 done); wiring the ABC reader to parse `^/`/`_/` into quarter-tone
      accidentals is the remaining step

**Bar lines & repeats**
- [x] `|` `||` `[|` `|]` `|:` `:|` → barline styles + repeats
- [x] **Variant endings / voltas** `|1 |2`, `[1 [2`, `:|2` → `Measure.volta`
- [ ] Dotted bar `.|`, invisible bar, `[|]`

**Decorations & articulations**
- [x] `.` staccato
- [x] `!…!` decorations → articulations (fermata, accent, tenuto, marcato) and
      ornaments (trill, mordent, uppermordent, turn); dynamics `!p!`…`!ff!`
- [x] Shorthand `~ H T M P` → ornaments / fermata
- [x] Navigation `!segno!` `!coda!` `!D.C.!` `!D.S.!` `!fine!` (+ al fine/coda)
      → `Measure.navigation` (drives the `playbackTimeline` jumps)
- [ ] Bowing `u`/`v`, emphasis `L` (no model equivalent yet)

**Text, symbols, inline fields**
- [x] `"C"` chord symbols → annotations; `w:` lyrics with `- _ * |`
- [x] Positioned annotations `"^…"` `"_…"` `"<…"` `">…"` `"@…"` (marker stripped)
- [x] **Inline fields** `[K:…]` (key/clef) `[M:…]` (meter) `[L:…]` (unit)
      mid-tune → `Measure.keyChange`/`timeChange`/`clefChange`
- [x] Header `X T M L K V w`; other metadata fields ignored (harmless)
- [x] `Q:` tempo (header + mid-tune → metronome annotation `♩ = n`), `P:` part
      labels (→ annotations), line continuation `\`
- [x] Dotted bar `.|` → `BarlineStyle.dotted` (round-trips; a lone `.` is still
      staccato)
- [x] `u`/`v` up/down-bow → `Articulation.upBow`/`downBow` (drawn above the
      staff; round-trips through ABC and MusicXML `<technical>`)
- [ ] `U:` redefinable symbols, `m:` macros, `s:` symbol lines, `W:` unaligned
      words
- [x] `%` comments; `%%` stylesheet directives ignored (rendering-hint only)

**Structure**
- [x] Multi-measure rest `Z`/`Zn` → `Measure.multiRest`
- [x] Multi-voice `V:` — `scoreFromAbc` takes the first voice
- [x] Multi-voice → **multiple staves / system** — `staffSystemFromAbc` imports
      each `V:` voice as its own staff (own clef + lyrics, unique ids), aligned
      as a `StaffSystem` (golden 76); field-line and inline `[V:n]` styles
- [~] Parts `P:` — mid-tune labels import as annotations; full `P:AABB`
      section-ordering / playback expansion is not modeled

**Fidelity harness**
- [x] The abcjs example tunes (Money Lost, Pretty Little Liza, Mary) import
      with their bars/chords/endings/lyrics as committed regression tests
      (`abc_test.dart` → "fidelity: the abcjs example tune-book"). *Left:*
      grow the corpus; Amazing Grace needs multi-staff.

---

## Interchange parity & Score-model lacunae

Every interchange codec funnels through the one `Score`, so "parity" has **two
layers**: (1) does a codec carry a feature the model *already* represents, and
(2) can the model represent it at all. This section tracks both, and is the
map for the ongoing enrichment of the newer codecs toward MusicXML (the
reference).

### Layer 1 — codec coverage (feature is in the model; is it round-tripped?)

MusicXML is the most complete reader/writer. MEI, MuseScore, Humdrum `**kern`
and LilyPond (export-only) started as a base subset (clef/key/meter + changes,
notes/chords/rests, durations+dots, ties, two voices, pickup) and are being
enriched toward it, one feature-group per commit.

- **Done:** base subset for all four; **articulations** (staccato/tenuto/
  accent/marcato/fermata + up/down-bow) and **ornaments** (trill/short-trill/
  mordent/turn) now round-trip in MEI/MuseScore/kern and emit in LilyPond
  (`interchange_articulations_test.dart`, `interchange_ornaments_test.dart`).
  MEI ornaments use `<trill>`/`<mordent>`/`<turn>` control events by `xml:id` —
  the note-anchoring mechanism slurs/dynamics will reuse.
- **Enrichment backlog** (each already in the model, MusicXML-only today —
  ordered by leverage): **grace notes**, **slurs**,
  **dynamics + hairpins**, **lyrics** (**tuplets** now also round-trip through
  Humdrum `**kern`), then the
  MusicXML-only long tail — **fingerings, arpeggio, single-note tremolo,
  notehead shape, ottavas, glissandos, pedals, jazz marks, figured bass, breath
  marks, transposition**, and the measure-structure set (**repeats, voltas,
  multi-measure rests, navigation, barline styles**). Slurs/dynamics/ornaments
  need note-anchoring; for MEI/MuseScore that means emitting stable element
  ids (`xml:id`) and control events — a shared step that unlocks that whole row.
- **Carried by NO codec yet** (model *has* these; no reader/writer touches
  them): `featheredBeams`, `beamSlants`, `chordDiagrams`, all eight tab-only
  spans (`bends`/`vibratos`/`palmMutes`/`letRings`/`tabNoteMarks`/`tabVoicings`/
  `taps`/`tremoloBars`). The tab family is expected (these formats aren't tab);
  feathered/slant beams and chord diagrams could be added to MusicXML/MEI.
- **Not preserved by design:** element `id` strings (every reader regenerates
  `e0, e1, …`; span anchoring survives only because writer+reader agree on
  order). MIDI additionally loses spelling (re-spelled sharp), tuplets and all
  structure (unfolded via `playbackTimeline`).

### Layer 2 — Score-model lacunae (feature is NOT representable at all)

Features real formats carry that the `Score` model currently **cannot hold**.
Marked `[cheap]` (an additive field/enum, low blast radius) or `[deep]`
(touches equality, layout and every codec). Until implemented these are lost on
*every* hop, so a codec "dropping" them is a model gap, not a codec gap.

- **Work / score metadata** — title, composer, lyricist, copyright. **✓ Done:**
  `ScoreMetadata` on `Score`, carried through the MusicXML/MEI/MuseScore/kern/
  LilyPond headers (`interchange_metadata_test.dart`).
- **Structured tempo / metronome marks** — `♩ = 120` as data. **✓ Done:** a
  `Tempo` (bpm + beat unit + dots) on `Score`, through MusicXML/MEI/MuseScore/
  kern/LilyPond (`interchange_tempo_test.dart`). *Left:* mid-score tempo changes
  (initial tempo only today) and drawing it in the layout engine.
- **Instrument / part identity** — **✓ name done** (`ScoreMetadata.instrument`,
  via the same headers); MIDI program/channel + abbreviation still deferred.
  `[cheap]`
- **Extended dynamics vocabulary** — **✓ Done:** `DynamicLevel` gains
  `ppp/pppp/fff/ffff` + `sf/sfz/sffz/fz/fp/rf`, each SMuFL-glyph-mapped and
  MusicXML/ABC-round-tripped (`dynamics_vocabulary_test.dart`). *Left:*
  arbitrary text dynamics (`poco f`, etc.).
- **Structured chord symbols** — **✓ Done:** `ChordSymbol` (root pitch +
  `ChordSymbolKind` + slash bass) on `Score`, rendered on the annotation row,
  **transposable roots**, MusicXML `<harmony>` round-trip; text annotations
  moved to `<words>` (`chord_symbol_test.dart`). *Left:* MEI `<harm>` and ABC
  structured-chord round-trip (they still carry chords as text today).
- **Voices 3–4 per staff** — **✓ Done (both increments):** `Measure.voice3`/
  `voice4` + a `voices` getter, round-tripping through MusicXML/MEI/MuseScore,
  covered by playback + transposition (`voices_three_four_test.dart`); and the
  layout engine engraves two to four voices (`_layoutMultiVoiceMeasure`, goldens
  90–91). See 5.5.
- **Appoggiatura (grace style)** — **✓ Done:** `NoteElement.graceStyle`
  (acciaccatura/appoggiatura), gated in the grace-note renderer and
  MusicXML-round-tripped (`grace_style_test.dart`). *Left:* per-grace durations,
  and grace-note support in MEI/MuseScore/kern/LilyPond (the grace-notes
  enrichment on the codec backlog).
- **Microtones** — ✅ quarter tones done (`Pitch.microtone`, Phase 5.10);
  integer `Pitch.alter` stays −2..2. Finer just-intonation ratios still `[deep]`.
- **Non-standard meters** — **✓ senza misura / open** is `timeSignature: null`
  (no signature, no subdivision; round-trip tested). *Left:* interchangeable/
  alternating meters. **Non-standard key signatures** — **✓ Done:**
  `KeySignature.custom` (modal/atonal, any accidental order) drives layout +
  note suppression + MusicXML round-trip (5.8, golden 92).
- **Cross-staff notes & beaming** — **✓ cross-staff beams done** (`CrossStaffBeam`
  on `GrandStaff`, 2.2, golden 94). *Left:* cross-staff chords (one stem, heads
  on both staves), **cue/ossia notes, explicit beam grouping.** `[deep]`
- **Tuplet/​slur constraints** — tuplets cannot cross barlines or nest;
  documented model constraints, not bugs.

Convention: prefer implementing a `[cheap]` lacuna when a codec would otherwise
have to drop it; batch the `[deep]` ones into their Phase (2/5) rather than
bolting fields on ad hoc.

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
