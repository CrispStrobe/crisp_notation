import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

String pitchesOf(SeventhChord c) => c.pitches.join(' ');

void main() {
  group('root-position seventh qualities', () {
    test('dominant / major / minor stack in thirds', () {
      expect(
        pitchesOf(SeventhChord(const Pitch(Step.g), ChordType.dominantSeventh)),
        'G4 B4 D5 F5',
      );
      expect(
        pitchesOf(SeventhChord(const Pitch(Step.c), ChordType.majorSeventh)),
        'C4 E4 G4 B4',
      );
      expect(
        pitchesOf(SeventhChord(const Pitch(Step.d), ChordType.minorSeventh)),
        'D4 F4 A4 C5',
      );
    });

    test('half-diminished vs fully-diminished spell the right seventh', () {
      expect(
        pitchesOf(
            SeventhChord(const Pitch(Step.b), ChordType.halfDiminishedSeventh)),
        'B4 D5 F5 A5',
      );
      // The fully-diminished seventh is a *diminished* seventh (B → A♭), not A.
      expect(
        pitchesOf(
            SeventhChord(const Pitch(Step.b), ChordType.diminishedSeventh)),
        'B4 D5 F5 Ab5',
      );
    });
  });

  test('inversions move the lowest notes up an octave', () {
    const g = Pitch(Step.g);
    expect(
      pitchesOf(SeventhChord(g, ChordType.dominantSeventh, inversion: 1)),
      'B4 D5 F5 G5',
    );
    expect(
      pitchesOf(SeventhChord(g, ChordType.dominantSeventh, inversion: 2)),
      'D5 F5 G5 B5',
    );
    expect(
      pitchesOf(SeventhChord(g, ChordType.dominantSeventh, inversion: 3)),
      'F5 G5 B5 D6',
    );
  });

  test('round-trips through the analyser as a Roman numeral', () {
    final cMajor = Key.major(const Pitch(Step.c));
    String rn(SeventhChord c) => romanNumeralOf(c.pitches, cMajor)!.symbol;

    expect(rn(SeventhChord(const Pitch(Step.g), ChordType.dominantSeventh)),
        'V7');
    expect(
        rn(SeventhChord(const Pitch(Step.d), ChordType.minorSeventh)), 'ii7');
    expect(
      rn(SeventhChord(const Pitch(Step.b), ChordType.halfDiminishedSeventh)),
      'viiø7',
    );
    // First-inversion dominant seventh carries the 6/5 figure.
    expect(
      rn(SeventhChord(const Pitch(Step.g), ChordType.dominantSeventh,
          inversion: 1)),
      'V6/5',
    );
  });

  test('only seventh types are accepted', () {
    expect(SeventhChord.isSeventhType(ChordType.dominantSeventh), isTrue);
    expect(SeventhChord.isSeventhType(ChordType.diminishedSeventh), isTrue);
    expect(SeventhChord.isSeventhType(ChordType.major), isFalse);
    expect(
      () => SeventhChord(const Pitch(Step.c), ChordType.major),
      throwsA(isA<AssertionError>()),
    );
  });
}
