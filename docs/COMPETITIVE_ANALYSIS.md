# partitura — wider-ecosystem competitive scan (2026-07-11)

`docs/ROADMAP.md` compares partitura against the three JS incumbents
(**VexFlow 5 / OSMD / abcjs**). This document widens the lens to the rest of
the ecosystem, from an 8-way parallel research sweep, to find the **delta**:
features beyond that incumbent baseline *and* beyond what partitura does
today. It is a menu, not a commitment — the actionable plan stays in
`ROADMAP.md`/`PLAN.md`.

Apps surveyed, by axis:

- **Pro-editor engraving ceiling:** MuseScore 4, LilyPond, Dorico
- **Peer rendering libraries:** Verovio (MEI/SVG), alphaTab (notation + tab)
- **Theory/analysis:** music21
- **Interaction/education apps:** Soundslice, Flat.io, Noteflight
- **Tablature depth:** Guitar Pro / Songsterr / TuxGuitar

Framing: partitura is an **interactive Flutter/Dart rendering library with a
pedagogy theory core**, no audio synthesis (a timing map instead). So the
delta splits three ways — **[R]** engraving/notation to add, **[MOAT]**
interaction/theory that leans into partitura's differentiation, and **[OUT]**
editor/backend/audio that is deliberately not partitura's job.

---

## A. Engraving quality — the biggest "looks professional" gap  [R]

All three pro editors (MuseScore, LilyPond, Dorico) do these automatically;
partitura does not. This tier changes how *everything already rendered* looks.

1. **Optical horizontal spacing** — duration-logarithmic "springs-and-rods"
   spacing, not linear/beat spacing. *The single biggest quality lever.*
   (LilyPond `SpacingSpanner`; Dorico/MuseScore auto.) partitura currently
   spaces roughly linearly.
2. **Skyline-based global collision avoidance** — every glyph has a skyline;
   accidentals, articulations, dynamics, lyrics, slurs placed to avoid
   overlap across the whole system. (LilyPond, Dorico, MuseScore.)
3. **Pluggable SMuFL fonts + font-driven engraving metrics** — Leland,
   Bravura, Petaluma (jazz), Gonville, Emmentaler; line thicknesses read from
   the font's own metadata JSON. (MuseScore, Verovio, VexFlow.) partitura
   bundles only Bravura but *already abstracts glyph names*, so this is mostly
   asset + config.
4. **Advanced beaming** — feathered/fanned beams (accel./rall.), beam
   subdivision, custom slopes / independent beam-end heights, beams over
   rests, **cross-measure** and **cross-staff** beaming. (LilyPond, Dorico,
   MuseScore.)
5. **Cross-staff notes / stems / beams** — a chord or beam spanning both
   staves of a grand staff. Essential for keyboard music. (all three + music21
   spanners.)

## B. Structural / score-level — the "viewer → conductor's score" jump  [R]
Overlaps roadmap item **0.7.3 (N-staff systems)**; this is the fuller menu.

