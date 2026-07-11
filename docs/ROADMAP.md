# partitura — feature-parity roadmap

Gap analysis against the three JavaScript incumbents — **VexFlow** (the
low-level engraving library), **OpenSheetMusicDisplay/OSMD** (MusicXML
renderer built on VexFlow) and **abcjs** (ABC-notation renderer + synth) —
and the plan to close the gaps that matter.

> Beyond the three JS incumbents below, a wider 8-app ecosystem scan
> (MuseScore, LilyPond, Dorico, Verovio, alphaTab, music21, and the
> Soundslice/Flat/Noteflight interactive apps) lives in
> [COMPETITIVE_ANALYSIS.md](COMPETITIVE_ANALYSIS.md) — it surfaces the
> engraving-quality, interaction-moat, theory-moat, and tablature deltas that
> feed later milestones.

This document has two parts:

- **Part I — v0.7 long-tail parity** (current): a fresh gap analysis
  written 2026-07-11 against **VexFlow ~5.0**, **OSMD ~1.9** and
  **abcjs ~6.6**, after the original parity plan (below) shipped in full.
- **Part II — the original v0.1–v0.6 parity plan** (historical): the
  analysis written 2026-07-10 at v0.2 and the plan that closed it. Every
  row of that plan is now implemented; it is kept as the record of what
  shipped and why.

---

# Part I — v0.7 long-tail parity (2026-07-11)

## Why a second gap analysis

The original matrix (Part II) was the *headline* feature set: what a
beginner-to-intermediate single-part or piano score needs, plus MusicXML
round-trip and interactivity. Every row of it now reads ✓ for partitura.
"Feature-complete" against that table is **not** parity with the three
incumbents — those libraries carry a long tail the v0.2 table never
enumerated (navigation marks, piano/technical marks, extra noteheads,
tremolo/arpeggio/glissando, alternate fonts, MIDI export…). Part I is that
long tail, re-derived from exhaustive current inventories of all three.

None of it is architecturally hard on partitura's existing
model → layout → paint pipeline: it is **breadth, not depth**. The moat
(first-class interactivity, pure-Dart deterministic layout, a pedagogy
theory core, repaint-only highlighting) still stands; defend it while
adding breadth.

Legend: ✓ = full · ● = partial · — = none.

## Tier 1 — common in real scores; all three have it, partitura does not

| Feature | VexFlow | OSMD | abcjs | partitura today |
|---|---|---|---|---|
| Coda / Segno / D.C. / D.S. / Fine navigation | ✓ | ✓ | ✓ | — (repeats + voltas only) |
| Pedal marks (Ped. / sost. / una corda) | ✓ | ✓ | ✓ | — |
| Fingering numbers | ✓ | ✓ | ✓ | — |
| Tremolo (single-note strokes + between two notes) | ✓ | ✓ | ✓ | — |
| Arpeggio / roll (vertical wavy before a chord) | ✓ | ✓ | ✓ | — |
| Glissando / slide line | ✓ | ✓ | ✓ | — |
| 3+ staff systems | ✓ | ✓ | ✓ | — (`GrandStaff` is exactly 2) |
| Trill wavy-line extension | ✓ | ✓ | — | ● (glyph only, no line) |
| cresc./dim. as dashed text (not only a wedge) | ✓ | ✓ | ✓ | — (hairpin wedge only) |

## Tier 2 — pedagogy / breadth wins, cheap on the existing pipeline

| Feature | VexFlow | OSMD | abcjs | partitura today |
|---|---|---|---|---|
| Model note-coloring (pitch color, Boomwhacker, custom set) | ✓ (style) | ✓ (`coloringMode`) | ● (CSS) | — (highlight infra only) |
| Cue / small notes (distinct from grace) | ✓ | ● | ● | — |
| Notehead shapes (x, diamond/harmonic, triangle, slash) | ✓ | ✓ | ✓ | — |
| More articulations (staccatissimo, breath, caesura, up/down-bow, harmonic) | ✓ | ✓ | ✓ | ● (5: staccato/tenuto/accent/marcato/fermata) |
| Fuller dynamics (sf, sfz, fp, rfz, pppp/ffff) | ✓ | ✓ | ✓ | ● (pp…ff) |
| Multiple lyric verses | ● | ✓ | ✓ | — (`Lyric` has no verse index) |
| Rendered measure numbers | ✓ | ✓ | ✓ | — (emitted to MusicXML, never drawn) |
| Cautionary / parenthesized accidentals | ✓ | ✓ | ● | ● (`showAccidental:true` forces, not parenthesized) |
| Part-group brackets + nested grouping | ✓ | ✓ | ✓ | ● (single brace) |
| 15ma ottava + fuller C-clef family (soprano/mezzo/baritone/subbass) | ✓ | ✓ | ● | ● (4 clefs + 3 octave variants, 8va only) |

