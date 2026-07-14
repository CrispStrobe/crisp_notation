import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

List<Pitch> chord(String names) => names.split(' ').map(Pitch.parse).toList();

Set<VoiceLeadingRule> rules(List<VoiceLeadingIssue> issues) =>
    {for (final i in issues) i.rule};

void main() {
  group('parallel perfect intervals', () {
    test('parallel fifths (both voices up a step, fifth to fifth)', () {
      // G4/C4 (P5) → A4/D4 (P5), similar upward motion.
      final issues = checkVoiceLeading([chord('g4 c4'), chord('a4 d4')]);
      expect(issues, hasLength(1));
      expect(issues.single.rule, VoiceLeadingRule.parallelFifths);
      expect(issues.single.chordIndex, 1);
      expect(issues.single.upperVoice, 0);
      expect(issues.single.lowerVoice, 1);
    });

    test('parallel octaves', () {
      final issues = checkVoiceLeading([chord('c5 c4'), chord('d5 d4')]);
      expect(rules(issues), contains(VoiceLeadingRule.parallelOctaves));
    });

    test('a non-perfect parallel motion (thirds) is fine', () {
      // C5/A4 (m3) → D5/B4 (m3): parallel thirds are allowed.
      expect(checkVoiceLeading([chord('c5 a4'), chord('d5 b4')]), isEmpty);
    });
  });

  group('hidden (direct) perfect intervals', () {
    test('outer voices leap into a fifth by similar motion', () {
      // Bass steps up, soprano leaps up into a P5 — a hidden fifth.
      final issues = checkVoiceLeading([chord('c5 c4'), chord('a5 d4')]);
      expect(rules(issues), contains(VoiceLeadingRule.hiddenFifths));
    });

    test('stepwise similar motion into a fifth is not hidden', () {
      // Soprano moves by step (not a leap) → allowed.
      final issues = checkVoiceLeading([chord('c5 c4'), chord('d5 g4')]);
      expect(rules(issues), isNot(contains(VoiceLeadingRule.hiddenFifths)));
    });

    test('outer voices leap into an octave by similar motion', () {
      // Bass steps up (C4→D4), soprano leaps up a fourth (A4→D5) into a P8 —
      // a hidden (direct) octave.
      final issues = checkVoiceLeading([chord('a4 c4'), chord('d5 d4')]);
      expect(rules(issues), contains(VoiceLeadingRule.hiddenOctaves));
    });
  });

  group('crossing, overlap and spacing', () {
    test('voice crossing within a chord', () {
      // Voice 0 = C4, voice 1 = E4 (the lower voice sounds higher).
      final issues = checkVoiceLeading([chord('c4 e4')]);
      expect(issues.single.rule, VoiceLeadingRule.voiceCrossing);
    });

    test('voice overlap between chords', () {
      // E4/C4 → G4/F4: the lower voice (F4) rises above the upper's old E4.
      final issues = checkVoiceLeading([chord('e4 c4'), chord('g4 f4')]);
      expect(rules(issues), contains(VoiceLeadingRule.voiceOverlap));
    });

    test('spacing: upper voices over an octave apart', () {
      // S=C6, A=C4 (two octaves) with a bass below → spacing flagged on S-A;
      // the bass–tenor gap is exempt.
      final issues = checkVoiceLeading([chord('c6 c4 g3')]);
      final spacing =
          issues.where((i) => i.rule == VoiceLeadingRule.spacing).toList();
      expect(spacing, hasLength(1));
      expect(spacing.single.upperVoice, 0);
      expect(spacing.single.lowerVoice, 1);
    });

    test('a well-spaced close-position chord is clean', () {
      expect(checkVoiceLeading([chord('c5 g4 e4 c4')]), isEmpty);
    });
  });

  test('a clean two-chord progression flags nothing', () {
    // C major → F major in close position, stepwise: no parallels, good spacing.
    expect(
      checkVoiceLeading([chord('g4 e4 c4'), chord('f4 c4 a3')]),
      isEmpty,
    );
  });
}
