import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A bar cannot be both a multi-measure rest and full of notes.
///
/// `<measure-style><multiple-rest>` is a DISPLAY instruction and a real file can
/// contradict itself: the corpus holds a MuseScore export whose measure 52
/// declares a 2-bar multi-rest and then carries two half notes. Storing that
/// contradiction made every consumer defend against it, and two did not — the
/// ABC writer emitted `Z` in place of the bar and dropped the notes, and the
/// layout engine drew a multi-rest instead of drawing them.
void main() {
  const noteXml = '<note><pitch><step>A</step><octave>4</octave></pitch>'
      '<duration>2</duration><voice>1</voice><type>half</type></note>';

  String doc(String measureBody) =>
      '<score-partwise><part-list><score-part id="P1">'
      '<part-name>P</part-name></score-part></part-list>'
      '<part id="P1"><measure number="1">'
      '<attributes><divisions>1</divisions></attributes>'
      '$measureBody</measure></part></score-partwise>';

  test('a multi-rest bar that carries notes is not a multi-rest', () {
    final score = scoreFromMusicXml(doc(
      '<attributes><measure-style><multiple-rest>2</multiple-rest>'
      '</measure-style></attributes>$noteXml$noteXml',
    ));
    expect(score.measures.first.multiRest, isNull);
    expect(
      score.measures.first.elements.whereType<NoteElement>(),
      hasLength(2),
    );
  });

  test('a genuine multi-rest is still read as one', () {
    final score = scoreFromMusicXml(doc(
      '<attributes><measure-style><multiple-rest>3</multiple-rest>'
      '</measure-style></attributes>'
      '<note><rest/><duration>4</duration><voice>1</voice></note>',
    ));
    expect(score.measures.first.multiRest, 3);
  });

  test('the model admits a rest as a multi-rest ANCHOR, not a note', () {
    // A multi-rest may keep its rest so a mark set on the silent stretch has
    // an element to sit on (#11). Notes are the reader's job to rule out (the
    // test above): a const constructor cannot inspect element types, and the
    // reader normalises the contradiction at the boundary.
    expect(
      () => Measure([RestElement(NoteDuration.whole, id: 'r')], multiRest: 2),
      returnsNormally,
    );
    final read = scoreFromMusicXml(doc(
      '<attributes><measure-style><multiple-rest>2</multiple-rest>'
      '</measure-style></attributes>'
      '<note><pitch><step>A</step><octave>4</octave></pitch>'
      '<duration>4</duration><voice>1</voice><type>whole</type></note>',
    ));
    expect(read.measures.first.multiRest, isNull);
  });

  test('an EMPTY multi-rest bar still writes as Z', () {
    final score = Score(
      clef: Clef.treble,
      measures: [Measure(const [], multiRest: 4)],
    );
    expect(scoreToAbc(score), contains('Z4'));
  });
}
