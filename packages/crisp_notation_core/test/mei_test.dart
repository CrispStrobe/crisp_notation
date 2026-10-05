import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The MEI subset codec: an `<mei>` document ↔ [Score] for the shared musical
/// data. A subset-only score writes and reads back exactly; documented losses
/// (features MEI-or-crisp_notation cannot express in the subset) are asserted.
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
      expect(
          (sys.staves[0].measures.first.elements.single as NoteElement)
              .pitches
              .single
              .octave,
          5);
      expect(
          (sys.staves[2].measures.first.elements.single as NoteElement)
              .pitches
              .single
              .octave,
          3);
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

  test('round-trips grace notes (write <note grace> then read back)', () {
    final source = Score(clef: Clef.treble, measures: [
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
    ]);
    final mei = scoreToMei(source);
    expect(mei, contains('grace="unacc"'));
    expect(mei, contains('grace="acc"'));
    final notes =
        scoreFromMei(mei).measures.single.elements.cast<NoteElement>();
    expect(notes.first.graceNotes.single, const Pitch(Step.b, octave: 4));
    expect(notes.first.graceStyle, GraceStyle.acciaccatura);
    expect(notes.last.graceNotes.single, const Pitch(Step.e, octave: 5));
    expect(notes.last.graceStyle, GraceStyle.appoggiatura);
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
        ], tuplets: const [
          TupletSpan(0, 2, actual: 3, normal: 2)
        ]),
      ],
    );
    final xml = scoreToMei(source);
    expect(xml, contains('<tuplet num="3" numbase="2">'));
    expect(scoreFromMei(xml).measures.single.tuplets,
        const [TupletSpan(0, 2, actual: 3, normal: 2)]);
  });

  // A minimal MEI wrapper around one measure body (staff 1 / layer 1).
  String meiWith(String layerBody,
          {String? extraSection, String? extraChild}) =>
      '''
<mei xmlns="http://www.music-encoding.org/ns/mei">
 <music><body><mdiv><score>
  <scoreDef><staffGrp><staffDef n="1" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>
  <section>
   <measure n="1"><staff n="1"><layer n="1">$layerBody</layer></staff>${extraChild ?? ''}</measure>
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
    expect(notes.map((n) => n.pitches.single.step.name), ['c', 'd', 'e', 'f']);
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

  test('applies a <tupletSpan> control event (by note id) as a tuplet', () {
    // Professionally-encoded MEI expresses tuplets as a <tupletSpan> referencing
    // its first/last note by id, not a wrapping <tuplet> — without this the
    // notes keep their nominal, unscaled duration (hardening G17).
    final xml = meiWith(
      '<note xml:id="n1" pname="c" oct="5" dur="8"/>'
      '<note xml:id="n2" pname="d" oct="5" dur="8"/>'
      '<note xml:id="n3" pname="e" oct="5" dur="8"/>',
      extraChild: '<tupletSpan staff="1" num="3" numbase="2" '
          'startid="#n1" endid="#n3"/>',
    );
    final m = scoreFromMei(xml).measures.single;
    expect(m.tuplets, hasLength(1));
    expect(m.tuplets.single.startIndex, 0);
    expect(m.tuplets.single.endIndex, 2);
    expect(m.tuplets.single.actual, 3);
    expect(m.tuplets.single.normal, 2);
    // The tuplet scales the three eighths to 1/3 quarter each (effective dur).
    expect(m.effectiveDurationAt(0).toDouble(), closeTo(1 / 12, 1e-9));
  });

  test('a tuplet stated twice (<tuplet> AND <tupletSpan>) is read once', () {
    // The MEI sample encodings' Schubert "Lindenbaum" wraps a triplet in a
    // <tuplet> and also names it with a <tupletSpan> over the same notes. Both
    // became tuplets, overlapping — invalid in the model, so layout threw.
    final xml = meiWith(
      '<tuplet num="3" numbase="2">'
      '<note xml:id="n1" pname="c" oct="5" dur="8"/>'
      '<note xml:id="n2" pname="d" oct="5" dur="8"/>'
      '<note xml:id="n3" pname="e" oct="5" dur="8"/>'
      '</tuplet>',
      extraChild: '<tupletSpan staff="1" num="3" numbase="2" '
          'startid="#n1" endid="#n3"/>',
    );
    final tuplets = scoreFromMei(xml).measures.single.tuplets;
    expect(tuplets, hasLength(1), reason: 'one triplet, not two overlapping');
    expect((tuplets.single.startIndex, tuplets.single.endIndex), (0, 2));
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

  test('a staff absent from a measure reads empty, not another staff (G19)',
      () {
    // Two staves; measure 2 omits <staff n="2">. Staff 2 must read an empty
    // bar there, not fall back to staff 1's notes (which duplicated them).
    const xml = '''
