import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// EVERY element a reader produces must carry an id.
///
/// ⚠️ The LilyPond reader left exactly one kind without one: the spacer rests
/// that align an inner `\\` voice to the point where its split began. 33 of 181
/// elements in one corpus file. That is not cosmetic —
///
/// - a span cannot attach to an id-less element, so no slur, hairpin or pedal
///   can ever touch an inner voice's opening rest;
/// - every index-based comparison shifts from that point on, which is why one
///   file failed identically in all four capable target formats, with all 20
///   of its slurs present and every position wrong;
/// - and `scoreToMidi` silently DROPS notes whose id is null, so inner voices
///   read from `.ly` did not reach MIDI export at all.
///
/// The last one is why this is worth a test of its own rather than a line in
/// the slur suite: the symptom appears three subsystems away from the cause.
void main() {
  const twoVoices = r'''
\score {
  \new Staff {
    \time 4/4
    << { c'4 d'4 e'4 f'4 } \\ { r4 g4 a4 b4 } >>
    << { g'4 a'4 b'4 c''4 } \\ { r2 c4 d4 } >>
  }
}
''';

  ({int total, int withoutId}) audit(Score s) {
    var total = 0;
    var withoutId = 0;
    for (final m in s.measures) {
      for (final v in [m.elements, m.voice2, m.voice3, m.voice4]) {
        for (final e in v) {
          total++;
          if (e.id == null) withoutId++;
        }
      }
    }
    return (total: total, withoutId: withoutId);
  }

  test('every element read from LilyPond has an id', () {
    final a = audit(scoreFromLilyPond(twoVoices));
    expect(a.total, greaterThan(0));
    expect(a.withoutId, 0);
  });

  test('ids are unique', () {
    final s = scoreFromLilyPond(twoVoices);
    final ids = <String>[];
    for (final m in s.measures) {
      for (final v in [m.elements, m.voice2, m.voice3, m.voice4]) {
        for (final e in v) {
          if (e.id != null) ids.add(e.id!);
        }
      }
    }
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('the other readers already did this — parity', () {
    final src = scoreFromLilyPond(twoVoices);
    for (final back in [
      scoreFromMusicXml(scoreToMusicXml(src)),
      scoreFromMei(scoreToMei(src)),
      scoreFromMscx(scoreToMscx(src)),
      scoreFromLilyPond(scoreToLilyPond(src)),
    ]) {
      final a = audit(back);
      expect(a.withoutId, 0);
      expect(a.total, audit(src).total);
    }
  });
}
