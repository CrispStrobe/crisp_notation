import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

List<String> pitchNames(Score s) => s.measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .expand((n) => n.pitches)
    .map((p) => p.toString())
    .toList();

void main() {
  test('writes a GPIF document with the expected structure', () {
    final gpif = scoreToGpif(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4',
    ));
    expect(gpif, contains('<GPIF>'));
    expect(gpif, contains('name="Tuning"'));
    expect(gpif, contains('<Pitches>'));
    expect(gpif, contains('<NoteValue>Quarter</NoteValue>'));
    expect(gpif, contains('<Property name="Fret">'));
  });

  test('round-trips pitches and durations', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e2:q g2 c3 e3 | g4:h a4',
    );
    final back = scoreFromGpif(scoreToGpif(source));
    expect(back.measures, hasLength(2));
    expect(pitchNames(back), pitchNames(source));
    final durations = back.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .map((n) => n.duration)
        .toList();
    expect(durations.last, NoteDuration.half); // a4 was a half note
  });

  test('round-trips a chord', () {
    final back = scoreFromGpif(scoreToGpif(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e2+b2+e4:w',
    )));
    final chord = back.measures.single.elements.whereType<NoteElement>().single;
    expect(chord.pitches, hasLength(3));
  });

  test('round-trips rests and dotted durations', () {
    final back = scoreFromGpif(scoreToGpif(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e2:q. r:e g3:h',
    )));
    final els = back.measures.single.elements;
    expect(els[0], isA<NoteElement>());
    expect((els[0] as NoteElement).duration,
        const NoteDuration(DurationBase.quarter, dots: 1));
    expect(els[1], isA<RestElement>());
  });

  test('recovers the time signature', () {
    final back = scoreFromGpif(scoreToGpif(Score.simple(
      timeSignature: const TimeSignature(3, 4),
      notes: 'e2:q g2 c3',
    )));
    expect(back.timeSignature, const TimeSignature(3, 4));
  });

  test('a drop-D tuning round-trips its low note', () {
    // Low D2 is only reachable on the dropped 6th string.
    final source = Score.simple(notes: 'd2:q');
    final back = scoreFromGpif(scoreToGpif(source, tuning: Tuning.dropDGuitar));
    expect(pitchNames(back), ['D2']);
  });

  test('parses playing techniques into tab marks', () {
    // A hand-written GPIF (the shape the .gp apps emit): note 0 hammers to
    // note 1 which is bent full; note 2 is dead; note 3 is a harmonic.
    const gpif = '''
<GPIF>
  <Tracks><Track id="0"><Staves><Staff><Properties>
    <Property name="Tuning"><Pitches>64 59 55 50 45 40</Pitches></Property>
  </Properties></Staff></Staves></Track></Tracks>
  <MasterBars><MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar></MasterBars>
  <Bars><Bar id="0"><Voices>0 -1 -1 -1</Voices></Bar></Bars>
  <Voices><Voice id="0"><Beats>0 1 2 3</Beats></Voice></Voices>
  <Beats>
    <Beat id="0"><Rhythm ref="0"/><Notes>0</Notes></Beat>
    <Beat id="1"><Rhythm ref="0"/><Notes>1</Notes></Beat>
    <Beat id="2"><Rhythm ref="0"/><Notes>2</Notes></Beat>
    <Beat id="3"><Rhythm ref="0"/><Notes>3</Notes></Beat>
  </Beats>
  <Notes>
    <Note id="0"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>5</Fret></Property><Property name="HopoOrigin"><Enable/></Property></Properties></Note>
    <Note id="1"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>7</Fret></Property><Property name="Bended"><Enable/></Property><Property name="BendDestinationValue"><Float>100</Float></Property></Properties></Note>
    <Note id="2"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>3</Fret></Property><Property name="Muted"><Enable/></Property></Properties></Note>
    <Note id="3"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>12</Fret></Property><Property name="Harmonic"><Enable/></Property></Properties></Note>
  </Notes>
  <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
</GPIF>''';
    final score = scoreFromGpif(gpif);
    expect(score.slurs, [const Slur('e0', 'e1')]); // hammer-on
    expect(score.bends, [const Bend('e1')]); // full bend (100/100)
    expect(
      score.tabNoteMarks,
      containsAll([
        const TabNoteMark('e2', TabNoteStyle.dead),
        const TabNoteMark('e3', TabNoteStyle.harmonic),
      ]),
    );
  });

  test('round-trips techniques through export + import', () {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 e5 g5',
    );
    final source = Score(
      clef: base.clef,
      timeSignature: base.timeSignature,
      measures: base.measures,
      slurs: const [Slur('e0', 'e1')], // hammer-on
      glissandos: const [Glissando('e1', 'e2')], // slide
      bends: const [Bend('e2', steps: 1.5)],
      vibratos: const [Vibrato('e3')],
      tabNoteMarks: const [TabNoteMark('e4', TabNoteStyle.dead)],
    );
    final back = scoreFromGpif(scoreToGpif(source));
    expect(back.slurs, [const Slur('e0', 'e1')]);
    expect(back.glissandos, [const Glissando('e1', 'e2')]);
    expect(back.bends, [const Bend('e2', steps: 1.5)]);
    expect(back.vibratos, [const Vibrato('e3')]);
    expect(back.tabNoteMarks, [const TabNoteMark('e4', TabNoteStyle.dead)]);
  });

  test('selects a track by index from a multi-track GPIF', () {
    const gpif = '''
<GPIF>
  <Tracks>
    <Track id="0"><Name>Gtr</Name><Staves><Staff><Properties>
      <Property name="Tuning"><Pitches>64 59 55 50 45 40</Pitches></Property>
    </Properties></Staff></Staves></Track>
    <Track id="1"><Name>Bass</Name><Staves><Staff><Properties>
      <Property name="Tuning"><Pitches>43 38 33 28</Pitches></Property>
    </Properties></Staff></Staves></Track>
  </Tracks>
  <MasterBars><MasterBar><Time>4/4</Time><Bars>0 1</Bars></MasterBar></MasterBars>
  <Bars>
    <Bar id="0"><Voices>0 -1 -1 -1</Voices></Bar>
    <Bar id="1"><Voices>1 -1 -1 -1</Voices></Bar>
  </Bars>
  <Voices>
    <Voice id="0"><Beats>0</Beats></Voice>
    <Voice id="1"><Beats>1</Beats></Voice>
  </Voices>
  <Beats>
    <Beat id="0"><Rhythm ref="0"/><Notes>0</Notes></Beat>
    <Beat id="1"><Rhythm ref="0"/><Notes>1</Notes></Beat>
  </Beats>
  <Notes>
    <Note id="0"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>3</Fret></Property></Properties></Note>
    <Note id="1"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>3</Fret></Property></Properties></Note>
  </Notes>
  <Rhythms><Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm></Rhythms>
</GPIF>''';
    expect(gpifTrackNames(gpif), ['Gtr', 'Bass']);
    expect(
        pitchNames(scoreFromGpif(gpif, trackIndex: 0)), ['G4']); // e-string f3
    expect(
        pitchNames(scoreFromGpif(gpif, trackIndex: 1)), ['A#2']); // g-string f3
  });

  test('rejects non-GPIF input', () {
    expect(() => scoreFromGpif('<Other></Other>'), throwsFormatException);
  });
}
