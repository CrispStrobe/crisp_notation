# crisp_notation

Music notation rendering for Flutter with **first-class interactivity** —
staves, notes, chords, beams, rests and signatures, where every element is
identifiable, hit-testable, highlightable and draggable. Builds on
[`crisp_notation_core`](https://pub.dev/packages/crisp_notation_core) (re-exported)
and bundles the Bravura SMuFL font.

Part of a three-package family: [crisp_notation_core](https://pub.dev/packages/crisp_notation_core) (pure-Dart engine) · [crisp_notation](https://pub.dev/packages/crisp_notation) (Flutter rendering) · [crisp_notation_cli](https://pub.dev/packages/crisp_notation_cli) (CLI).

![crisp_notation rendering](https://raw.githubusercontent.com/CrispStrobe/crisp_notation/main/packages/crisp_notation/doc/hero.png)

Made for education apps — ear training, theory drills, note-reading games —
where static SVG renderers fall short.

## Install

```sh
flutter pub add crisp_notation
```

## Quickstart

```dart
import 'package:flutter/material.dart';
import 'package:crisp_notation/crisp_notation.dart';

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
  theme: CrispNotationTheme.kids,            // large hit targets, bold lines
  highlightedIds: selectedIds,           // repaint-only, never relayouts
  onElementTap: (id) => toggle(id),      // tap a note
  onStaffTap: (target) =>                // tap/drop on empty staff,
      add(target.pitchFor(Clef.treble)), // quantized to a line/space
)
```

`MultiSystemView` wraps a long score into width-fitting systems, and
`InteractiveGrandStaffView` does the same for a two-staff keyboard system —
both interactive, both with cross-staff onset gridding.

For player / editor apps, a `ScoreEditorController` drives the view imperatively:

```dart
final controller = ScoreEditorController();
controller.setLoop('e10', 'e18');                          // loop band
controller.mark('e5', const EditorMark(Colors.red,        // flag a wrong note
    message: 'out of key'));
controller.attachViewport(                                 // app owns the scroll
    scrollController: myScroll, rectOfElement: () => render.rectOfElement);
await controller.scrollToNote('e42');                      // reveal a note
```

## Feature matrix

| In (v0.4) | Out (planned / never) |
|---|---|
| Single staff, N-staff systems, grand staff; automatic line-breaking + pagination | Page frames / spacers (in progress) |
| All clefs (treble/bass/alto/tenor + French-violin, soprano, mezzo, baritone, sub-bass, octave variants, percussion) | Physical mm / spatium scaling unit (in progress) |
| Notes/rests breve–64th, 2 dots, chords, multi-level + feathered beaming, tuplets | **Audio synthesis (never)** |
| Accidentals incl. measure memory + quarter-tone microtones; non-standard key signatures | |
| Key/time signatures −7..+7, mid-score changes, additive/composite meters | |
| Ties (incl. laissez-vibrer), slurs, articulations, ornaments, extended trills, dynamics + hairpins, grace + cue notes | |
| Skyline collision avoidance; cross-staff onset-column gridding | |
| Lyrics (elision), figured bass, chord symbols, jazz articulations | |
| Shape-note / pitch-name / solfège noteheads; note-name & beat-count teaching overlays | |
| Guitar **tablature** with full techniques | |
| Repeats, voltas, D.C./D.S./coda navigation; transposing + concert-pitch toggle | |
| Element tap → id, staff tap → `StaffTarget`, hover caret + ghost drag, marquee selection, kid mode | |
| Editor overlays (`errorOverlay`, `loopRange`), `rectOfElement` + `ScoreEditorController` | |
| Multi-part interactive view (`InteractiveMultiPartView`, per-part tap/hover), `TranspositionController`, drill scoring (`evaluateDrill`) | |
| Fretboard & piano-keyboard diagrams; pluggable SMuFL fonts (Bravura bundled; Petaluma/Leland/Leipzig descriptors) | |

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
[docs/CONTRACT.md](https://github.com/CrispStrobe/crisp_notation/blob/main/docs/CONTRACT.md).

## License

Code: [MIT](LICENSE). The bundled
[Bravura](https://github.com/steinbergmedia/bravura) font is © Steinberg
Media Technologies GmbH, licensed under the SIL Open Font License 1.1 —
see [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt). The font is neither
converted, subset nor renamed.