## Tier 3 — ecosystem / output; bigger lifts

| Feature | Who has it | Notes for partitura |
|---|---|---|
| MIDI file export | abcjs | Pure-Dart serializer on top of the existing `playbackTimeline`. **No audio** — fully within contract. Natural unlock. |
| SVG / PNG export | OSMD, abcjs | `PictureRecorder`→PNG is easy; SVG is real work (own emitter). |
| ABC import | abcjs (native) | Broadens ingest beyond the DSL + MusicXML. |
| Alternate SMuFL fonts (Petaluma/Leland "handwritten") | VexFlow | SMuFL metadata layer already abstracts glyphs; mostly asset + config. |
| Cross-staff beaming | VexFlow only | Hardest, least-supported even among incumbents (OSMD/abcjs punt). Low priority. |

## Explicitly out by the HANDOVER contract (needs a product decision, not engineering)

The three incumbents have these; partitura's contract currently excludes
them. Listed so the exclusion stays a *conscious* choice, since literal
"parity on every count" would include them:

- **Audio synthesis / playback** (abcjs) — permanently out per HANDOVER
  ("partitura renders; it never makes sound"). partitura supplies the
  timing map instead; MIDI export (Tier 3) is the contract-safe analogue.
- **Percussion notation**, **microtonal accidentals** — out until a
  consumer asks.
- **Tablature + guitar bends** — a consumer asked (2026-07-11), so promoted
  to its own milestone **v0.8** below (needs a HANDOVER/CONTRACT amendment
  lifting the "tablature out" clause).

**Figured bass** is intentionally skipped: none of the three render it
well, so it is not a parity gap.

## v0.7 sequencing

Ordering principle unchanged from v0.3–v0.6: model + layout foundations
first, pedagogical value weighted over engraving completeness, reuse the
span/attachment infrastructure already built for slurs/hairpins/ottava.

- [x] **0.7.1 Navigation marks** — Coda, Segno, D.C., D.S. (+ al Coda / al
      Fine), Fine. Measure-level `NavigationMark` (like `startRepeat`/
      `volta`), drawn on one shared line above the staff per system, MusicXML
      `<direction>`/`<sound>` round-trip. **Playback jump execution
      deferred** — the marks render and round-trip but the timeline does not
      yet follow them; that state machine is its own slice.
- [x] **0.7.2 Piano / technical layer** — **complete:** fingerings (0.7.2a),
      arpeggio (0.7.2b), glissando (0.7.2c), tremolo (0.7.2d), pedal marks
      (0.7.2e). All share the span/attach infra from hairpins and slurs.
- [ ] **0.7.3 N-staff systems** — generalize `GrandStaff` from 2 → N staves
      with brackets and nested part groups. Unblocks choral (SATB) and
      organ/orchestral literature and a large slice of real-world
      MusicXML. Largest structural item.
- [ ] **0.7.4 Pedagogy breadth** — model note-coloring (pitch /
      Boomwhacker / custom set), cue notes, notehead shapes, extra
      articulations + dynamics, multiple lyric verses, rendered measure
      numbers, cautionary accidentals.
- [ ] **0.7.5 MIDI export** — off the existing playback timeline. Cheap,
      high ecosystem value, contract-safe (no audio).
- [ ] **0.7.6 Output & ingest** (demand-driven) — PNG/SVG export, ABC
      import, alternate SMuFL fonts.

## v0.8 — guitar tablature (consumer-requested 2026-07-11)

