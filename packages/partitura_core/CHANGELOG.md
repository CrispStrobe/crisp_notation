# Changelog

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
