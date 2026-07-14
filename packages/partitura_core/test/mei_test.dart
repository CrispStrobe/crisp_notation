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

  group('multi-staff (staffSystemFromMei)', () {
    const quartet = '''
<?xml version="1.0" encoding="UTF-8"?>
<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.0">
  <meiHead><fileDesc><titleStmt><title>x</title></titleStmt></fileDesc></meiHead>
  <music><body><mdiv><score>
    <scoreDef keysig="0" meter.count="4" meter.unit="4">
      <staffGrp symbol="bracket">
        <staffDef n="1" lines="5" clef.shape="G" clef.line="2" label="Violin"/>
        <staffDef n="2" lines="5" clef.shape="C" clef.line="3" label="Viola"/>
        <staffDef n="3" lines="5" clef.shape="F" clef.line="4" label="Cello"/>
      </staffGrp>
    </scoreDef>
    <section>
      <measure n="1">
        <staff n="1"><layer n="1"><note pname="c" oct="5" dur="1"/></layer></staff>
        <staff n="2"><layer n="1"><note pname="e" oct="4" dur="1"/></layer></staff>
        <staff n="3"><layer n="1"><note pname="c" oct="3" dur="1"/></layer></staff>
      </measure>
      <measure n="2">
        <staff n="1"><layer n="1"><note pname="d" oct="5" dur="1"/></layer></staff>
        <staff n="2"><layer n="1"><note pname="f" oct="4" dur="1"/></layer></staff>
        <staff n="3"><layer n="1"><note pname="d" oct="3" dur="1"/></layer></staff>
      </measure>
    </section>
  </score></mdiv></body></music>
</mei>''';

    test('reads every staffDef into an aligned staff, in order', () {
      final sys = staffSystemFromMei(quartet);
      expect(sys.staves, hasLength(3));
      expect(sys.staves[0].clef, Clef.treble);
      expect(sys.staves[1].clef, Clef.alto);
      expect(sys.staves[2].clef, Clef.bass);
      // Each staff read its own <staff n="…"> content across both measures.
      expect(sys.staves[0].measures, hasLength(2));
      expect((sys.staves[0].measures.first.elements.single as NoteElement)
          .pitches.single.octave, 5);
      expect((sys.staves[2].measures.first.elements.single as NoteElement)
          .pitches.single.octave, 3);
    });

    test('per-staff instrument labels and disjoint id spaces', () {
      final sys = staffSystemFromMei(quartet);
      expect(sys.staves[0].metadata.instrument, 'Violin');
      expect(sys.staves[2].metadata.instrument, 'Cello');
      // Ids do not collide across staves.
      final id0 = sys.staves[0].measures.first.elements.single.id;
      final id2 = sys.staves[2].measures.first.elements.single.id;
      expect(id0, isNot(id2));
    });

    test('a staffGrp symbol becomes a bracket over its staves', () {
      final sys = staffSystemFromMei(quartet);
      expect(sys.brackets,
          contains(const StaffBracket(0, 2, kind: StaffBracketKind.bracket)));
    });

    test('multiPartScoreFromMei bridges into a paginating document', () {
      final doc = multiPartScoreFromMei(quartet);
      expect(doc.parts, hasLength(3));
      expect(doc.measureCount, 2);
      expect(doc.effectiveBarlineGroups, const [BarlineGroup(0, 2)]);
    });

    test('a single-staff document still yields a one-staff system', () {
      final sys = staffSystemFromMei('''
<?xml version="1.0" encoding="UTF-8"?>
<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.0">
  <meiHead><fileDesc><titleStmt><title>x</title></titleStmt></fileDesc></meiHead>
  <music><body><mdiv><score>
    <scoreDef keysig="0" meter.count="4" meter.unit="4">
      <staffGrp><staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp>
    </scoreDef>
    <section>
      <measure n="1"><staff n="1"><layer n="1">
        <note pname="c" oct="4" dur="1"/>
      </layer></staff></measure>
    </section>
  </score></mdiv></body></music>
</mei>''');
      expect(sys.staves, hasLength(1));
      expect(sys.staves.single.clef, Clef.treble);
    });
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

  test('round-trips a tuplet (<tuplet num numbase>)', () {
    final source = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          for (final s in ['c', 'd', 'e'])
            NoteElement(
                pitches: [Pitch(Step.values.byName(s), octave: 5)],
                duration: NoteDuration.eighth,
                id: s),
        ], tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2)]),
      ],
    );
    final xml = scoreToMei(source);
    expect(xml, contains('<tuplet num="3" numbase="2">'));
    expect(scoreFromMei(xml).measures.single.tuplets,
        const [TupletSpan(0, 2, actual: 3, normal: 2)]);
  });

  // A minimal MEI wrapper around one measure body (staff 1 / layer 1).
  String meiWith(String layerBody, {String? extraSection}) => '''
<mei xmlns="http://www.music-encoding.org/ns/mei">
 <music><body><mdiv><score>
  <scoreDef><staffGrp><staffDef n="1" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>
  <section>
   <measure n="1"><staff n="1"><layer n="1">$layerBody</layer></staff></measure>
  </section>${extraSection ?? ''}
 </score></mdiv></body></music>
</mei>''';

  test('reads notes inside a <beam> (they are not dropped)', () {
    // Beams are visual grouping only — Baroque scores are almost entirely
    // beamed, so dropping beamed notes lost ~90% of the music (hardening G14).
    final xml = meiWith('<beam>'
        '<note pname="c" oct="5" dur="8"/><note pname="d" oct="5" dur="8"/>'
        '<note pname="e" oct="5" dur="8"/><note pname="f" oct="5" dur="8"/>'
        '</beam>');
    final notes = scoreFromMei(xml)
        .measures
        .single
        .elements
        .whereType<NoteElement>()
        .toList();
    expect(notes, hasLength(4));
    expect(notes.map((n) => n.pitches.single.step.name),
        ['c', 'd', 'e', 'f']);
  });

  test('reads notes inside a <beam> nested in a <beam>', () {
    final xml = meiWith('<beam><note pname="c" oct="5" dur="8"/>'
        '<beam><note pname="d" oct="5" dur="16"/>'
        '<note pname="e" oct="5" dur="16"/></beam></beam>');
    expect(
        scoreFromMei(xml)
            .measures
            .single
            .elements
            .whereType<NoteElement>()
            .length,
        3);
  });

  test('folds a <note grace> into the next note, not a full note', () {
    // A grace note must ornament the following principal note, not occupy the
    // measure as a full-duration note (which over-fills the bar — hardening
    // G16). MEI grace="unacc" = acciaccatura, "acc" = appoggiatura.
    final xml = meiWith(
      '<note grace="unacc" pname="b" oct="4" dur="16"/>'
      '<note pname="c" oct="5" dur="4"/>'
      '<note grace="acc" pname="d" oct="5" dur="16"/>'
      '<note pname="e" oct="5" dur="4"/>',
    );
    final notes = scoreFromMei(xml)
        .measures
        .single
        .elements
        .whereType<NoteElement>()
        .toList();
    // Two principal notes only; the graces are attached, not standalone.
    expect(notes, hasLength(2));
    expect(notes[0].pitches.single.step.name, 'c');
    expect(notes[0].graceNotes.single.step.name, 'b');
    expect(notes[0].graceStyle, GraceStyle.acciaccatura);
    expect(notes[1].pitches.single.step.name, 'e');
    expect(notes[1].graceNotes.single.step.name, 'd');
    expect(notes[1].graceStyle, GraceStyle.appoggiatura);
  });

  test('reads measures from every <section>, not just the first', () {
    // A chorale commonly has one <section> per verse; reading only the first
    // dropped every later verse (hardening G15).
    final xml = meiWith(
      '<note pname="c" oct="5" dur="4"/>',
      extraSection: '<section>'
          '<measure n="2"><staff n="1"><layer n="1">'
          '<note pname="d" oct="5" dur="4"/></layer></staff></measure>'
          '</section>'
          '<section>'
          '<measure n="3"><staff n="1"><layer n="1">'
          '<note pname="e" oct="5" dur="4"/></layer></staff></measure>'
          '</section>',
    );
    expect(scoreFromMei(xml).measures, hasLength(3));
  });
}
