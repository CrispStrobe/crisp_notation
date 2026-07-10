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

| In (v0.1) | Out (v0.x non-goals) |
|---|---|
| Single staff, treble + bass clefs | Grand staff / multiple staves |
| Notes/rests whole–16th, up to 2 dots | Tuplets, grace notes |
| Accidentals incl. measure memory | Slurs, ties, articulations, dynamics |
| Key signatures −7..+7, time signatures | Lyrics, multi-voice |
| Chords (shared stem, seconds handling) | Line breaking / justification |
| Beat-based beaming incl. 16th beams | MusicXML import/export |
| Element tap → id, staff tap → `StaffTarget` | Audio/playback (never) |
| Ghost-note drag preview, kid mode | Transposing instruments, tablature |

## Notes

- **Sizing**: pass `staffSpace` (px per staff space) for a fixed size, or
  omit it to fit the available width.
- **Goldens**: this package's golden tests were generated on macOS; text
  rasterization differs across platforms, so run/regenerate them on macOS
  (`flutter test --update-goldens`).
- **Example**: `example/` ships a gallery of the golden corpus and an
  interactive place-a-note demo (macOS, web, iOS).

## License

Code: [MIT](LICENSE). The bundled
[Bravura](https://github.com/steinbergmedia/bravura) font is © Steinberg
Media Technologies GmbH, licensed under the SIL Open Font License 1.1 —
see [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt). The font is neither
converted, subset nor renamed.