Scope decision: **full techniques** (not a fret-numbers-only MVP). This is
a *parallel notation mode*, not a decoration on the 5-line staff, so it
gets a design phase before implementation and a contract amendment lifting
the "tablature out" clause. Overlaps and should build on **0.7.3** (N-staff
systems), since real tab is usually paired with a notation staff.

Sub-slices, foundations first:

- [ ] **0.8.0 Design + contract amendment** — N-line staff generalization
      (the engine's `y = (8 − staffPosition)/2` and `Pitch.staffPosition`
      assume exactly 5 lines), `Tuning` model (open-string pitches; standard
      guitar, bass, drop-D, custom), pitch → (string, fret) assignment, the
      TAB clef, DSL + MusicXML `<staff-details>`/`<technical>` mapping.
- [ ] **0.8.1 Core TAB staff** — 6-line (configurable) staff, TAB clef,
      fret numbers instead of noteheads, optional rhythm stems below.
- [ ] **0.8.2 Tab paired with notation** — a notation staff + its TAB in
      one system (rides on 0.7.3).
- [ ] **0.8.3 Techniques** — bends (with release, multi-point), slides,
      hammer-on / pull-off, vibrato, palm mute; MusicXML `<bend>`/`<slide>`
      round-trip.
- [ ] **0.8.4 Tunings** — presets (bass, drop-D, DADGAD…) + custom.

Each item ships the full pipeline exactly as v0.3–v0.6 did: model + layout
+ unit tests in `partitura_core`, painting + goldens + interaction tests in
`partitura`, gallery entry where visual, CONTRACT/CHANGELOG updates, gates
green (`dart format`, analyze zero issues, all tests), push.

---

# Part II — original v0.1–v0.6 parity plan (2026-07-10, historical)

Gap analysis against the three JavaScript incumbents — **VexFlow**,
**OSMD** and **abcjs** — and the plan to close the gaps that matter.
Written at v0.2. **All items below are now implemented** (v0.3–v0.6); the
section is retained as the record of what shipped.

## Where we stand

**What partitura already does that the incumbents do poorly or not at
all** — this is the moat, defend it while adding features:

- First-class interactivity: every element hit-testable/highlightable,
  quantized staff taps, ghost-note drag, kid-mode ergonomics. (abcjs has
  click handlers; VexFlow/OSMD leave hit-testing to the app.)
- Pure-Dart deterministic layout, testable without a renderer.
- A pedagogy-shaped theory core (`Key.triadFor`, scales, exact duration
  arithmetic) — the JS libraries have little or no theory model.
