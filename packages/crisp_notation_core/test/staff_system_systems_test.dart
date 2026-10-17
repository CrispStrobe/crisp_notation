import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Workshop contract C6 (core): a multi-part [StaffSystem] document wrapped into
/// systems with shared barlines.
late final LayoutSettings settings;

StaffSystem eightBarTrio() => StaffSystem([
      Score.simple(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        notes:
            'c5:q d5 e5 f5 | g5:q a5 b5 c6 | c6:q b5 a5 g5 | f5:q e5 d5 c5 | '
            'e5:q f5 g5 a5 | b5:q a5 g5 f5 | e5:q d5 c5 d5 | c5:w',
      ),
      Score.simple(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        notes:
            'e4:q f4 g4 a4 | b4:q c5 d5 e5 | e5:q d5 c5 b4 | a4:q g4 f4 e4 | '
            'g4:q a4 b4 c5 | d5:q c5 b4 a4 | g4:q f4 e4 f4 | e4:w',
      ),
      Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:h e3 | g3:h c4 | e3:h c3 | g2:h c3 | '
            'c3:h g3 | e3:h c3 | g3:h g2 | c3:w',
      ),
    ], brackets: const [
      StaffBracket(0, 2)
    ]);

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
      metadata:
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>),
    );
  });

  test('wraps a three-part document into multiple systems', () {
    final wrapped =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 40);
    expect(wrapped.systems.length, greaterThan(1));
    // Every system carries all three parts.
    for (final s in wrapped.systems) {
      expect(s.layout.staves, hasLength(3));
    }
  });

  test('systems cover every measure exactly once, in order', () {
    final wrapped =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 40);
    expect(wrapped.systems.first.firstMeasure, 0);
    expect(wrapped.systems.last.lastMeasure, 7); // 8 bars, 0-based
    for (var i = 1; i < wrapped.systems.length; i++) {
      expect(wrapped.systems[i].firstMeasure,
          wrapped.systems[i - 1].lastMeasure + 1);
    }
  });

  test('barlines align across all parts within each system', () {
    final wrapped =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 40);
    for (final system in wrapped.systems) {
      final ref = system.layout.staves.first.measureRegions;
      for (final staff in system.layout.staves.skip(1)) {
        for (var i = 0; i < ref.length; i++) {
          expect(staff.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
        }
      }
    }
  });

  test('the time signature is drawn only on the first system', () {
    final wrapped =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 40);
    int timeGlyphs(StaffSystemLayout l) => l.staves
        .expand((s) => s.primitives.whereType<GlyphPrimitive>())
        .where((g) => g.smuflName.contains('timeSig'))
        .length;
    expect(timeGlyphs(wrapped.systems.first.layout), greaterThan(0));
    for (final s in wrapped.systems.skip(1)) {
      expect(timeGlyphs(s.layout), 0);
    }
  });

  test('non-final systems fill the width; the final one does not', () {
    final wrapped =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 40);
    for (var i = 0; i < wrapped.systems.length - 1; i++) {
      expect(wrapped.systems[i].layout.width, closeTo(40, 0.5));
    }
    // The last system is left ragged.
    expect(wrapped.systems.last.layout.width, lessThanOrEqualTo(40 + 1e-6));
  });

  test('justify: false leaves non-final systems ragged', () {
    final ragged = layoutStaffSystemSystems(eightBarTrio(), settings,
        maxWidth: 40, justify: false);
    expect(ragged.systems.first.layout.width, lessThan(40));
  });

  test('a wide maxWidth keeps everything on one system', () {
    final one =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 400);
    expect(one.systems, hasLength(1));
  });

  test('rejects parts with mismatched measure counts', () {
    final bad = StaffSystem([
      Score.simple(notes: 'c4:w | d4:w'),
      Score.simple(notes: 'c4:w'),
    ]);
    expect(() => layoutStaffSystemSystems(bad, settings, maxWidth: 40),
        throwsArgumentError);
  });

  test('rejects a non-positive maxWidth', () {
    expect(
        () => layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 0),
        throwsArgumentError);
  });

  test('staffSystemSystemsToSvg emits every part of every system', () {
    final wrapped =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 40);
    final svg = staffSystemSystemsToSvg(wrapped, staffSpace: 12);
    expect(svg, contains('<svg'));
    expect(svg.trimRight(), endsWith('</svg>'));
    // One `scale(` staff group per staff per system (plus barline connectors),
    // so at least three staves × N systems worth of scaled groups appear.
    final scaledGroups = 'scale('.allMatches(svg).length;
    expect(scaledGroups, greaterThanOrEqualTo(3 * wrapped.systems.length));
    // Notehead glyphs from all three parts are present.
    expect(svg, contains('<text'));
  });

  test('wrapped SVG can show instrument labels and original bar numbers', () {
    final piano = StaffSystem([
      Score.simple(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        metadata: const ScoreMetadata(instrument: 'Piano'),
        notes: 'c5:q d5 e5 f5 | g5:q a5 b5 c6 | c6:q b5 a5 g5 | f5:q e5 d5 c5',
      ),
      Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        metadata: const ScoreMetadata(instrument: 'Piano'),
        notes: 'c3:q e3 g3 c4 | c3:q e3 g3 c4 | c3:q e3 g3 c4 | c3:q e3 g3 c4',
      ),
    ], brackets: const [
      StaffBracket(0, 1, kind: StaffBracketKind.brace),
    ]);
    final wrapped = layoutStaffSystemSystems(piano, settings, maxWidth: 28);
    expect(wrapped.systems.length, greaterThan(1));

    final svg = staffSystemSystemsToSvg(
      wrapped,
      staffSpace: 12,
      leftMargin: 10,
      showInstrumentLabels: true,
      showSystemMeasureNumbers: true,
    );

    expect(svg, contains('>Piano<'));
    expect('>Piano<'.allMatches(svg), hasLength(1));
    expect(svg, contains('>2<'));
    expect(wrapped.systems[1].firstMeasure, 1);
  });

  test('a line-broken instrument name is one <text> per line', () {
    final system = StaffSystem([
      Score.simple(
        metadata: const ScoreMetadata(instrument: 'Singstimme\nVoice'),
        notes: 'c5:w | d5:w',
      ),
      Score.simple(
        clef: Clef.bass,
        metadata: const ScoreMetadata(instrument: 'Piano'),
        notes: 'c3:w | d3:w',
      ),
    ]);
    final svg = staffSystemSystemsToSvg(
      layoutStaffSystemSystems(system, settings, maxWidth: 40),
      staffSpace: 12,
      leftMargin: 10,
      showInstrumentLabels: true,
    );
    expect(svg, contains('>Singstimme<'));
    expect(svg, contains('>Voice<'));
    expect(svg, isNot(contains('Singstimme\n')));
  });

  test('wrapped SVG can reserve and render title metadata', () {
    final piano = StaffSystem([
      Score.simple(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        metadata: const ScoreMetadata(
          title: 'Sonata No. 16\n1st Movement',
          composer: 'Wolfgang Amadeus Mozart',
          instrument: 'Piano',
        ),
        notes: 'c5:q d5 e5 f5 | g5:q a5 b5 c6',
      ),
      Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        metadata: const ScoreMetadata(
          title: 'Sonata No. 16\n1st Movement',
          composer: 'Wolfgang Amadeus Mozart',
          instrument: 'Piano',
        ),
        notes: 'c3:q e3 g3 c4 | c3:q e3 g3 c4',
      ),
    ], brackets: const [
      StaffBracket(0, 1, kind: StaffBracketKind.brace),
    ]);
    final wrapped = layoutStaffSystemSystems(piano, settings, maxWidth: 60);

    final withoutTitle = staffSystemSystemsToSvg(wrapped, staffSpace: 12);
    final withTitle = staffSystemSystemsToSvg(
      wrapped,
      staffSpace: 12,
      showTitle: true,
    );

    expect(withTitle, contains('>Sonata No. 16<'));
    expect(withTitle, contains('>1st Movement<'));
    expect(withTitle, contains('>Wolfgang Amadeus Mozart<'));
    expect(withTitle.length, greaterThan(withoutTitle.length));
  });

  test('staffSystemToSvg renders a single multi-part system', () {
    final one =
        layoutStaffSystemSystems(eightBarTrio(), settings, maxWidth: 400);
    final svg = staffSystemToSvg(one.systems.single.layout, staffSpace: 12);
    expect(svg, contains('<svg'));
    expect('scale('.allMatches(svg).length, greaterThanOrEqualTo(3));
  });
}
