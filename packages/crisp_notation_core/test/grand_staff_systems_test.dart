import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Editor contract C5 (core): a grand staff wrapped into multiple systems.
late final LayoutSettings settings;

GrandStaff eightBarPiano() => GrandStaff(
      upper: Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes:
            'c5:q d5 e5 f5 | g5:q a5 b5 c6 | c6:q b5 a5 g5 | f5:q e5 d5 c5 | '
            'e5:q f5 g5 a5 | b5:q a5 g5 f5 | e5:q d5 c5 d5 | c5:w',
      ),
      lower: Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:h e3 | g3:h c4 | e3:h c3 | g2:h c3 | '
            'c3:h g3 | e3:h c3 | g3:h g2 | c3:w',
      ),
    );

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
      metadata:
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>),
    );
  });

  test('breaks a grand staff into aligned systems', () {
    final wrapped =
        layoutGrandStaffSystems(eightBarPiano(), settings, maxWidth: 40);
    expect(wrapped.systems.length, greaterThan(1));

    // Measures are covered contiguously across systems, and both staves of
    // each system share the same measure range.
    var expectedFirst = 0;
    for (final system in wrapped.systems) {
      expect(system.firstMeasure, expectedFirst);
      expect(system.layout.upper.measureRegions.length,
          system.lastMeasure - system.firstMeasure + 1);
      expect(system.layout.lower.measureRegions.length,
          system.layout.upper.measureRegions.length);
      expect(system.layout.width, lessThanOrEqualTo(40 + 0.01));
      expectedFirst = system.lastMeasure + 1;
    }
    expect(expectedFirst, 8); // all eight measures placed
  });

  test('the time signature is drawn only on the first system', () {
    final wrapped =
        layoutGrandStaffSystems(eightBarPiano(), settings, maxWidth: 40);
    expect(wrapped.systems.length, greaterThan(1));

    bool hasTimeSig(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .any((g) => g.smuflName == SmuflGlyph.timeSigDigits[4]);

    expect(hasTimeSig(wrapped.systems.first.layout.upper), isTrue);
    for (final system in wrapped.systems.skip(1)) {
      expect(hasTimeSig(system.layout.upper), isFalse);
      expect(hasTimeSig(system.layout.lower), isFalse);
    }
    // But every system restates the clef (both staves).
    for (final system in wrapped.systems) {
      expect(
        system.layout.upper.primitives
            .whereType<GlyphPrimitive>()
            .any((g) => g.smuflName == SmuflGlyph.gClef),
        isTrue,
      );
    }
  });

  test('non-final systems justify to the target width; the last stays ragged',
      () {
    final wrapped =
        layoutGrandStaffSystems(eightBarPiano(), settings, maxWidth: 40);
    expect(wrapped.systems.length, greaterThan(1));
    for (final system in wrapped.systems.take(wrapped.systems.length - 1)) {
      expect(system.layout.width, closeTo(40, 0.6),
          reason: 'non-final systems fill the width');
    }
    expect(wrapped.systems.last.layout.width, lessThan(40),
        reason: 'the last system is not stretched');
  });

  test('justification and gridding compose (§2.9 increment 4)', () {
    // Rhythmically-different hands (upper quarters, lower halves), justified.
    final wrapped =
        layoutGrandStaffSystems(eightBarPiano(), settings, maxWidth: 40);
    expect(wrapped.systems.length, greaterThan(1));
    final first = wrapped.systems.first.layout;

    // The non-final system fills the width...
    expect(first.width, closeTo(40, 0.6));

    // ...and simultaneous notes still align across the two staves (the shared
    // columns scale with the justification stretch).
    double noteX(ScoreLayout staff, String id) => staff.primitives
        .whereType<GlyphPrimitive>()
        .firstWhere(
            (g) => g.elementId == id && g.smuflName.startsWith('notehead'))
        .position
        .x;
    // Beat 1 (onset 0): upper c5 over lower c3.
    expect(noteX(first.upper, 'e0'), closeTo(noteX(first.lower, 'e0'), 0.01));
    // Beat 3 (onset 1/2): upper's third quarter over the lower's second half.
    expect(noteX(first.upper, 'e2'), closeTo(noteX(first.lower, 'e1'), 0.01));
  });

  test('justify: false leaves non-final systems ragged', () {
    final ragged = layoutGrandStaffSystems(eightBarPiano(), settings,
        maxWidth: 40, justify: false);
    final slack = ragged.systems
        .take(ragged.systems.length - 1)
        .map((s) => 40 - s.layout.width);
    expect(slack.any((gap) => gap > 1), isTrue);
  });

  test('measure-count mismatch and non-positive width fail loudly', () {
    expect(
      () => layoutGrandStaffSystems(
        GrandStaff(
          upper: Score.simple(notes: 'c5:q | d5:q'),
          lower: Score.simple(clef: Clef.bass, notes: 'c3:q'),
        ),
        settings,
        maxWidth: 40,
      ),
      throwsArgumentError,
    );
    expect(
      () => layoutGrandStaffSystems(eightBarPiano(), settings, maxWidth: 0),
      throwsArgumentError,
    );
  });

  test('systemDistance runs from the lower staff to the next upper staff', () {
    final wrapped =
        layoutGrandStaffSystems(eightBarPiano(), settings, maxWidth: 40);
    final above = wrapped.systems[0].layout.lower;
    final below = wrapped.systems[1].layout.upper;
    final gap = wrapped.gapAfter(0, 1, systemDistance: 14);

    expect((above.top + above.height - 4) + gap - below.top, closeTo(14, 1e-9));
    expect(wrapped.gapAfter(0, 1, systemDistance: 0), 1);
  });
}
