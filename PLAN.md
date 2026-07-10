# partitura — implementation plan (living tracker)

Working checklist for the feature-parity plan. Analysis and per-item
design notes live in [docs/ROADMAP.md](docs/ROADMAP.md); check items off
here as they land. Every item ships the full pipeline: model + layout +
unit tests in `partitura_core`, painting + goldens + interaction tests in
`partitura`, gallery entry where visual, CONTRACT/CHANGELOG updates,
gates green (`dart format`, analyze zero issues, all tests), push.

## Done

- [x] v0.1 — M1..M5 per HANDOVER.md (theory, layout rules 1–14,
      StaffView, InteractiveStaff, release polish)
- [x] v0.2 — alto + tenor clefs

## v0.3 — notation depth (single staff, single voice)

- [x] 0.3.1 Ties (`tieToNext`, `CurvePrimitive` foundation, DSL `~`)
- [x] 0.3.2 Slurs (`Slur(startId, endId)` spans, curve clearance)
- [x] 0.3.3 Tuplets (measure-level spans, ratio bracket + digits,
      exact `Fraction` math, beaming inside)
- [x] 0.3.4 Articulations (staccato, tenuto, accent, marcato, fermata)
- [x] 0.3.5 Dynamics (pp…ff glyphs) + hairpins (cresc/dim wedges)
- [x] 0.3.6 Grace notes (scaled glyphs, acciaccatura slash)
- [x] 0.3.7 32nd/64th notes + breve (flags, multi-level beams, DSL
      letters `t`, `x`, `b`)
- [x] 0.3.8 Mid-score clef/key/time changes (courtesy naturals),
      repeat barlines, voltas

## v0.4 — structure

- [ ] 0.4.1 Two voices per staff (forced stems, rest displacement,
      cross-voice seconds)
- [ ] 0.4.2 Grand staff / systems (brace, connected barlines)
- [ ] 0.4.3 Line breaking + justification (`MultiSystemView`)
- [ ] 0.4.4 Lyrics (syllables, hyphens, extenders)
- [ ] 0.4.5 Chord symbols / text annotations (covers rehearsal + tempo
      marks)

## v0.5 — interchange & time

- [ ] 0.5.1 MusicXML import (subset covering v0.3/0.4)
- [ ] 0.5.2 MusicXML export (round-trip tested)
- [ ] 0.5.3 Playback-cursor API (time iterator → `highlightedIds`;
      **no audio, ever** — apps bring their own synth)
- [ ] 0.5.4 `Score.transposedBy(interval)`

## v0.6 — engraving polish

- [ ] 0.6.1 Accidental stacking rules for dense chords
- [ ] 0.6.2 Ornaments (trill, mordent, turn)
- [ ] 0.6.3 Multi-measure rests
- [ ] 0.6.4 Octave clefs + ottava brackets

## Permanently out (per HANDOVER contract / until explicitly requested)

- Audio synthesis or playback of any kind
- Tablature, percussion notation, guitar bends, microtonal accidentals
