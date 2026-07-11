# partitura

Music notation rendering for Flutter with **first-class interactivity** —
staves, notes, chords, beams, rests and signatures, where every element is
identifiable, hit-testable, highlightable and draggable. Builds on
[`partitura_core`](https://pub.dev/packages/partitura_core) (re-exported)
and bundles the Bravura SMuFL font.

![partitura rendering](https://raw.githubusercontent.com/CrispStrobe/partitura/main/packages/partitura/doc/hero.png)

Made for education apps — ear training, theory drills, note-reading games —
where static SVG renderers fall short.

## Quickstart

```dart
import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Bravura.load(); // font metadata; one-time
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(
        child: StaffView(
          score: Score.simple(
            timeSignature: TimeSignature.fourFour,
            notes: 'g4:e a4 b4 c5 d5:q d5 | e5:e e5 e5 e5 d5:h',
          ),
        ),
      ),
    ),
  ));
}
```

Interaction is one widget swap away:

```dart
InteractiveStaff(
  score: score,
  theme: PartituraTheme.kids,            // large hit targets, bold lines
  highlightedIds: selectedIds,           // repaint-only, never relayouts
  onElementTap: (id) => toggle(id),      // tap a note
  onStaffTap: (target) =>                // tap/drop on empty staff,
      add(target.pitchFor(Clef.treble)), // quantized to a line/space
)
```

## Feature matrix

| In (v0.3) | Out (planned / never) |
|---|---|
| Single staff; treble, bass, alto, tenor clefs (+ mid-score changes) | Grand staff / systems (v0.4) |
| Notes/rests breve–64th, up to 2 dots | Multi-voice (v0.4, in progress) |
| Accidentals incl. measure memory, cancellation naturals | Line breaking / justification (v0.4) |
| Key/time signatures −7..+7 incl. mid-score changes | Lyrics, chord symbols (v0.4) |
| Chords, multi-level beaming, tuplets | MusicXML import/export (v0.5) |
| Ties, slurs, articulations, dynamics + hairpins, grace notes | Playback cursor API (v0.5; **audio: never**) |
| Repeats & voltas | Ornaments, multi-measure rests, 8va (v0.6) |
| Element tap → id, staff tap → `StaffTarget`, ghost drag, kid mode | Transposing instruments, tablature |

## Notes

- **Sizing**: pass `staffSpace` (px per staff space) for a fixed size, or
  omit it to fit the available width.
- **Goldens**: this package's golden tests were generated on macOS; text
  rasterization differs across platforms, so run/regenerate them on macOS
  (`flutter test --update-goldens`).
- **Example**: `example/` ships a gallery of the golden corpus and an
  interactive place-a-note demo (macOS, web, iOS).

## Contract

The implemented feature set, binding conventions and API guarantees are
documented in
[docs/CONTRACT.md](https://github.com/CrispStrobe/partitura/blob/main/docs/CONTRACT.md).

## License

Code: [MIT](LICENSE). The bundled
[Bravura](https://github.com/steinbergmedia/bravura) font is © Steinberg
Media Technologies GmbH, licensed under the SIL Open Font License 1.1 —
see [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt). The font is neither
converted, subset nor renamed.
