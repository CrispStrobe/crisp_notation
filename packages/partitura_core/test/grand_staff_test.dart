import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.4.2: grand staff layout.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

GrandStaff demo({String upper = 'c5:q d5 e5 f5 | g5:w', String? lower}) =>
    GrandStaff(
      upper: Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: upper,
      ),
      lower: Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: lower ?? 'c3:h e3:h | c3:w',
      ),
    );

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model', () {
    test('value semantics', () {
      expect(demo(), demo());
      expect(demo(), isNot(demo(upper: 'c5:w | g5:w')));
      expect(demo().hashCode, demo().hashCode);
    });

    test('measure-count mismatch fails loudly', () {
      expect(
        () => layoutGrandStaff(
          GrandStaff(
            upper: Score.simple(notes: 'c5:q | d5:q'),
            lower: Score.simple(clef: Clef.bass, notes: 'c3:q'),
          ),
          settings,
        ),
        throwsArgumentError,
      );
    });
  });

  group('alignment', () {
    test('leading widths, measure boundaries and totals align', () {
      final layout = layoutGrandStaff(demo(), settings);
      expect(layout.upper.width, closeTo(layout.lower.width, 1e-9));
      for (var i = 0; i < layout.upper.measureRegions.length; i++) {
        expect(
          layout.upper.measureRegions[i].startX,
          closeTo(layout.lower.measureRegions[i].startX, 1e-9),
          reason: 'measure $i start',
        );
        expect(
          layout.upper.measureRegions[i].endX,
          closeTo(layout.lower.measureRegions[i].endX, 1e-9),
          reason: 'measure $i end',
        );
      }
    });

    test('the busier staff dictates each measure width', () {
      // Upper measure 1 is busy (8 eighths), lower is one whole note; and
      // vice versa in measure 2.
      final layout = layoutGrandStaff(
        demo(
          upper: 'c5:e d5 e5 f5 g5 a5 b5 c6 | g5:w',
          lower: 'c3:w | c3:e d3 e3 f3 g3 a3 b3 c4',
        ),
        settings,
      );
      final naturalUpper = const LayoutEngine().layout(
        Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:e d5 e5 f5 g5 a5 b5 c6 | g5:w',
        ),
        settings,
      );
      // Measure 1 keeps the upper staff's natural width.
      expect(
        layout.upper.measureRegions[0].endX -
            layout.upper.measureRegions[0].startX,
        closeTo(
          naturalUpper.measureRegions[0].endX -
              naturalUpper.measureRegions[0].startX,
          1e-9,
        ),
      );
      // And the lower staff's measure 1 got padded to match.
      expect(
        layout.lower.measureRegions[0].endX -
            layout.lower.measureRegions[0].startX,
        closeTo(
          layout.upper.measureRegions[0].endX -
              layout.upper.measureRegions[0].startX,
          1e-9,
        ),
      );
    });

    test('geometry helpers', () {
      final layout = layoutGrandStaff(demo(), settings, staffGap: 5);
      expect(layout.staffGap, 5);
      expect(layout.width, layout.upper.width);
      expect(layout.height, greaterThan(8 + 5));
    });

    test('deterministic', () {
      String render() {
        final layout = layoutGrandStaff(demo(), settings);
        return [
          ...layout.upper.primitives.map((p) => p.toString()),
          '---',
          ...layout.lower.primitives.map((p) => p.toString()),
        ].join('\n');
      }

      expect(render(), render());
    });
  });
}
