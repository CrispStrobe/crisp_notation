import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('KeySignature.alteredSteps', () {
    test('sharps accumulate in the order F C G D A E B', () {
      const order = [Step.f, Step.c, Step.g, Step.d, Step.a, Step.e, Step.b];
      for (var fifths = 0; fifths <= 7; fifths++) {
        expect(
          KeySignature(fifths).alteredSteps,
          order.sublist(0, fifths),
          reason: '$fifths sharps',
        );
      }
    });

    test('flats accumulate in the order B E A D G C F', () {
      const order = [Step.b, Step.e, Step.a, Step.d, Step.g, Step.c, Step.f];
      for (var fifths = -1; fifths >= -7; fifths--) {
        expect(
          KeySignature(fifths).alteredSteps,
          order.sublist(0, -fifths),
          reason: '${-fifths} flats',
        );
      }
    });
  });

  group('KeySignature.alterFor', () {
    test('C major alters nothing', () {
      for (final step in Step.values) {
        expect(const KeySignature(0).alterFor(step), 0);
      }
    });

    test('D major (2 sharps): F# and C#', () {
      const d = KeySignature(2);
      expect(d.alterFor(Step.f), 1);
      expect(d.alterFor(Step.c), 1);
      for (final step in [Step.g, Step.d, Step.a, Step.e, Step.b]) {
        expect(d.alterFor(step), 0, reason: '$step');
      }
    });

    test('Eb major (3 flats): Bb, Eb, Ab', () {
      const eFlat = KeySignature(-3);
      expect(eFlat.alterFor(Step.b), -1);
      expect(eFlat.alterFor(Step.e), -1);
      expect(eFlat.alterFor(Step.a), -1);
      for (final step in [Step.c, Step.d, Step.f, Step.g]) {
        expect(eFlat.alterFor(step), 0, reason: '$step');
      }
    });

    test('extremes alter every step', () {
      for (final step in Step.values) {
        expect(const KeySignature(7).alterFor(step), 1);
        expect(const KeySignature(-7).alterFor(step), -1);
      }
    });

    test('alterFor agrees with alteredSteps for every signature', () {
      for (var fifths = -7; fifths <= 7; fifths++) {
        final signature = KeySignature(fifths);
        for (final step in Step.values) {
          final expected =
              signature.alteredSteps.contains(step) ? (fifths > 0 ? 1 : -1) : 0;
          expect(
            signature.alterFor(step),
            expected,
            reason: 'fifths $fifths, step $step',
          );
        }
      }
    });
  });

  test('value semantics', () {
    expect(const KeySignature(3), const KeySignature(3));
    expect(const KeySignature(3), isNot(const KeySignature(-3)));
    expect(const KeySignature(2).toString(), 'KeySignature(+2)');
    expect(const KeySignature(-1).toString(), 'KeySignature(-1)');
  });
}
