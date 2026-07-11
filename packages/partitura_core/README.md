# partitura_core

Music theory model, score document model and **deterministic notation layout
engine** for the [partitura](https://github.com/CrispStrobe/partitura) music
notation libraries. Pure Dart, zero dependencies — usable on any Dart
platform, no Flutter required.

![Rendered by partitura from a partitura_core layout](https://raw.githubusercontent.com/CrispStrobe/partitura/main/packages/partitura_core/doc/hero.png)

For rendering and interaction in Flutter, use the
[`partitura`](https://pub.dev/packages/partitura) package, which builds on
this one.

## Quickstart

```dart
import 'package:partitura_core/partitura_core.dart';

void main() {
  // Theory: pitches, keys, scales, triads, functional harmony.
  const key = Key.major(Pitch(Step.d));
  print(key.signature.alteredSteps);              // [Step.f, Step.c]
  print(key.triadFor(HarmonicFunction.dominant)); // Triad(A4 major)
  print(const Scale(Pitch(Step.a), ScaleType.harmonicMinor).pitches);

  // A score from the terse DSL (measures split on '|', chords with '+').
  final score = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: 'c4:q e4 g4 c5 | c4+e4+g4:h r:h',
  );
  print(score.measures.first.totalDuration); // 1/1 — fills the 4/4 measure
}
```

## What's inside

| Layer | Contents |
|---|---|
| Theory | `Pitch` (MIDI, staff positions, transposition, enharmonics), `Interval`, `NoteDuration` + exact `Fraction`, `KeySignature`, `TimeSignature`, `Scale`, `Triad`, `Key` with `HarmonicFunction` (Tonika/Subdominante/Dominante) |
| Model | `Score` / `Measure` / `NoteElement` / `RestElement`, value equality, `Score.simple` string DSL with auto element ids |
| Layout | `LayoutEngine` → `ScoreLayout`: flat glyph/line/beam/curve display list + per-element hit regions, all in staff spaces; four clefs, key/time signatures incl. mid-score changes, stems, flags, multi-level beams, tuplets, ties, slurs, articulations, dynamics + hairpins, grace notes, ledger lines, accidentals with measure memory, dots, chords, rests, barlines, repeats, voltas |
| SMuFL | `SmuflMetadata` (engraving defaults, glyph boxes, stem anchors parsed from a SMuFL font's metadata JSON), glyph-name constants |

Still **out of scope** (see [PLAN.md](../../PLAN.md) for the roadmap):
grand staff, line breaking, lyrics, MusicXML (all planned); audio
(never). Two-voice support is in progress.

## Conventions (binding)

- Scientific pitch notation, middle C = C4 = MIDI 60.
- `Pitch.staffPosition(clef)`: 0 = bottom staff line, +1 per line/space
  upward (bottom lines: treble E4, bass G2, alto F3, tenor D3).
- Layout coordinates in staff spaces, origin at the staff's top line ∩ left
  edge, y grows downward.

## Contract

The implemented feature set, binding conventions and API guarantees are
documented in
[docs/CONTRACT.md](https://github.com/CrispStrobe/partitura/blob/main/docs/CONTRACT.md).

## License

[MIT](LICENSE).
