// The GP readers must recover the file's LEFT-HAND FINGERING, not only its
// pitches and string choice.
//
// The writer has always emitted `<Property name="LeftHandFinger">`, and both
// readers threw it away — the binary one literally `skip(2)`-ed over the bytes.
// So a fingered Guitar Pro file lost, on import, the one editorial layer a tab
// carries that an arranger cannot reproduce: which finger a person chose.
//
// The subtle part is that GP and we disagree about `0` — GP means the THUMB,
// we mean an OPEN STRING — so a straight copy is not merely lossy, it is wrong.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

Score _fingered(List<int> fingers, {int midi = 65, int? string}) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: [Pitch.fromMidi(midi)],
            duration: NoteDuration.quarter,
            id: 'n0',
            fingerings: fingers,
          ),
        ]),
      ],
      tabVoicings: [
        if (string != null) TabVoicing('n0', [string]),
      ],
    );

NoteElement _only(Score s) =>
    s.measures.expand((m) => m.elements).whereType<NoteElement>().single;

void main() {
  final t = Tuning.standardGuitar;

  group('GPIF (Guitar Pro 6/7 XML)', () {
    test('a left-hand finger survives the round trip', () {
      final back = scoreFromGpif(scoreToGpif(_fingered(const [2]), tuning: t));
      expect(
        _only(back).fingerings,
        [2],
        reason: 'the writer emitted it and the reader used to drop it',
      );
    });

    test('an unfingered file yields no fingering — not a row of zeros', () {
      final back = scoreFromGpif(scoreToGpif(_fingered(const []), tuning: t));
      expect(
        _only(back).fingerings,
        isEmpty,
        reason: 'silence in the file must stay silence, not become "open"',
      );
    });

    test('the THUMB survives as a thumb, not as an open string', () {
      // GP writes the thumb as 0 and an unstated finger as -1; our 0 is an open
      // string. This is the case a straight byte copy gets wrong.
      final back = scoreFromGpif(
        scoreToGpif(_fingered(const [kFingeringThumb]), tuning: t),
      );
      expect(_only(back).fingerings, [kFingeringThumb]);
    });
  });

  group('the binary formats (GP3/4/5)', () {
    test('a left-hand finger survives write → binary → read', () {
      final back = scoreFromGpif(
        readGpifFromGp(
            writeGpFromGpif(scoreToGpif(_fingered(const [3]), tuning: t))),
      );
      expect(_only(back).fingerings, [3]);
    });

    test('and so does the thumb', () {
      final back = scoreFromGpif(
        readGpifFromGp(writeGpFromGpif(
            scoreToGpif(_fingered(const [kFingeringThumb]), tuning: t))),
      );
      expect(_only(back).fingerings, [kFingeringThumb]);
    });

    test('an unfingered file still yields nothing after a round trip', () {
      final back = scoreFromGpif(
        readGpifFromGp(
            writeGpFromGpif(scoreToGpif(_fingered(const []), tuning: t))),
      );
      expect(_only(back).fingerings, isEmpty);
    });
  });

  test('fingering does not disturb the pitch or the string choice', () {
    // The regression that would matter most: reading two extra bytes in the
    // binary parser puts every following field at the wrong offset. If the
    // pitch and voicing still come back right, the cursor is still aligned.
    final score = _fingered(const [4], midi: 64, string: 1);
    final back = scoreFromGpif(
      readGpifFromGp(writeGpFromGpif(scoreToGpif(score, tuning: t))),
    );
    final note = _only(back);
    expect(note.pitches.single.midiNumber, 64);
    expect(note.fingerings, [4]);
    final voiced = {for (final v in back.tabVoicings) v.noteId: v.strings};
    expect(voiced[note.id], [1]);
  });
}