<mei xmlns="http://www.music-encoding.org/ns/mei">
 <music><body><mdiv><score>
  <scoreDef><staffGrp>
    <staffDef n="1" clef.shape="G" clef.line="2"/>
    <staffDef n="2" clef.shape="F" clef.line="4"/>
  </staffGrp></scoreDef>
  <section>
   <measure n="1">
     <staff n="1"><layer n="1"><note pname="c" oct="5" dur="4"/></layer></staff>
     <staff n="2"><layer n="1"><note pname="c" oct="3" dur="4"/></layer></staff>
   </measure>
   <measure n="2">
     <staff n="1"><layer n="1"><note pname="d" oct="5" dur="4"/></layer></staff>
   </measure>
  </section>
 </score></mdiv></body></music>
</mei>''';
    final sys = staffSystemFromMei(xml);
    expect(sys.staves, hasLength(2));
    final bass = sys.staves[1];
    // Staff 2: C3 in bar 1, and NO notes in bar 2 (not a duplicate of the D5).
    expect(
        bass.measures[0].elements
            .whereType<NoteElement>()
            .single
            .pitches
            .single,
        const Pitch(Step.c, octave: 3));
    expect(bass.measures[1].elements.whereType<NoteElement>(), isEmpty);
  });

  test('an ornament on a note with no id still round-trips', () {
    // Regression: the ornament control event needs a startid, so the writer
    // skipped it when the note had no xml:id — silently dropping the ornament.
    // The writer now gives an ornamented, id-less note a deterministic
    // position-derived id and anchors the control event to it.
    NoteElement orn(Step s, Ornament o) => NoteElement(
          pitches: [Pitch(s, octave: 4)],
          duration: const NoteDuration(DurationBase.half),
          ornament: o,
        );
    final score = Score(
      clef: Clef.treble,
      measures: [
        Measure([orn(Step.c, Ornament.trill), orn(Step.d, Ornament.mordent)]),
      ],
    );
    final notes = scoreFromMei(scoreToMei(score))
        .measures
        .first
        .elements
        .whereType<NoteElement>()
        .toList();
    // Both ornaments survive AND land on the right note (distinct anchors).
    expect(notes[0].ornament, Ornament.trill);
    expect(notes[1].ornament, Ornament.mordent);
  });

  test('multiPartToMei keeps every part (not just the first)', () {
    NoteElement note(Step s, int o, {String? id, Ornament? orn}) => NoteElement(
          pitches: [Pitch(s, octave: o)],
          duration: const NoteDuration(DurationBase.whole),
          id: id,
          ornament: orn,
        );
    final flute = Score(
      clef: Clef.treble,
      dynamics: [const DynamicMarking('f0', DynamicLevel.ff)],
      measures: [
        Measure([note(Step.g, 4, id: 'f0', orn: Ornament.trill)]),
        Measure([note(Step.a, 4)]),
      ],
    );
    final cello = Score(
      clef: Clef.bass,
      lyrics: const [Lyric('c0', 'la')],
      measures: [
        Measure([note(Step.c, 3, id: 'c0')]),
        Measure([note(Step.d, 3)]),
      ],
    );
    final back =
        multiPartScoreFromMei(multiPartToMei(MultiPartScore([flute, cello])));
    expect(back.parts, hasLength(2), reason: 'both parts survive');
    expect(back.parts.map((p) => p.clef).toSet(), {Clef.treble, Clef.bass},
        reason: 'each part keeps its own clef');
    final notes = back.parts
        .expand((p) => p.measures.expand((m) => m.elements))
        .whereType<NoteElement>()
        .toList();
    expect(notes, hasLength(4), reason: 'all four notes across both parts');
    // Per-part markings survive with part-prefixed ids (no cross-part clash).
    expect(notes.any((n) => n.ornament == Ornament.trill), isTrue);
    expect(back.parts.any((p) => p.dynamics.isNotEmpty), isTrue);
    expect(back.parts.any((p) => p.lyrics.isNotEmpty), isTrue);
  });
}
