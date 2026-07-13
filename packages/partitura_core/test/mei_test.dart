import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// The MEI subset codec: an `<mei>` document ↔ [Score] for the shared musical
/// data. A subset-only score writes and reads back exactly; documented losses
/// (features MEI-or-partitura cannot express in the subset) are asserted.
void main() {
  test('exact round-trip: clef, key, meter, chords, rests, dots', () {
    final source = Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(-3),
      timeSignature: TimeSignature.fourFour,
      notes: 'c3+e3+g3:h. r:q | e2:q f2 g2:q. a2:e',
    );
    expect(scoreFromMei(scoreToMei(source)), source);
  });

  test('exact round-trip: two voices (layers)', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 ; c4:h g4:h',
    );
    expect(scoreFromMei(scoreToMei(source)), source);
  });

  test('exact round-trip: ties across a barline', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:h~ c4:h~ | c4:w',
    );
    expect(scoreFromMei(scoreToMei(source)), source);
  });

  test('exact round-trip: mid-score clef / key / time changes', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | !clef=bass !key=3 !time=3/4 c3:q d3 e3',
    );
    expect(scoreFromMei(scoreToMei(source)), source);
  });

  test('exact round-trip: common time (MEI keeps the symbol)', () {
    final source = Score.simple(
      timeSignature: TimeSignature.commonTime,
      notes: 'c4:w',
    );
    final back = scoreFromMei(scoreToMei(source));
    expect(back.timeSignature, TimeSignature.commonTime); // symbol preserved
    expect(back, source);
  });

  test('exact round-trip: additive meter', () {
    final source = Score.simple(
      timeSignature: TimeSignature.additive([3, 2], 8),
      notes: 'c4:e d4 e4 f4 g4',
    );
    final back = scoreFromMei(scoreToMei(source));
    expect(back.timeSignature, TimeSignature.additive([3, 2], 8));
  });

  test('exact round-trip: pickup measure', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
    );
    expect(source.measures.first.pickup, isTrue);
    final back = scoreFromMei(scoreToMei(source));
    expect(back.measures.first.pickup, isTrue);
    expect(back, source);
  });

  test('enharmonic spelling survives via accid.ges (C# stays C#, not Db)', () {
    final source = Score.simple(notes: 'c#4:q db4:q');
    final names = scoreFromMei(scoreToMei(source))
        .measures
        .single
        .elements
        .whereType<NoteElement>()
        .map((n) => n.pitches.single.toString())
        .toList();
    expect(names, ['C#4', 'Db4']);
  });

  test('reads a hand-written MEI document (real-file shape)', () {
    const mei = '''
<?xml version="1.0" encoding="UTF-8"?>
<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.0">
  <meiHead><fileDesc><titleStmt><title>x</title></titleStmt></fileDesc></meiHead>
  <music><body><mdiv><score>
    <scoreDef keysig="1s" meter.count="3" meter.unit="4">
      <staffGrp><staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp>
    </scoreDef>
    <section>
      <measure n="1"><staff n="1"><layer n="1">
        <note pname="c" oct="4" dur="4"/>
        <rest dur="4"/>
        <note pname="f" oct="4" dur="8" dots="1" accid.ges="s"/>
        <chord dur="8"><note pname="g" oct="4"/><note pname="b" oct="4"/></chord>
      </layer></staff></measure>
    </section>
  </score></mdiv></body></music>
</mei>''';
    final score = scoreFromMei(mei);
    expect(score.clef, Clef.treble);
    expect(score.keySignature.fifths, 1);
    expect(score.timeSignature, TimeSignature.threeFour);
    final elements = score.measures.single.elements;
    expect(elements, hasLength(4));
    expect((elements[0] as NoteElement).pitches.single, const Pitch(Step.c));
    expect(elements[1], isA<RestElement>());
    expect((elements[2] as NoteElement).pitches.single,
        const Pitch(Step.f, alter: 1));
    expect(
        elements[2].duration, const NoteDuration(DurationBase.eighth, dots: 1));
    expect((elements[3] as NoteElement).pitches, hasLength(2));
  });

  test('keysig strings map to fifths (2s → +2, 3f → -3, 0 → 0)', () {
    expect(meiKeySig(const KeySignature(2)), '2s');
    expect(meiKeySig(const KeySignature(-3)), '3f');
    expect(meiKeySig(const KeySignature(0)), '0');
  });

  test('rejects a non-MEI document', () {
    expect(() => scoreFromMei('<score-partwise/>'), throwsFormatException);
  });

  test('round-trips a slur (re-anchored across regenerated ids)', () {
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
    final xml = scoreToMei(source);
    expect(xml, contains('<slur startid="#a" endid="#c"/>'));
    final back = scoreFromMei(xml);
    expect(back.slurs.length, 1);
    final ids = back.measures.single.elements.map((e) => e.id).toList();
    expect(back.slurs.single.startId, ids.first);
    expect(back.slurs.single.endId, ids.last);
  });
}