6. **3+ staff systems** with **nested brackets/braces + barline grouping**.
   (all pro editors; partitura's `GrandStaff` is exactly 2.)
7. **Hide empty staves / cutaway / ossia / divisi / extra staves** — dynamic
   staff count. Cutaway + coordination lines and condensing are Dorico's
   flagship; hide-empty + ossia are in MuseScore + LilyPond too.
8. **Condensing** (Dorico) — auto-reduce many players onto shared staves with
   "a2 / 1. / 2." labels for the score while parts stay split. A *view*
   transform a semantic model can support.
9. **Page-layout engine** — spatium unit, margins, vertical justification
   (staff/system distances, page-fill), spacers, explicit page/section
   breaks, system locks, layout stretch; plus **frames** (vertical/text/
   horizontal/image, metadata host). (MuseScore, LilyPond page-turn-aware
   breaking, Dorico flows/frames/casting-off.) partitura has line-breaking
   only.
10. **Pickup/anacrusis + actual-vs-nominal measure duration + irregular
    measures** — *foundational*; a large fraction of real pieces need it.
    (MuseScore, LilyPond, Dorico.)
11. **Linked parts + transposing instruments + concert-pitch toggle.**
12. **Measure-numbering system** (per-system/interval, per-measure overrides,
    section reset) + **measure-repeat signs** (1/2/4-bar).

## C. Notation breadth — individual objects still missing  [R]

13. **Noteheads** — type set (x, diamond/harmonic, slash, triangle, circled,
    etc.), **schemes** (shape-note Sacred Harp/Aikin, pitch-name, solfège),
    **cue/small** notes, **colored + out-of-range** auto-coloring. (MuseScore
    9 schemes; LilyPond shape/easy heads.) partitura has only default heads.
14. **More clefs** — French violin, soprano/mezzo/baritone/subbass (rare C/F
    positions), percussion, TAB. (MuseScore, LilyPond.) partitura has 4 +
    octave variants.
15. **Custom / atonal key signatures + cancelling-naturals policy.**
16. **Time signatures** — Common (C) / Cut (¢) symbols, additive/composite
    (3+2+3/8), **local per-staff** meters, interchangeable, polymetric.
17. **Barlines** — dashed/dotted/tick/short/reverse-final + **custom-span /
    Mensurstrich** across staves. (MuseScore, LilyPond user-defined barlines.)
18. **Lines/spanners** — laissez-vibrer ties, **palm-mute / let-ring /
    vibrato** lines, **trill extension line** + baroque prall/mordent
    variants, portamento, fall/doit/plop/scoop, **ambitus**, system dividers.
19. **Lyrics** — multiple verses, melisma extenders, elision slurs,
    hyphenation. partitura has a single verse.
20. **Voices 3 & 4** per staff + rest-merging. partitura has 2.
21. **Figured bass** — stacked figures, accidentals, slashes, continuation
    lines. (LilyPond, Dorico semantic, MuseScore font, music21 realization.)
    *Note: none of the three JS incumbents do it — it's a pro-editor delta.*
22. **Microtonal accidentals + remappable alteration glyphs** — quarter tones
    and Arabic/Turkish/Persian koma systems. (LilyPond world-music, music21
    Scala.) *Contract currently lists microtonal as out.*
23. **Jazz articulations** (scoops/falls/doits/plops/flips/smears). (Dorico
    ornaments, MuseScore, VexFlow.)
24. Small: 128th notes + double-dots (MuseScore floor; partitura stops at
    64th).

## D. Guitar tablature — the v0.8 milestone, now with an exhaustive spec  [R/T]

alphaTab (the closest architectural peer — a cross-platform rendering lib
with a Flutter port requested) is the deepest open-source reference, and the
Guitar Pro binary format gives ready-to-adopt enum values. Consolidated
technique set (feeds `docs/HANDOVER_V08_TABLATURE.md` §0.8.3):

- **Fundamentals:** fret-on-string, open `0`, stacked chords, string count
  3–10, per-string tuning, capo, displayTranspose; tab staff variants
  (simple/common/full; numbers vs French letters).
- **Bends:** 8-type taxonomy (bend, release, bend-release, prebend,
  prebend-bend, prebend-release, hold, custom) with **exact quarter-tone
  point grids** and up/gradual/fast display styles. (alphaTab `be`; GP enum
  0–5.)
- **Whammy/tremolo bar:** *separate system* from string bends — dive, dip,
  predive, hold + point grids. (alphaTab `tbe`; GP dip/dive/return.)
- **Slides:** 8 variants — legato, shift, in-from-below/above,
  out-up/down, pick-slide up/down; combinable.
- **Legato:** hammer-on / pull-off (chained), tapping (beat-level +
  left-hand-tapped note-level).
- **Harmonics:** full 6-way — natural, artificial, pinch, tap, semi,
  feedback — with a fret→pitch-offset table. (alphaTab; GP enum 1–5.)
- **Vibrato:** slight / wide, note- and beat-level.
- **Muting/ringing:** dead note `X`, ghost, palm-mute (spanning bracket),
  let-ring, staccato, accent/heavy-accent/tenuto, dead-slap.
- **Bass:** slap / pop / dead-slap.
- **Strumming/flamenco:** brush up/down, arpeggio up/down, pick-stroke,
  **18 named rasgueado patterns**, golpe (finger/thumb), wah open/close.
- **Tremolo picking** (1–5 marks, buzz-roll) + **trill** (fret + speed).
- **Fingering:** left-hand + right-hand PIMA, circled string numbers.
- **Chord/fretboard diagrams** — finger dots, barré, open/muted markers,
  base-fret, per-instrument sets, auto-simplest-shape (Dorico), diagram
  legend frame (MuseScore).
- **Slash/rhythm-in-tab** mode; rhythm stems below tab (Songsterr).
- **I/O:** Guitar Pro import gp3/4/5/gpx/gp — highest-value tab unlock;
  adopt the documented note/beat effect bitmasks for clean round-trip.
- Other-instrument tabs: bass 4/5/6, 7/8-string, banjo, ukulele, mandolin,
  lute (French/German/Italian).

## E. Interchange / formats  [R]

25. **MIDI file export** off the existing playback timeline — contract-safe
    (no audio). Already roadmap **0.7.5**. (abcjs, Verovio, everyone.)
26. **SVG / PNG / PDF export** — rasterization is easy from Flutter
    (`PictureRecorder`); SVG is real work. (MuseScore, OSMD, Verovio.)
27. **Wider import** — MEI, Guitar Pro, MIDI, ABC, Capella; Verovio adds
    Humdrum/PAE/DARMS/EsAC/MuseData for scholarly corpora.
28. **Repeat *unfolding*** (Verovio expansionmap) — linearize
    D.C./D.S./voltas into performance order. *This is exactly the playback
    jump-execution deferred in 0.7.1* — Verovio shows the clean model
    (unfold only for time-based outputs, clone IDs with `-rend2` suffixes).
29. **Timemap JSON** (Verovio) — event → ms/quarter-note map; the same idea
    as partitura's playback cursor, worth matching as an export.
30. **Braille music export/rendering** (MuseScore `.brf`) — rare in JS/Dart
    libs; a real accessibility differentiator.

## F. Interaction / education — partitura's MOAT to widen  [MOAT]

Competitors' *renderers* mostly don't own this; the *apps* (Soundslice, Flat,
Noteflight) do, at the app layer. partitura can offer it as a rendering
substrate. Highest differentiation per unit effort.

31. **Instrument visualizers synced to the cursor** — piano keyboard (L/R
    hand), guitar fretboard, that light up as the cursor moves. Soundslice's
    signature; pairs perfectly with partitura's no-audio cursor. *Top pick.*
32. **Note-name & rhythm-count overlays** — letter above notehead, beat number
    above note. Cheap, ubiquitous in education (Soundslice), high pedagogy
    value.
33. **Drag-to-loop with snap-to-note/rest/barline + section looping** — the
    core practice primitive; builds on existing measure selection.
34. **Error/annotation overlay** — paint specific notes correct/wrong/flagged
    (the rendering half of Noteflight SoundCheck + MIDI assessment). Lets
    ear-training/assessment apps bring their own analysis and ask partitura to
    show results.
35. **Tempo/speed map the cursor follows** — extend the cursor API from a
    fixed clock to a warped/variable tempo (slowdown, speed-training,
    follow-a-recording). alphaTab's **External Audio Cursor / sync-point API**
    is the exact pattern for partitura's timing-map philosophy.
36. **Concert-pitch ↔ written-pitch toggle + live transposition UI** —
    partitura already has `Score.transposedBy`; this is the interaction
    wrapper. (Noteflight.)
37. **MIDI-input highlighting** — highlight played-vs-expected for
    play-the-right-note games. (Flat, Noteflight.)
38. **Rich imperative control/embed API** — Flat's 60+-method typed SDK
    (seek-to-note, set-loop, overlay-annotations, toggle-part, set-visualizer)
    is the bar for "apps drive the renderer." partitura's Dart API should
    expose an equivalently rich surface.
39. **Accessible + sonified navigable score** — largely *unserved* across all
    interactive players; a genuine market gap, and a natural fit for Flutter
    `Semantics`.

## G. Theory / analysis — the pedagogy moat, from music21  [MOAT]

No renderer (VexFlow/OSMD/abcjs/Verovio/alphaTab) does any of this; partitura
already has `Key.triadFor`, scales, intervals, exact durations to build on.

40. **Bidirectional Roman-numeral analysis** — infer RN + inversion +
    secondary dominants from a chord in a key (music21
    `romanNumeralFromChord`), and render RN + figured-bass symbols. *Highest
    pedagogy payoff.*
41. **Part-writing / voice-leading checker** — flag parallel fifths/octaves,
    hidden intervals, voice crossing/overlap, spacing. *The* teaching-library
    differentiator; nothing in the renderer space has it.
42. **Key-finding** (Krumhansl-Schmuckler + windowed local key).
43. **Chord identification from a pitch set** (root/inversion/quality,
    seventh/aug-sixth) — the inverse of partitura's triad construction.
44. **Post-tonal set theory** — normal order, prime form, Forte number,
    interval-class vector, Z-relation. Self-contained; a whole 20th-c. module.
45. **Figured-bass realization** into SATB with a voice-leading rule engine
    (pairs with #41).
46. **`beatStrength` / metrical-accent hierarchy** on the exact-duration core
    — also improves auto-beaming.
47. Smaller: scale derivation (rank matching scales for a pitch set),
    Neo-Riemannian L/P/R transforms, twelve-tone matrix, RomanText I/O for
    interop with the music21/analysis-corpus ecosystem.

---

## Prioritized recommendation

Weighting by (value to partitura's identity) ÷ (effort), after the in-flight
v0.7.2 → v0.8 plan:

- **Tier 1 — transformative, do next.**
  - **A1 Optical spacing + A2 skyline collision avoidance.** Biggest
    "looks engraved" lever; improves every existing feature at once.
  - **A3 Pluggable SMuFL fonts.** Cheap given the existing glyph abstraction;
    unlocks the jazz/handwritten look.
  - **B (0.7.3) N-staff systems + hide-empty/ossia + cross-staff.** Unblocks
    real multi-part repertoire; prerequisite for tab-with-notation (0.8.2).
  - **B10 pickup/anacrusis + actual-vs-nominal measure duration.**
    Foundational; unblocks a huge fraction of real pieces.

- **Tier 2 — lean into the moat (where partitura *wins*).**
  - **F31/F32/F33/F34 interaction:** instrument visualizers, note-name/count
    overlays, drag-to-loop, error overlay — all ride the existing cursor +
    selection, no audio needed. This is the differentiation competitors'
    renderers can't match.
  - **G40/G41 theory:** Roman-numeral inference + voice-leading checker.
    Unique in the rendering-library space; extends the existing theory core.

- **Tier 3 — notation breadth (steady grind, section C).**
  Noteheads (types+cue), more clefs, figured bass, multi-verse lyrics, voices
  3–4, extra barlines/lines (laissez-vibrer, palm-mute/let-ring/vibrato),
  jazz articulations, microtonal (needs the contract note lifted).

- **Tier 4 — v0.8 guitar tablature.** Already planned; section D is the
  exhaustive spec, adopt alphaTab's model + Guitar Pro enums.

- **Tier 5 — interchange.** MIDI export (0.7.5), SVG/PNG export, wider import
  (MEI/GP/MIDI/ABC), repeat unfolding (closes the deferred nav-mark playback
  jumps), braille.

## Deliberately OUT of scope (do not chase)

Audio synthesis/playback and mixers; note-input/editing mechanics
(caret, insert, force-duration, popovers); collaboration backends, LMS/grade
sync, content libraries, cloud publishing, version history; VST/expression
maps; plugin frameworks. partitura's play is to be the best **interactive
rendering + theory substrate** those apps are built on — not to become an
editor or a DAW.
