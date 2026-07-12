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
| Layout | `LayoutEngine` → `ScoreLayout`: flat glyph/line/beam/curve display list + per-element hit regions, all in staff spaces; clefs (treble/bass/alto/tenor + octave variants + percussion), key/time signatures (incl. mid-score changes and common/cut symbols), stems, flags, multi-level + feathered beams, tuplets, ties, slurs, articulations, ornaments, dynamics + hairpins, grace notes, tremolo, ledger lines, accidentals with measure memory, dots, chords, rests, two voices, barlines, repeats, voltas, navigation, lyrics, figured bass |
| Systems | `layoutStaffSystem` (N-staff systems with brackets), `layoutSystems` (line breaking), `layoutPages` (pagination with margins + vertical justification) |
| Interchange | MusicXML (+ compressed `.mxl`), MEI, Humdrum `**kern`, MIDI, MuseScore (`.mscx`), `.gp3`–`.gp5`/`.gpx`/`.gp`, GPIF and ABC readers/writers (+ LilyPond `.ly` export), all through the one `Score` model |
| SMuFL | `SmuflMetadata` (engraving defaults, glyph boxes, stem anchors parsed from a SMuFL font's metadata JSON), glyph-name constants |

Still **out of scope** (see [PLAN.md](../../PLAN.md) for the roadmap):
full-system skyline collision avoidance, page frames/spacers, voices 3–4,
microtones (all planned); audio (never).

## WebAssembly

`partitura_core` is pure Dart with no `dart:io`/`dart:html`/`dart:ffi`/
`dart:isolate` (only `dart:typed_data`), so the theory, layout and interchange
core compiles to and runs as a WasmGC module via `dart compile wasm`
(dart2wasm) — in the browser or any WASM host. See
[`example/wasm/`](example/wasm/) for a runnable smoke test (verified under Node)
and an in-browser JS-interop demo. The full interchange surface is web-safe —
including the `.gp`/`.gpx`/`.mscz` ZIP/BCFS **container reading and writing**,
which use pure-Dart [`inflate`](lib/src/interchange/inflate.dart) /
[`deflate`](lib/src/interchange/deflate.dart) (RFC 1951) instead of `dart:io`,
so real compressed archives both load and save in the browser. Only file I/O
itself stays in `partitura_cli`'s CLI. For the Flutter renderer, use Flutter
web's WasmGC / `skwasm` renderer.

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
