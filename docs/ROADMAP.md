# partitura — feature-parity roadmap

Gap analysis against the three JavaScript incumbents — **VexFlow** (the
low-level engraving library), **OpenSheetMusicDisplay/OSMD** (MusicXML
renderer built on VexFlow) and **abcjs** (ABC-notation renderer) — and the
plan to close the gaps that matter. Written 2026-07-10 at v0.2.

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
