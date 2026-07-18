import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// LilyPond is export-only (its input is a full language), so these assert the
/// generated `.ly` contains the expected constructs rather than round-tripping.
void main() {
  test('emits version, staff, clef, key and time', () {
    final ly = scoreToLilyPond(Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(-2),
      timeSignature: TimeSignature.threeFour,
      notes: 'c3:q d3 e3',
    ));
    expect(ly, contains('\\version "'));
    expect(ly, contains('\\new Staff {'));
    expect(ly, contains('\\clef bass'));
    expect(ly, contains('\\key bes \\major'));
    expect(ly, contains('\\time 3/4'));
    expect(ly, contains('\\layout { }'));
  });

  test('pitches carry octave marks and accidentals (Dutch names)', () {
    final ly = scoreToLilyPond(Score.simple(notes: 'c4:q c#4 e4:h f#3:q bb5'));
    expect(ly, contains("c'4")); // C4 = one apostrophe
    expect(ly, contains("cis'4")); // C#4
    expect(ly, contains("e'2")); // E4 half
    expect(ly, contains('fis4')); // F#3 = no marks
    expect(ly, contains("bes''4")); // Bb5 = two apostrophes
  });

  test('low octaves use commas', () {
    final ly = scoreToLilyPond(Score.simple(clef: Clef.bass, notes: 'c2:q c1'));
    expect(ly, contains('c,4')); // C2
    expect(ly, contains('c,,4')); // C1
  });

  test('chords, rests, dots, ties and breve', () {
    final ly = scoreToLilyPond(Score.simple(
      notes: 'c4+e4+g4:h. r:q | c4:b | c4:q~ c4:q',
    ));
    expect(ly, contains("<c' e' g'>2.")); // dotted-half chord
    expect(ly, contains('r4')); // rest
    expect(ly, contains("c'\\breve")); // breve
    expect(ly, contains("c'4~")); // tie
  });

  test('two voices use the polyphony construct', () {
    final ly = scoreToLilyPond(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 ; c4:h g4:h',
    ));
    expect(ly, contains('<<'));
    expect(ly, contains('\\\\'));
    expect(ly, contains('>>'));
  });

  test('numeric 4/4 forces numerals; common time does not', () {
    final numeric = scoreToLilyPond(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:w',
    ));
    expect(numeric, contains('\\numericTimeSignature'));
    final common = scoreToLilyPond(Score.simple(
      timeSignature: TimeSignature.commonTime,
      notes: 'c4:w',
    ));
    expect(common, isNot(contains('\\numericTimeSignature')));
    expect(common, contains('\\time 4/4'));
  });

  test('a pickup measure emits \\partial', () {
    final ly = scoreToLilyPond(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
    ));
    expect(ly, contains('\\partial 4'));
  });

  test('mid-score clef / key / time changes appear inline', () {
    final ly = scoreToLilyPond(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | !clef=bass !key=3 !time=3/4 c3:q d3 e3',
    ));
    expect(ly, contains('\\clef bass'));
    expect(ly, contains('\\key a \\major'));
    expect(ly, contains('\\time 3/4'));
  });

  test('slurs export as ( and )', () {
    final source = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
              pitches: [const Pitch(Step.c, octave: 4)],
              duration: NoteDuration.quarter,
              id: 'a'),
          NoteElement(
              pitches: [const Pitch(Step.d, octave: 4)],
              duration: NoteDuration.quarter,
              id: 'b'),
          NoteElement(
              pitches: [const Pitch(Step.e, octave: 4)],
              duration: NoteDuration.quarter,
              id: 'c'),
        ]),
      ],
      slurs: const [Slur('a', 'c')],
    );
    final ly = scoreToLilyPond(source);
    expect(ly, contains("c'4("));
    expect(ly, contains("e'4)"));
  });

  test('tuplets export as \\tuplet a/n { … }', () {
    final source = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          for (final s in ['c', 'd', 'e'])
            NoteElement(
                pitches: [Pitch(Step.values.byName(s), octave: 5)],
                duration: NoteDuration.eighth,
                id: s),
        ], tuplets: const [
          TupletSpan(0, 2, actual: 3, normal: 2)
        ]),
      ],
    );
    final ly = scoreToLilyPond(source);
    expect(ly, contains('\\tuplet 3/2 {'));
    expect(ly, contains('}'));
  });

  test('grace notes export as \\acciaccatura / \\appoggiatura', () {
    final ly = scoreToLilyPond(Score(clef: Clef.treble, measures: [
      Measure([
        NoteElement(
            pitches: [const Pitch(Step.c, octave: 5)],
            duration: NoteDuration.quarter,
            graceNotes: [const Pitch(Step.b, octave: 4)],
            id: 'a'),
        NoteElement(
            pitches: [const Pitch(Step.d, octave: 5)],
            duration: NoteDuration.quarter,
            graceNotes: [const Pitch(Step.e, octave: 5)],
            graceStyle: GraceStyle.appoggiatura,
            id: 'b'),
      ]),
    ]));
    expect(ly, contains('\\acciaccatura b\'8'));
    expect(ly, contains('\\appoggiatura e\'\'8'));
  });

  group('multi-part → a StaffGroup with one Staff per part', () {
    NoteElement note(Step s, int o) => NoteElement(
        pitches: [Pitch(s, octave: o)], duration: NoteDuration.whole);
    final flute = Score(clef: Clef.treble, measures: [
      Measure([note(Step.g, 5)]),
    ]);
    final cello = Score(clef: Clef.bass, measures: [
      Measure([note(Step.c, 3)]),
    ]);
    final ly = multiPartToLilyPond(MultiPartScore([flute, cello]),
        partNames: ['Flute', 'Cello']);

    test('wraps every part in one StaffGroup', () {
      expect('\\new StaffGroup'.allMatches(ly), hasLength(1));
      expect('<<'.allMatches(ly), hasLength(1));
      expect('>>'.allMatches(ly), hasLength(1));
      // Two \new Staff blocks (the trailing space excludes \new StaffGroup).
      expect(RegExp(r'\\new Staff[ \\]').allMatches(ly), hasLength(2));
    });

    test('each part keeps its own clef, instrument name and notes', () {
      expect(ly, contains('\\clef treble'));
      expect(ly, contains('\\clef bass'));
      expect(ly, contains('instrumentName = "Flute"'));
      expect(ly, contains('instrumentName = "Cello"'));
      expect(ly, contains("g''1")); // G5
      expect(ly, contains('c1')); // C3
    });

    test('the document is well-formed (balanced braces)', () {
      expect('{'.allMatches(ly).length, '}'.allMatches(ly).length);
    });
  });
}