- Repaint-only highlight pipeline (OSMD's cursor re-renders far more).

**Feature gaps** (✓ = has it, ● = partial, — = no):

| Feature | VexFlow | OSMD | abcjs | partitura v0.2 |
|---|---|---|---|---|
| Ties | ✓ | ✓ | ✓ | — |
| Slurs | ✓ | ✓ | ✓ | — |
| Tuplets | ✓ | ✓ | ✓ | — |
| Articulations (staccato…fermata) | ✓ | ✓ | ✓ | — |
| Dynamics (p…ff, hairpins) | ✓ | ✓ | ✓ | — |
| Grace notes | ✓ | ✓ | ✓ | — |
| 32nd+ durations, breve | ✓ | ✓ | ✓ | — (to 16th) |
| Mid-score clef/key/time changes | ✓ | ✓ | ✓ | — |
| Repeats, voltas, rehearsal marks | ✓ | ✓ | ✓ | — |
| Multiple voices per staff | ✓ | ✓ | ✓ | — |
| Grand staff / multi-staff systems | ✓ | ✓ | ✓ | — |
| Line breaking / justification | ● (manual) | ✓ | ✓ | — (single system) |
| Lyrics | ✓ | ✓ | ✓ | — |
| Chord symbols / annotations | ✓ | ✓ | ✓ | — |
| MusicXML import | — | ✓ | — | — |
| Text-notation import (ABC) | — | — | ✓ | ● (own DSL) |
| Playback cursor / time iterator | — | ✓ | ✓ | — |
| Audio synthesis | — | — | ✓ | — (**never**, by contract) |
| Tablature / percussion / bends | ✓ | ● | ● | — (out of scope) |
| Octave clefs (8va), C-clef family beyond alto/tenor | ✓ | ✓ | ● | — (four clefs) |
| Ornaments (trill, mordent, turn) | ✓ | ✓ | ✓ | — |
| Multi-measure rests | ✓ | ✓ | ✓ | — |
| Accidental stacking rules (dense chords) | ✓ | ✓ | ● | ● (naive columns) |

Permanently out regardless of parity: **audio** (HANDOVER: "partitura
renders; it never makes sound" — apps bring their own synth; we supply the
timing map instead). Out until a consumer asks: tablature, percussion
notation, guitar bends, microtonal accidentals.

## Plan

Ordering principle: model + layout foundations first (each later feature
rides on them), pedagogical value for KlangUniversum weighted over
engraving completeness, one system at a time.

### v0.3 — notation depth (single staff, single voice)

1. **Ties** — `NoteElement.tieToNext`; new `CurvePrimitive` (cubic Bézier
   in staff spaces) + painting; curves over/under by stem direction;
   across-barline support. Foundation for slurs.
2. **Slurs** — `Slur(startId, endId)` span list on `Score`; reuses
   `CurvePrimitive`; clearance above/below noteheads and stems.
3. **Tuplets** — `Tuplet` grouping wrapper (ratio, e.g. 3:2) in the
   measure model; exact `Fraction` math already copes; bracket + ratio
   digits; beaming inside tuplets.
4. **Articulations** — enum on `NoteElement` (staccato, tenuto, accent,
   marcato, fermata); SMuFL glyphs placed on the notehead side with
   stacking; hit regions extend.
5. **Dynamics + hairpins** — `DynamicElement` (p…ff text glyphs) and
   `Hairpin(startId, endId)` wedges below the staff.
6. **Grace notes** — small-glyph rendering (scaled font), acciaccatura
   slash, spacing before the host note.
7. **32nd/64th notes + breve** — extend `DurationBase`, flags/beam levels
   generalize (beam count = base.index − 2).
8. **Mid-score changes + repeats** — clef/key/time changes at measure
   boundaries (model: per-measure overrides), repeat barlines, voltas,
   courtesy naturals when the key changes.

### v0.4 — structure

9. **Multiple voices per staff** (two voices) — `Measure` gains voices;
   forced stem directions, rest displacement, second-interval collision
   between voices. Hardest single item; prerequisite for real grand-staff
   literature.
10. **Grand staff / systems** — `System` of staves with brace, connected
    barlines, cross-staff `Score` model (the layout engine already scopes
    per staff; a system layer composes staff layouts).
11. **Line breaking + justification** — break a long score into systems
    for a target width; stretch spacing to justify; `MultiSystemView`
    widget with per-system `ScoreLayout`s.
12. **Lyrics** — syllables attached to note ids, hyphens/extenders,
    skyline placement below the staff.
13. **Chord symbols / text annotations** — anchored text above the staff
    (also covers rehearsal marks and tempo text).

### v0.5 — interchange & time

14. **MusicXML import (subset)** — partwise, single/grand staff, the
    v0.3/0.4 feature set; maps to `Score`. The single biggest ecosystem
    unlock (OSMD's raison d'être).
15. **MusicXML export (same subset)** — round-trip tested against the
    importer.
16. **Playback cursor API** — pure-Dart time iterator: element ids ↔
    onset/duration in beats or seconds (given a tempo); drives
    `highlightedIds` for abcjs/OSMD-style follow-along **without audio**.
17. **Score transposition** — `Score.transposedBy(interval)` using the
    existing theory (new key signature, respelled accidentals).

### v0.6 — engraving polish

18. Proper accidental stacking (offset rules for dense chords), ornament
    glyphs (trill, mordent, turn), multi-measure rests, octave clefs
    (8va/8vb) and `ottava` brackets, whole-measure rest centering.

Each item lands like the clefs did: model + layout + unit tests in
`partitura_core`, painting + goldens + interaction tests in `partitura`,
gallery entry, CONTRACT.md/CHANGELOG updates, gates green, push.
