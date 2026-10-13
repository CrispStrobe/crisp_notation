import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

import 'support/layout_lint.dart';

/// Every barline the model can ask for, at every place it can sit (first,
/// middle, last bar; on a line break or not), through every layout entry
/// point — each result checked against the engraving rules in
/// [lintLayout]. Bugs like #19 hide in these corners: one bar drawn by two
/// pieces of code that each look right alone.
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));

  // Four bars of quarters; [edit] sets each bar's barline attributes.
  Score score(Measure Function(int index, Measure m) edit) {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: List.filled(4, 'c5:q d5 e5 f5').join(' | '),
    );
    return base.copyWith(measures: [
      for (final (i, m) in base.measures.indexed) edit(i, m),
    ]);
  }

  // How bar 1 ends and bar 2 begins, and how the last bar (3) ends.
  final joins = <String, Measure Function(int, Measure)>{
    'plain': (i, m) => m,
    'start repeat': (i, m) => i == 1 ? m.copyWith(startRepeat: true) : m,
    'end repeat': (i, m) => i == 0 ? m.copyWith(endRepeat: true) : m,
    'end + start repeat': (i, m) => switch (i) {
          0 => m.copyWith(endRepeat: true),
          1 => m.copyWith(startRepeat: true),
          _ => m,
        },
    'double bar + start repeat': (i, m) => switch (i) {
          0 => m.copyWith(barline: BarlineStyle.doubleBar),
          1 => m.copyWith(startRepeat: true),
          _ => m,
        },
    'key change + start repeat': (i, m) => i == 1
        ? m.copyWith(startRepeat: true, keyChange: const KeySignature(2))
        : m,
    'time change + start repeat + double bar': (i, m) => switch (i) {
          0 => m.copyWith(barline: BarlineStyle.doubleBar),
          1 => m.copyWith(
              startRepeat: true, timeChange: const TimeSignature(3, 4)),
          _ => m,
        },
    'opening start repeat': (i, m) =>
        i == 0 ? m.copyWith(startRepeat: true) : m,
    'volta 1 / 2': (i, m) => switch (i) {
          1 => m.copyWith(volta: 1, endRepeat: true),
          2 => m.copyWith(volta: 2),
          _ => m,
        },
  };
  final endings = <String, Measure Function(Measure)>{
    'default': (m) => m,
    'end repeat': (m) => m.copyWith(endRepeat: true),
    for (final style in BarlineStyle.values)
      if (style != BarlineStyle.normal)
        'barline ${style.name}': (m) => m.copyWith(barline: style),
    'end repeat + final style': (m) =>
        m.copyWith(endRepeat: true, barline: BarlineStyle.finalBar),
  };

  // [measures]: the score's measures this layout drew, in order.
  void expectClean(ScoreLayout layout, String where,
      {required bool closes,
      required List<Measure> measures,
      bool signatures = true}) {
    final issues = [
      ...lintLayout(layout, settings,
          closes: closes, lastMeasure: measures.last),
      ...barlineMismatches(
          layout, Score(clef: Clef.treble, measures: measures), settings,
          closes: closes, signatures: signatures),
    ];
    expect(issues, isEmpty, reason: '$where:\n${issues.join('\n')}');
  }

  List<Measure> slice(Score s, int first, int last) =>
      s.measures.sublist(first, last + 1);

  for (final MapEntry(key: joinName, value: join) in joins.entries) {
    for (final MapEntry(key: endName, value: ending) in endings.entries) {
      final s = score((i, m) => i == 3 ? ending(join(i, m)) : join(i, m));
      group('$joinName, ending $endName', () {
        test('one line', () {
          expectClean(const LayoutEngine().layout(s, settings), 'line',
              closes: true, measures: s.measures);
        });

        test('a line break at every bar', () {
          final systems = layoutSystems(s, settings,
              maxWidth: 60, systemBreaks: const {1, 2, 3}).systems;
          expect(systems, hasLength(4));
          for (final (k, sys) in systems.indexed) {
            expectClean(sys.layout, 'system $k',
                closes: k == systems.length - 1,
                measures: slice(s, sys.firstMeasure, sys.lastMeasure));
          }
        });

        test('justified lines', () {
          final systems = layoutSystems(s, settings, maxWidth: 40).systems;
          for (final (k, sys) in systems.indexed) {
            expectClean(sys.layout, 'system $k',
                closes: k == systems.length - 1,
                measures: slice(s, sys.firstMeasure, sys.lastMeasure));
          }
        });

        test('grand staff', () {
          final g = layoutGrandStaff(
              GrandStaff(upper: s, lower: s.copyWith(clef: Clef.bass)),
              settings);
          for (final (name, l) in [('upper', g.upper), ('lower', g.lower)]) {
            expectClean(l, name, closes: true, measures: s.measures);
          }
        });

        test('grand staff, broken into systems', () {
          final systems = layoutGrandStaffSystems(
                  GrandStaff(upper: s, lower: s.copyWith(clef: Clef.bass)),
                  settings,
                  maxWidth: 40)
              .systems;
          for (final (k, sys) in systems.indexed) {
            for (final l in [sys.layout.upper, sys.layout.lower]) {
              expectClean(l, 'system $k',
                  closes: k == systems.length - 1,
                  measures: slice(s, sys.firstMeasure, sys.lastMeasure));
            }
          }
        });

        test('three-staff system, broken into systems', () {
          final systems = layoutStaffSystemSystems(
                  StaffSystem([s, s, s.copyWith(clef: Clef.bass)]), settings,
                  maxWidth: 40)
              .systems;
          for (final (k, sys) in systems.indexed) {
            for (final l in sys.layout.staves) {
              expectClean(l, 'system $k',
                  closes: k == systems.length - 1,
                  measures: slice(s, sys.firstMeasure, sys.lastMeasure));
            }
          }
        });

        test('notation + tab', () {
          final nt = layoutNotationTab(s, Tuning.standardGuitar, settings);
          expectClean(nt.notation, 'notation',
              closes: true, measures: s.measures);
          expectClean(nt.tab, 'tab',
              closes: true, measures: s.measures, signatures: false);
        });
      });
    }
  }
}
