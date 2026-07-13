import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('ChordPresets', () {
    test('ukulele presets are 4-string, named, and in range', () {
      expect(ChordPresets.ukulele, hasLength(4));
      for (final d in ChordPresets.ukulele) {
        expect(d.frets, hasLength(4));
        expect(d.name, isNotNull);
        expect(d.frets.every((f) => f >= 0 && f <= 12), isTrue);
      }
      expect(ChordPresets.ukuleleC.frets, [0, 0, 0, 3]);
    });

    test('banjo presets are 5-string and named', () {
      expect(ChordPresets.banjo, hasLength(3));
      for (final d in ChordPresets.banjo) {
        expect(d.frets, hasLength(5));
        expect(d.name, isNotNull);
      }
      // Open-G tuning: the G chord is every string open.
      expect(ChordPresets.banjoG.frets, [0, 0, 0, 0, 0]);
    });

    test('mandolin presets are 4-course and named', () {
      expect(ChordPresets.mandolin, hasLength(3));
      for (final d in ChordPresets.mandolin) {
        expect(d.frets, hasLength(4));
        expect(d.name, isNotNull);
      }
    });

    test('finger arrays, when present, match the string count', () {
      for (final d in [
        ...ChordPresets.ukulele,
        ...ChordPresets.banjo,
        ...ChordPresets.mandolin,
      ]) {
        if (d.fingers != null) {
          expect(d.fingers, hasLength(d.frets.length), reason: '${d.name}');
        }
      }
    });
  });
}
