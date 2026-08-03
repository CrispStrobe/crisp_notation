import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A bar that does NOT match its meter.
///
/// 🛑 This was recorded as a hard LilyPond format limitation and it is not one.
/// LilyPond derives barlines from durations plus the meter, so an over-full bar
/// left implicit makes it re-bar the piece and every bar after shifts — one
/// 135-bar motet came back with 152, and it accounted for essentially all of
/// the `krn -> lilypond` gap against the other formats.
///
/// But LilyPond states an irregular measure explicitly, with
/// `\set Timing.measureLength`. The writer emits it whenever a bar's length
/// differs from the running one, and the reader honours it in place of the
/// meter's capacity. Real early music is full of these — a 3/2 bar written
/// under 3/4 is ordinary in the NIFC corpus.
void main() {
  List<MusicElement> beats(String p, int n, DurationBase d) => [
        for (var i = 0; i < n; i++)
          NoteElement(
            id: '$p$i',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: NoteDuration(d),
          ),
      ];

  test('an OVER-FULL bar does not re-bar the piece', () {
    // 3/4 meter, but bar 2 holds six quarters.
    final source = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(3, 4),
      measures: [
        Measure(beats('a', 3, DurationBase.quarter)),
        Measure(beats('b', 6, DurationBase.quarter)),
        Measure(beats('c', 3, DurationBase.quarter)),
      ],
    );
    final ly = scoreToLilyPond(source);
    expect(ly, contains(r'\set Timing.measureLength'));
    final back = scoreFromLilyPond(ly);
    expect(back.measures, hasLength(3));
    expect(back.measures[0].elements, hasLength(3));
    expect(back.measures[1].elements, hasLength(6));
    expect(back.measures[2].elements, hasLength(3));
  });

  // ⚠️ An under-full bar needs NO measureLength: the writer emits an explicit
  // `|` after every measure and the reader closes on it. Announcing a shorter
  // length for these as well cost 14 MusicXML round trips — only the OVER-full
  // case is the one LilyPond cannot otherwise express.
  test('an UNDER-full bar keeps its length WITHOUT an override', () {
    final source = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(beats('a', 4, DurationBase.quarter)),
        Measure(beats('b', 2, DurationBase.quarter)),
        Measure(beats('c', 4, DurationBase.quarter)),
      ],
    );
    final ly = scoreToLilyPond(source);
    expect(ly, isNot(contains('measureLength')));
    final back = scoreFromLilyPond(ly);
    expect(back.measures, hasLength(3));
    expect([for (final m in back.measures) m.elements.length], [4, 2, 4]);
  });

  // ⚠️ The bar's content is the LONGEST voice, not voice 1 — which need not
  // fill the bar when another voice does.
  test('voice 1 being short does NOT shorten the bar', () {
    final source = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(
          beats('a', 2, DurationBase.quarter),
          voice2: beats('b', 4, DurationBase.quarter),
        ),
        Measure(beats('c', 4, DurationBase.quarter)),
      ],
    );
    final ly = scoreToLilyPond(source);
    expect(ly, isNot(contains('measureLength')));
    final back = scoreFromLilyPond(ly);
    expect(back.measures, hasLength(2));
    expect(back.measures[0].voice2, hasLength(4));
  });

  test('an ordinary score emits NO measureLength', () {
    final plain = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(beats('a', 4, DurationBase.quarter)),
        Measure(beats('b', 4, DurationBase.quarter)),
      ],
    );
    expect(scoreToLilyPond(plain), isNot(contains('measureLength')));
  });

  test('a \\time RESETS the override', () {
    // ⚠️ LilyPond's `\time` resets the bar length, so an override set for an
    // earlier irregular bar must not outlive it — otherwise every bar after a
    // meter change keeps the old length and the piece re-bars from there.
    final source = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(3, 4),
      measures: [
        Measure(beats('a', 6, DurationBase.quarter)),
        Measure(beats('b', 4, DurationBase.quarter),
            timeChange: const TimeSignature(4, 4)),
        Measure(beats('c', 4, DurationBase.quarter)),
      ],
    );
    final back = scoreFromLilyPond(scoreToLilyPond(source));
    expect(back.measures, hasLength(3));
    expect([for (final m in back.measures) m.elements.length], [6, 4, 4]);
    expect(back.measures[1].timeChange?.beats, 4);
  });
}
