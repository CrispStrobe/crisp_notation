// LilyPond `<< A \\ B >>` — parallel voices.
//
// The reader used to walk only the first branch and run LYRICS commands on the
// rest, so every note after a `\\` was discarded: `<< {4 notes} \\ {4 notes} >>`
// read as 4 notes. `Score.voice2..voice4` exist and MusicXML/kern/MuseScore all
// preserve them, so this was a silent loss unique to the LilyPond reader.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

Score _read(String ly) => scoreFromLilyPond(ly);

int _n(List<MusicElement> v) => v.whereType<NoteElement>().length;

void main() {
  group('parallel voices', () {
    test('a second branch lands in voice2 instead of vanishing', () {
      final m = _read(r'''
\score { \new Staff { << { c'4 d'4 e'4 f'4 } \\ { g4 a4 b4 c'4 } >> } }
''').measures.first;
      expect(_n(m.elements), 4);
      expect(_n(m.voice2), 4);
    });

    test('three branches fill voice2 and voice3', () {
      final m = _read(r'''
\score { \new Staff { << { c'4 d'4 } \\ { g4 a4 } \\ { e4 f4 } >> } }
''').measures.first;
      expect(_n(m.elements), 2);
      expect(_n(m.voice2), 2);
      expect(_n(m.voice3), 2);
    });

    test('each branch starts from the same relative reference', () {
      // Both voices are written \relative to the same context, so the second
      // must not inherit where the first one ended up.
      final m = _read(r'''
\score { \new Staff { \relative c' { << { c4 d4 } \\ { c4 d4 } >> } } }
''').measures.first;
      final v1 = m.elements.whereType<NoteElement>().toList();
      final v2 = m.voice2.whereType<NoteElement>().toList();
      expect(
          v1.first.pitches.first.midiNumber, v2.first.pitches.first.midiNumber);
    });

    group('tuplets travel with their notes', () {
      test('a tuplet in voice 1 keeps its span and duration', () {
        final m = _read(r'''
\score { \new Staff { << { \tuplet 3/2 { c'8 d'8 e'8 } } \\ { g4 } >> } }
''').measures.first;
        expect(m.tuplets.single.voice, 0);
        // Three eighths as 3:2 sound as two eighths.
        expect(m.totalDuration, Fraction(1, 4));
      });

      test('a tuplet in voice 2 is re-pointed at voice 2', () {
        // Spans address a voice by index, so a span that travels without being
        // re-pointed would scale the WRONG notes — or none.
        final m = _read(r'''
\score { \new Staff { << { c'4 } \\ { \tuplet 3/2 { g8 a8 b8 } } >> } }
''').measures.first;
        expect(m.tuplets.single.voice, 1);
        expect(_n(m.voice2), 3);
      });
    });

    test('a plain simultaneous container is NOT treated as voices', () {
      // `\new Staff = "s" << … >>` uses << >> as a container, not a voice
      // split; its content must stay in voice 1.
      final m = _read(r'''
\score { \new Staff = "s" << \new Voice { c'4 d'4 e'4 } >> }
''').measures.first;
      expect(_n(m.elements), 3);
      expect(m.voice2, isEmpty);
    });

    test('a tuplet straddling a barline keeps its scaling', () {
      // The bar fills mid-group, so the notes land in two measures. The span
      // used to be built from a startIndex in the OLD measure and an endIndex
      // in the NEW one, fail its `end >= start` check and be dropped whole —
      // leaving every note counting at full value. That is a duration error,
      // not a missing note, so a note-count check cannot see it.
      final s = _read(r'''
\score { \new Staff { \time 2/4 c'4 d'8 \tuplet 3/2 { e'8 f'8 g'8 } } }
''');
      expect(s.measures.length, 2);
      expect(s.measures.every((m) => m.tuplets.isNotEmpty), isTrue,
          reason: 'both halves of the group must carry a span');
      // c4 + d8 + (three eighths as 3:2 = two eighths) = 5/8
      final total = s.measures
          .map((m) => m.totalDuration)
          .fold(Fraction.zero, (a, b) => a + b);
      expect(total, Fraction(5, 8));
    });

    test('a chord is unaffected', () {
      final m = _read(r'''
\score { \new Staff { <c' e' g'>4 d'4 } }
''').measures.first;
      expect(m.elements.length, 2);
      expect(m.voice2, isEmpty);
    });
  });
}
