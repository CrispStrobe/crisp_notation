import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `<actual-notes>1</actual-notes>` is a time-modification, not a tuplet.
///
/// A corpus Mass writes 1-in-the-time-of-4 as a display device for a longer
/// note. `TupletSpan` asserts `actual >= 2`, so building one made a Measure the
/// model forbids — and it only survived because `dart run` has assertions off.
/// The ratio belongs in the written value instead, which is exact for every
/// 1:N (a 16th x 4 is a quarter).
void main() {
  String doc(String notes) => '<score-partwise><part-list><score-part id="P1">'
      '<part-name>P</part-name></score-part></part-list>'
      '<part id="P1"><measure number="1">'
      '<attributes><divisions>4</divisions></attributes>'
      '$notes</measure></part></score-partwise>';

  String note(String type, int duration, {required String tuplet}) =>
      '<note><pitch><step>B</step><octave>4</octave></pitch>'
      '<duration>$duration</duration><voice>1</voice><type>$type</type>'
      '<time-modification><actual-notes>1</actual-notes>'
      '<normal-notes>4</normal-notes></time-modification>'
      '<notations><tuplet type="$tuplet"/></notations></note>';

  test('a 1:4 modification becomes the written value, with no span', () {
    final s = scoreFromMusicXml(doc(
      note('16th', 1, tuplet: 'start') + note('16th', 1, tuplet: 'stop'),
    ));
    expect(s.measures.first.tuplets, isEmpty);
    expect(
      s.measures.first.elements
          .whereType<NoteElement>()
          .map((e) => e.duration.base),
      [DurationBase.quarter, DurationBase.quarter],
      reason: 'the 4x modification was dropped instead of absorbed',
    );
  });

  test('it survives a round trip through every codec', () {
    final s = scoreFromMusicXml(doc(
      note('16th', 1, tuplet: 'start') + note('16th', 1, tuplet: 'stop'),
    ));
    Fraction total(Score x) => x.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .fold(Fraction.zero, (a, e) => a + e.duration.toFraction());
    for (final (name, back) in [
      ('mei', scoreFromMei(scoreToMei(s))),
      ('musescore', scoreFromMscx(scoreToMscx(s))),
      ('kern', scoreFromKern(scoreToKern(s))),
      ('abc', scoreFromAbc(scoreToAbc(s))),
      ('musicxml', scoreFromMusicXml(scoreToMusicXml(s))),
    ]) {
      expect(total(back), total(s), reason: name);
    }
  });

  test('a real tuplet is untouched', () {
    final s = scoreFromMusicXml(doc(
      '<note><pitch><step>B</step><octave>4</octave></pitch>'
      '<duration>2</duration><voice>1</voice><type>eighth</type>'
      '<time-modification><actual-notes>3</actual-notes>'
      '<normal-notes>2</normal-notes></time-modification>'
      '<notations><tuplet type="start"/></notations></note>'
      '<note><pitch><step>B</step><octave>4</octave></pitch>'
      '<duration>2</duration><voice>1</voice><type>eighth</type>'
      '<time-modification><actual-notes>3</actual-notes>'
      '<normal-notes>2</normal-notes></time-modification>'
      '<notations><tuplet type="stop"/></notations></note>',
    ));
    expect(s.measures.first.tuplets, hasLength(1));
    expect(s.measures.first.tuplets.single.actual, 3);
  });
}
