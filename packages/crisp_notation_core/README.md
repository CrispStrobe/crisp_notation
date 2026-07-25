# crisp_notation_core

Music theory model, score document model and **deterministic notation layout
engine** for the [crisp_notation](https://github.com/CrispStrobe/crisp_notation) music
notation libraries. Pure Dart, zero dependencies — usable on any Dart
platform, no Flutter required.

![Rendered by crisp_notation from a crisp_notation_core layout](https://raw.githubusercontent.com/CrispStrobe/crisp_notation/main/packages/crisp_notation_core/doc/hero.png)

For rendering and interaction in Flutter, use the
[`crisp_notation`](https://pub.dev/packages/crisp_notation) package, which builds on
this one.

Part of a three-package family: [crisp_notation_core](https://pub.dev/packages/crisp_notation_core) (pure-Dart engine) · [crisp_notation](https://pub.dev/packages/crisp_notation) (Flutter rendering) · [crisp_notation_cli](https://pub.dev/packages/crisp_notation_cli) (CLI).

## Install

```sh
dart pub add crisp_notation_core
```

## Quickstart

```dart
import 'package:crisp_notation_core/crisp_notation_core.dart';

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
| Theory | `Pitch` (MIDI, staff positions, transposition, microtones/cents, enharmonics), `Interval`, `NoteDuration` + exact `Fraction`, `KeySignature`, `TimeSignature`, `Scale`, `Triad`/`SeventhChord`, `Key` with `HarmonicFunction` (Tonika/Subdominante/Dominante). Analysis: chord identification (`identifyChord`), bidirectional Roman numerals, figured-bass → SATB realization, Krumhansl-Schmuckler key finding + modulation tracking, cadence/form detection, and post-tonal toolkits — **set theory** (normal/prime/Forte, interval-class vector), **twelve-tone** rows + matrix, **neo-Riemannian** P/L/R, and **voice-leading** rule checking |
| Model | `Score` / `Measure` / `NoteElement` / `RestElement`, value equality, `Score.simple` string DSL with auto element ids |
| Layout | `LayoutEngine` → `ScoreLayout`: flat glyph/line/beam/curve display list + per-element hit regions, all in staff spaces; clefs (treble/bass/alto/tenor + French-violin/soprano/mezzo/baritone/sub-bass + octave variants + percussion), key/time signatures (mid-score changes, common/cut, additive/composite meters with metric beam grouping, non-standard `KeySignature.custom`), stems, flags, multi-level + feathered beams, tuplets, ties (incl. laissez-vibrer), slurs, articulations, ornaments + extended trills, dynamics + hairpins, grace + cue notes, tremolo, ledger lines, accidentals with measure memory + quarter-tone microtones, dots, chords, rests, N voices, barlines (incl. tick/short/reverse-final), repeats, voltas, navigation, lyrics (elision), figured bass; notehead schemes (shape-note, pitch-name, solfège); **skyline collision avoidance** |
| Systems | `layoutStaffSystem` (N-staff systems with brackets), `layoutSystems` (line breaking), `layoutGrandStaffSystems` (wrapped grand staff), `layoutPages` (pagination with margins + vertical justification), and cross-staff onset-column gridding (`alignedColumns` / `gridAlign` — simultaneous notes align vertically across staves) |
| Interchange | MusicXML (+ compressed `.mxl`), MEI, Humdrum `**kern`, MIDI, MuseScore (`.mscx`/`.mscz`, incl. 1.x files), `.gp3`–`.gp5`/`.gpx`/`.gp`, GPIF, ABC, and LilyPond (`.ly`) readers **and** writers; **import-only**: GABC (Gregorian chant, `scoreFromGabc`), the muspy/MusicRender JSON of the PDMX corpus, and legacy Guitar-Pro binaries; **export-only**: braille music (`.brl`). All through the one `Score` model — `Slur` and `TupletSpan` round-trip through every note-carrying codec. The **LilyPond** importer is a real lexer→parser→AST pipeline (`\relative`, `<< >>`, variables, `\key`, `\partial`, tuplets, and `\addlyrics`/`\lyricsto`/`\lyricmode` verses; `\chordmode` tracks skipped). The **GPIF** codec is a high-fidelity tab round-trip: voice 2, tuplets, key signature (mid-score changes), dynamics, grace notes, articulations, lyrics, the file's string fingering (`TabVoicing`) and the tab techniques all survive; the binary `.gp3`–`.gp5` readers are **[covfuzz](https://pub.dev/packages/covfuzz)-hardened** (blind + coverage-guided) so malformed bytes reject with a `FormatException`, never a crash |
| SMuFL | `SmuflMetadata` (engraving defaults, glyph boxes, stem anchors parsed from a SMuFL font's metadata JSON), glyph-name constants |

Still **out of scope** (see [PLAN.md](https://github.com/CrispStrobe/crisp_notation/blob/main/PLAN.md) for the roadmap):
page frames/spacers and a physical mm/spatium scaling unit (planned); audio
(never).

## WebAssembly

`crisp_notation_core` is pure Dart with no `dart:io`/`dart:html`/`dart:ffi`/
`dart:isolate` (only `dart:typed_data`), so the theory, layout and interchange
core compiles to and runs as a WasmGC module via `dart compile wasm`
(dart2wasm) — in the browser or any WASM host. See
[`example/wasm/`](example/wasm/) for a runnable smoke test (verified under Node)
and an in-browser JS-interop demo. The full interchange surface is web-safe —
including the `.gp`/`.gpx`/`.mscz` ZIP/BCFS **container reading and writing**,
which use pure-Dart [`inflate`](lib/src/interchange/inflate.dart) /
[`deflate`](lib/src/interchange/deflate.dart) (RFC 1951) instead of `dart:io`,
so real compressed archives both load and save in the browser. Only file I/O
itself stays in `crisp_notation_cli`'s CLI. For the Flutter renderer, use Flutter
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
[docs/CONTRACT.md](https://github.com/CrispStrobe/crisp_notation/blob/main/docs/CONTRACT.md).

## License

[MIT](LICENSE).
