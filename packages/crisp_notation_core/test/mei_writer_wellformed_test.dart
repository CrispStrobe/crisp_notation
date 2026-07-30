import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The MEI writer must always emit WELL-FORMED XML.
///
/// A `TupletSpan` whose `endIndex` runs past the elements it is written
/// alongside opened a `<tuplet>` that was never closed, so the document would
/// not parse back at all. Spans address a voice by index, and one addressing
/// another voice routinely overshoots this one — the same defect the LilyPond
/// writer had with its closing brace.
Score _score(TupletSpan span) => Score(
      clef: Clef.treble,
      measures: [
        Measure(
          [
            for (var i = 0; i < 3; i++)
              NoteElement(
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: NoteDuration.eighth,
                id: 'e$i',
              ),
          ],
          tuplets: [span],
        ),
      ],
    );

void main() {
  test('a tuplet ending past the last element is still closed', () {
    final mei =
        scoreToMei(_score(const TupletSpan(1, 5, actual: 3, normal: 2)));
    expect(RegExp('<tuplet').allMatches(mei), hasLength(1));
    expect(RegExp(r'</tuplet>').allMatches(mei), hasLength(1));
    expect(() => scoreFromMei(mei), returnsNormally);
    expect(scoreFromMei(mei).measures.first.elements, hasLength(3));
  });

  test('an in-range tuplet is unaffected', () {
    final mei =
        scoreToMei(_score(const TupletSpan(0, 2, actual: 3, normal: 2)));
    expect(RegExp('<tuplet').allMatches(mei), hasLength(1));
    expect(RegExp(r'</tuplet>').allMatches(mei), hasLength(1));
    expect(scoreFromMei(mei).measures.first.elements, hasLength(3));
  });

  test('a span starting past the end opens nothing', () {
    final mei =
        scoreToMei(_score(const TupletSpan(7, 9, actual: 3, normal: 2)));
    expect(RegExp('<tuplet').allMatches(mei), isEmpty);
    expect(RegExp(r'</tuplet>').allMatches(mei), isEmpty);
    expect(() => scoreFromMei(mei), returnsNormally);
  });
}
