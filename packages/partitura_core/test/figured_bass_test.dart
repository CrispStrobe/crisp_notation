import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  final cMajor = Key.major(Pitch.parse('c4'));
  int pc(Pitch p) => p.midiNumber % 12;

  group('figure → chord pitch classes', () {
    test('an empty figure is a root triad', () {
      expect(
          figuredChordPitchClasses(Pitch.parse('c3'), '', cMajor), {0, 4, 7});
    });

    test('6 is the first-inversion (6/3) triad', () {
      // A 6 over G in C major = E minor (E-G-B) with G in the bass.
      expect(
          figuredChordPitchClasses(Pitch.parse('g3'), '6', cMajor), {4, 7, 11});
    });

    test('6/4 is the second inversion', () {
      // 6/4 over G = C major (G-C-E).
      expect(
          figuredChordPitchClasses(Pitch.parse('g3'), '64', cMajor), {0, 4, 7});
    });

    test('7 adds the seventh', () {
      expect(figuredChordPitchClasses(Pitch.parse('c3'), '7', cMajor),
          {0, 4, 7, 11});
    });

    test('a sharp raises the third (secondary dominant)', () {
      // # over D → D major (raised F#): the V of V.
      expect(
          figuredChordPitchClasses(Pitch.parse('d3'), '#', cMajor), {2, 6, 9});
    });

    test('the seventh-chord inversion figures (6/5, 4/3, 2)', () {
      // Over G in C major these are inversions of seventh chords.
      expect(figuredChordPitchClasses(Pitch.parse('g3'), '65', cMajor),
          {2, 4, 7, 11}); // 6/5 → Em7, G in bass (G-B-D-E)
      expect(figuredChordPitchClasses(Pitch.parse('g3'), '43', cMajor),
          {0, 4, 7, 11}); // 4/3 → Cmaj7, G in bass (G-B-C-E)
      expect(figuredChordPitchClasses(Pitch.parse('g3'), '2', cMajor),
          {0, 4, 7, 9}); // 2 → seventh chord, G in bass (G-A-C-E)
    });

    test('a flat lowers the figured third', () {
      // b over D in C major: the third F is lowered to F♭ (pc 4).
      expect(
          figuredChordPitchClasses(Pitch.parse('d3'), 'b', cMajor), {2, 4, 9});
    });

    test('a natural cancels a key accidental on the third', () {
      final gMajor = Key.major(Pitch.parse('g4')); // F♯ in the signature
      // n over D: the key's F♯ third is naturalised back to F (pc 5).
      expect(
          figuredChordPitchClasses(Pitch.parse('d3'), 'n', gMajor), {2, 5, 9});
    });
  });

  group('SATB realization', () {
    test('I–IV–V–I realizes into four clean parts', () {
      final satb = realizeFiguredBass([
        (Pitch.parse('c3'), ''), // I
        (Pitch.parse('f3'), ''), // IV
        (Pitch.parse('g3'), ''), // V
        (Pitch.parse('c3'), ''), // I
      ], cMajor);

      expect(satb, hasLength(4));
      const expectedPcs = [
        {0, 4, 7}, // C
        {5, 9, 0}, // F
        {7, 11, 2}, // G
        {0, 4, 7}, // C
      ];
      for (var i = 0; i < 4; i++) {
        final chord = satb[i];
        expect(chord, hasLength(4)); // S A T B
        // The bass is exactly the given bass.
        expect(
            chord[3],
            i == 1
                ? Pitch.parse('f3')
                : (i == 2 ? Pitch.parse('g3') : Pitch.parse('c3')));
        // Voices are ordered top → bottom.
        for (var v = 0; v + 1 < 4; v++) {
          expect(chord[v].midiNumber,
              greaterThanOrEqualTo(chord[v + 1].midiNumber));
        }
        // Every chord tone is present.
        expect({for (final p in chord) pc(p)}, expectedPcs[i]);
      }

      // No parallel perfect fifths or octaves in the whole progression.
      final parallels = checkVoiceLeading(satb).where((issue) =>
          issue.rule == VoiceLeadingRule.parallelFifths ||
          issue.rule == VoiceLeadingRule.parallelOctaves);
      expect(parallels, isEmpty);
    });
  });
}
