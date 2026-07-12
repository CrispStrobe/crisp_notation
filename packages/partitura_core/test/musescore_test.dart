import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// The MuseScore subset codec: a `.mscx` document ↔ [Score] for the shared
/// musical data. Because a subset-only score writes and reads back through the
/// one model, the round-trip is exact; where MuseScore cannot express a
/// partitura feature (or vice versa) the loss is documented and asserted.
void main() {
  test('exact round-trip: clef, key, meter, chords, rests, dots', () {
    final source = Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(-2),
      timeSignature: TimeSignature.fourFour,
      notes: 'c3+e3+g3:h. r:q | e2:q f2 g2:q. a2:e',
    );
    expect(scoreFromMscx(scoreToMscx(source)), source);
  });

  test('exact round-trip: two voices', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 ; c4:h g4:h',
    );
    expect(scoreFromMscx(scoreToMscx(source)), source);
  });

  test('exact round-trip: ties (including across a barline)', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:h~ c4:h~ | c4:w',
    );
    final back = scoreFromMscx(scoreToMscx(source));
    expect(back, source);
    expect(
      back.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .last
          .tieToNext,
      isFalse,
    );
  });

  test('exact round-trip: mid-score clef / key / time changes', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | !clef=bass !key=3 !time=3/4 c3:q d3 e3',
    );
    expect(scoreFromMscx(scoreToMscx(source)), source);
  });

  test('pickup measure round-trips via the len attribute', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
    );
    expect(source.measures.first.pickup, isTrue); // sanity: detected upbeat
    final back = scoreFromMscx(scoreToMscx(source));
    expect(back.measures.first.pickup, isTrue);
    expect(back, source);
  });

  test('tpc encodes the spelling (C=14, F=13, F#=20, B♭=12, C#=21)', () {
    expect(tpcOf(const Pitch(Step.c)), 14);
    expect(tpcOf(const Pitch(Step.f)), 13);
    expect(tpcOf(const Pitch(Step.f, alter: 1)), 20);
    expect(tpcOf(const Pitch(Step.b, alter: -1)), 12);
    expect(tpcOf(const Pitch(Step.c, alter: 1)), 21);
  });

  test('enharmonic spelling survives the round-trip (C# stays C#, not Db)', () {
    final source = Score.simple(notes: 'c#4:q db4:q');
    final pitches = scoreFromMscx(scoreToMscx(source))
        .measures
        .first
        .elements
        .whereType<NoteElement>()
        .map((n) => n.pitches.single.toString())
        .toList();
    expect(pitches, ['C#4', 'Db4']);
  });

  test('reads a hand-written MuseScore document (real-file shape)', () {
    const mscx = '''
<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.20">
  <Score>
    <Division>480</Division>
    <Part id="1"><Staff id="1"/><trackName>Piano</trackName></Part>
    <Staff id="1">
      <Measure>
        <voice>
          <Clef><concertClefType>G</concertClefType></Clef>
          <KeySig><concertKey>1</concertKey></KeySig>
          <TimeSig><sigN>3</sigN><sigD>4</sigD></TimeSig>
          <Chord><durationType>quarter</durationType>
            <Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
          <Rest><durationType>quarter</durationType></Rest>
          <Chord><dots>1</dots><durationType>eighth</durationType>
            <Note><pitch>64</pitch><tpc>18</tpc></Note></Chord>
          <Chord><durationType>16th</durationType>
            <Note><pitch>67</pitch><tpc>15</tpc></Note></Chord>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>''';
    final score = scoreFromMscx(mscx);
    expect(score.clef, Clef.treble);
    expect(score.keySignature.fifths, 1);
    expect(score.timeSignature, TimeSignature.threeFour);
    final elements = score.measures.single.elements;
    expect(elements, hasLength(4));
    expect((elements[0] as NoteElement).pitches.single, const Pitch(Step.c));
    expect(elements[1], isA<RestElement>());
    expect(
        elements[2].duration, const NoteDuration(DurationBase.eighth, dots: 1));
  });

  test('whole-measure rest (durationType=measure) maps to the meter', () {
    const mscx = '''
<museScore version="4.20"><Score><Staff id="1">
  <Measure><voice>
    <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
    <Rest><durationType>measure</durationType></Rest>
  </voice></Measure>
</Staff></Score></museScore>''';
    final rest = scoreFromMscx(mscx).measures.single.elements.single;
    expect(rest, isA<RestElement>());
    expect(rest.duration, NoteDuration.whole);
  });

  test('common time degrades to numeric 4/4 (documented loss)', () {
    final source = Score.simple(
      timeSignature: TimeSignature.commonTime,
      notes: 'c4:w',
    );
    final back = scoreFromMscx(scoreToMscx(source));
    expect(back.timeSignature, TimeSignature.fourFour); // numeric, not the C
  });

  test('rejects a document that is not MuseScore XML', () {
    expect(() => scoreFromMscx('<score-partwise/>'), throwsFormatException);
  });
}
