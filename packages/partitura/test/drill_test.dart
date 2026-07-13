import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

// e0=c4(60) e1=e4(64) e2=g4(67) e3=chord c5+e5+g5 (72,76,79)
Score score() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q e4 g4 c5+e5+g5',
    );

const _red = Color(0xFFD32F2F);

void main() {
  test('all expected pitches played → correct + perfect', () {
    final r = evaluateDrill(
        score: score(), expectedIds: ['e0', 'e1'], played: {60, 64});
    expect(r.overlay['e0']!.message, 'correct');
    expect(r.overlay['e1']!.message, 'correct');
    expect(r.isPerfect, isTrue);
    expect(r.extraPitches, isEmpty);
    expect(r.missingPitches, isEmpty);
  });

  test('a missing pitch → wrong mark, not perfect', () {
    final r =
        evaluateDrill(score: score(), expectedIds: ['e0', 'e1'], played: {60});
    expect(r.overlay['e0']!.message, 'correct');
    expect(r.overlay['e1']!.color, _red);
    expect(r.missingPitches, {64});
    expect(r.isPerfect, isFalse);
  });

  test('a chord needs every one of its pitches', () {
    final r =
        evaluateDrill(score: score(), expectedIds: ['e3'], played: {72, 76});
    expect(r.overlay['e3']!.color, _red);
    expect(r.overlay['e3']!.message, contains('missing 1 note'));
    expect(r.missingPitches, {79});
  });

  test('extra (unexpected) pitches are reported', () {
    final r =
        evaluateDrill(score: score(), expectedIds: ['e0'], played: {60, 61});
    expect(r.overlay['e0']!.message, 'correct');
    expect(r.extraPitches, {61});
    expect(r.isPerfect, isFalse);
  });

  test('custom colors; rests / unknown ids are ignored', () {
    final r = evaluateDrill(
      score: score(),
      expectedIds: ['e0', 'nope'],
      played: {60},
      correctColor: const Color(0xFF00AA00),
    );
    expect(r.overlay.keys, ['e0']); // unknown id skipped
    expect(r.overlay['e0']!.color, const Color(0xFF00AA00));
    expect(r.isPerfect, isTrue);
  });
}
