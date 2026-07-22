import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The MuseScore subset codec: a `.mscx` document ↔ [Score] for the shared
/// musical data. Because a subset-only score writes and reads back through the
/// one model, the round-trip is exact; where MuseScore cannot express a
/// crisp_notation feature (or vice versa) the loss is documented and asserted.
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

  test('a durationType shorter than a 64th (256th) clamps instead of throwing',
      () {
    // Real MuseScore scores occasionally carry a 128th/256th (a fast ornament).
    // No DurationBase represents them; the reader must clamp to a 64th so the
    // whole score still loads rather than throw a FormatException.
    final mscx = scoreToMscx(Score.simple(notes: 'c4:e')).replaceAll(
        '<durationType>eighth</durationType>',
        '<durationType>256th</durationType>');
    expect(mscx, contains('256th'));
    late Score back;
    expect(() => back = scoreFromMscx(mscx), returnsNormally);
    final note =
        back.measures.expand((m) => m.elements).whereType<NoteElement>().first;
    expect(note.duration.base, DurationBase.sixtyFourth);
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

  test('a drum staff maps hits to their drumset line and notehead', () {
    // A percussion part with a drumset: closed hi-hat (cross head, top line),
    // snare (normal, middle line), bass drum (normal, below middle). MuseScore
    // line: top = 0, increasing downward.
    const mscx = '''
<?xml version="1.0" encoding="UTF-8"?>
<museScore version="4.20">
  <Score>
    <Part id="1">
      <Staff id="1"/>
      <trackName>Drumset</trackName>
      <Instrument>
        <Drum pitch="36"><head>normal</head><line>6</line><name>Bass Drum</name></Drum>
        <Drum pitch="38"><head>normal</head><line>4</line><name>Snare</name></Drum>
        <Drum pitch="42"><head>cross</head><line>0</line><name>Closed Hi-Hat</name></Drum>
      </Instrument>
    </Part>
    <Staff id="1">
      <Measure><voice>
        <Clef><concertClefType>PERC</concertClefType></Clef>
        <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
        <Chord><durationType>quarter</durationType>
          <Note><pitch>42</pitch></Note></Chord>
        <Chord><durationType>quarter</durationType>
          <Note><pitch>38</pitch></Note></Chord>
        <Chord><durationType>quarter</durationType>
          <Note><pitch>36</pitch></Note></Chord>
      </voice></Measure>
    </Staff>
  </Score>
</museScore>''';
    final score = scoreFromMscx(mscx);
    expect(score.clef, Clef.percussion);
    final notes =
        score.measures.single.elements.whereType<NoteElement>().toList();
    expect(notes, hasLength(3));
    // The hi-hat is drawn with an x head; snare and bass keep the normal oval.
    expect(notes[0].notehead, NoteheadShape.x); // hi-hat
    expect(notes[1].notehead, NoteheadShape.normal); // snare
    expect(notes[2].notehead, NoteheadShape.normal); // bass
    // Each hit lands on its drumset line (position = 8 - line): hi-hat top,
    // snare in the middle, bass below — so vertically hi-hat > snare > bass.
    expect(notes[0].pitches.single, Clef.percussion.pitchAt(8)); // line 0
    expect(notes[1].pitches.single, Clef.percussion.pitchAt(4)); // line 4
    expect(notes[2].pitches.single, Clef.percussion.pitchAt(2)); // line 6
    expect(notes[0].pitches.single.diatonicIndex,
        greaterThan(notes[1].pitches.single.diatonicIndex));
    expect(notes[1].pitches.single.diatonicIndex,
        greaterThan(notes[2].pitches.single.diatonicIndex));
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

  test('round-trips a tuplet (<Tuplet>/<endTuplet>)', () {
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
    final mscx = scoreToMscx(source);
    expect(mscx, contains('<Tuplet>'));
    expect(mscx, contains('<endTuplet/>'));
    expect(scoreFromMscx(mscx).measures.single.tuplets,
        const [TupletSpan(0, 2, actual: 3, normal: 2)]);
  });

  test('round-trips a slur (<Spanner type="Slur">)', () {
    final source = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
              pitches: [const Pitch(Step.c, octave: 5)],
              duration: NoteDuration.quarter,
              id: 'a'),
          NoteElement(
              pitches: [const Pitch(Step.d, octave: 5)],
              duration: NoteDuration.quarter,
              id: 'b'),
          NoteElement(
              pitches: [const Pitch(Step.e, octave: 5)],
              duration: NoteDuration.quarter,
              id: 'c'),
        ]),
      ],
      slurs: const [Slur('a', 'c')],
    );
    final mscx = scoreToMscx(source);
    expect(mscx, contains('<Spanner type="Slur">'));
    final back = scoreFromMscx(mscx);
    expect(back.slurs.length, 1);
    final ids = back.measures.single.elements.map((e) => e.id).toList();
    expect(back.slurs.single.startId, ids.first);
    expect(back.slurs.single.endId, ids.last);
  });

  test('a slur in voice 2 round-trips (not just voice 1)', () {
    // Regression: MuseScore supports four voices and slurs, but the writer only
    // gave voice-1 notes an onset (so a voice-2 slur was skipped) and the reader
    // only tracked slur spanners in voice 0 — so a slur on voice 2 vanished
    // even though its notes round-tripped.
    NoteElement note(String id, Step step) => NoteElement(
        pitches: [Pitch(step, octave: 5)],
        duration: NoteDuration.quarter,
        id: id);
    final source = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure(
          [
            for (final s in [Step.c, Step.d, Step.e, Step.f])
              note('a${s.name}', s)
          ],
          voice2: [
            for (final s in [Step.g, Step.a, Step.b, Step.c])
              note('b${s.name}', s)
          ],
        ),
      ],
      slurs: const [Slur('bg', 'bc'), Slur('ac', 'af')], // voice-2 and voice-1
    );
    final back = scoreFromMscx(scoreToMscx(source));
    expect(back.slurs, hasLength(2));
    final v1 = back.measures.single.elements.whereType<NoteElement>().toList();
    final v2 = back.measures.single.voice2.whereType<NoteElement>().toList();
    // One slur spans voice 1 first→last, the other spans voice 2 first→last.
    expect(
      back.slurs.map((s) => (s.startId, s.endId)).toSet(),
      {(v1.first.id, v1.last.id), (v2.first.id, v2.last.id)},
    );
  });

  test('every ornament survives export (no silent drop)', () {
    // Regression: the writer's ornament map covered only trill/shortTrill/
    // mordent/turn, so invertedTurn and the accidental trills vanished on
    // export. invertedTurn now round-trips exactly; an accidental trill degrades
    // to a plain trill (MuseScore has no single-glyph accidental trill), like
    // the other codecs — but is never dropped.
    Ornament? roundTrip(Ornament o) {
      final s = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            NoteElement(
                pitches: [const Pitch(Step.c, octave: 4)],
                duration: NoteDuration.whole,
                id: 'a',
                ornament: o),
          ]),
        ],
      );
      return (scoreFromMscx(scoreToMscx(s)).measures.single.elements.single
              as NoteElement)
          .ornament;
    }

    for (final o in Ornament.values) {
      expect(roundTrip(o), isNotNull, reason: '$o was dropped on export');
    }
    expect(roundTrip(Ornament.invertedTurn), Ornament.invertedTurn);
    expect(
        roundTrip(Ornament.trillSharp), Ornament.trill); // documented degrade
  });

  test('multiPartToMscx keeps every part (not just the first)', () {
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
    final mscx = multiPartToMscx(MultiPartScore([flute, cello]));
    // No multi-part reader for mscx; read each staff back by index.
    final p0 = scoreFromMscx(mscx, staffIndex: 0);
    final p1 = scoreFromMscx(mscx, staffIndex: 1);
    expect(p0.clef, Clef.treble);
    expect(p1.clef, Clef.bass, reason: 'the second part is not dropped');
    expect(p0.measures, hasLength(2));
    expect(p1.measures, hasLength(2));
    expect(
      p0.measures
          .expand((m) => m.elements.whereType<NoteElement>())
          .any((n) => n.ornament == Ornament.trill),
      isTrue,
    );
    expect(p0.dynamics, isNotEmpty);
    expect(p1.lyrics, isNotEmpty);
  });

  test('multiPartScoreFromMscx reads every staff back into parts', () {
    NoteElement note(Step s, int o) => NoteElement(
        pitches: [Pitch(s, octave: o)], duration: NoteDuration.whole);
    final flute = Score(clef: Clef.treble, measures: [
      Measure([note(Step.g, 5)]),
      Measure([note(Step.a, 5)]),
    ]);
    final cello = Score(clef: Clef.bass, measures: [
      Measure([note(Step.c, 3)]),
      Measure([note(Step.d, 3)]),
    ]);
    final mscx = multiPartToMscx(MultiPartScore([flute, cello]),
        partNames: ['Flute', 'Cello']);
    final mp = multiPartScoreFromMscx(mscx);
    expect(mp.parts, hasLength(2), reason: 'both staves read back');
    expect(mp.parts.map((p) => p.clef).toSet(), {Clef.treble, Clef.bass});
    expect(
        mp.parts.map((p) => p.metadata.instrument).toSet(), {'Flute', 'Cello'},
        reason: 'each part keeps its own instrument name');
    // Staff-prefixed ids stay unique across parts.
    final ids = mp.parts
        .expand((p) => p.measures.expand((m) => m.elements.map((e) => e.id)))
        .toList();
    expect(ids.toSet(), hasLength(ids.length),
        reason: 'ids unique across parts');
  });
}
