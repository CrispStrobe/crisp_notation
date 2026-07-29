// A barre must be DRAWN, not merely stored.
//
// The import work that preceded this preserved 1,013 real barres and nothing
// put a mark on the page — which is the failure this project keeps meeting:
// data correct, effect invisible. `CIII` is the classical-guitar convention
// (C for *ceja* / *barré*), and it is what a player reads over the chord rather
// than a repeated "1" among the fingering digits.
import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score _chord({TabBarre? barre}) => Score(
  clef: Clef.treble,
  measures: [
    Measure([
      NoteElement(
        pitches: [Pitch.fromMidi(53), Pitch.fromMidi(60)],
        duration: NoteDuration.quarter,
        id: 'n0',
      ),
      const RestElement(NoteDuration.quarter, id: 'r0'),
    ]),
  ],
  tabBarres: [if (barre != null) barre],
);

List<String> _texts(Score score) => const LayoutEngine()
    .layout(score, settings)
    .primitives
    .whereType<TextPrimitive>()
    .map((t) => t.text)
    .toList();

void main() {
  setUpAll(() {
    final source = File(
      '../crisp_notation/assets/smufl/bravura_metadata.json',
    ).readAsStringSync();
    metadata = SmuflMetadata.fromJson(
      jsonDecode(source) as Map<String, Object?>,
    );
    settings = LayoutSettings(metadata: metadata);
  });

  test('a barre is drawn as its fret in Roman numerals', () {
    expect(_texts(_chord(barre: const TabBarre('n0', 3))), contains('CIII'));
  });

  test('the numeral is right across the neck', () {
    for (final (fret, roman) in const [
      (1, 'CI'),
      (2, 'CII'),
      (4, 'CIV'),
      (5, 'CV'),
      (7, 'CVII'),
      (9, 'CIX'),
      (10, 'CX'),
      (12, 'CXII'),
    ]) {
      expect(
        _texts(_chord(barre: TabBarre('n0', fret))),
        contains(roman),
        reason: 'fret $fret should print $roman',
      );
    }
  });

  test('no barre, no mark', () {
    expect(
      _texts(_chord()).where((t) => t.startsWith('C')),
      isEmpty,
      reason: 'a score without a barre must not gain one',
    );
  });

  test(
    'a barre on a note this layout does not contain is skipped, not fatal',
    () {
      // Multi-system layout splits a score, so a barre can legitimately point at
      // a note that is not in the system being laid out. A missing mark is
      // acceptable; failing the whole page is not.
      expect(
        () => _texts(_chord(barre: const TabBarre('nowhere', 5))),
        returnsNormally,
      );
    },
  );

  test('a partial barre is NOT drawn as a half-barre', () {
    // TabBarre.lowestString is Guitar Pro's value preserved verbatim; inferring
    // "half barre" from it would be the reinterpretation the model refuses to
    // make. It prints the same mark either way.
    expect(
      _texts(_chord(barre: const TabBarre('n0', 3, lowestString: 1))),
      contains('CIII'),
    );
  });
}
