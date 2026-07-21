import 'package:crisp_notation_core/crisp_notation_core.dart';
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

  // A one-bar score on reachable pitches, ids e0.., carrying tab-mark styles.
  Score marked(List<TabNoteMark> marks) {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 e5',
    );
    return Score(
      clef: base.clef,
      timeSignature: base.timeSignature,
      measures: base.measures,
      tabNoteMarks: marks,
    );
  }

  test('every tab-note style survives export (dead/ghost/all harmonics)', () {
    // Regression: ghost notes were silently dropped (the writer no-op'd them),
    // and only the natural/artificial/pinch harmonics were covered.
    for (final style in TabNoteStyle.values) {
      final back =
          scoreFromGpif(scoreToGpif(marked([TabNoteMark('e0', style)])));
      expect(back.tabNoteMarks, [TabNoteMark('e0', style)],
          reason: '$style did not round-trip');
    }
  });

  test('wide (whammy) vibrato keeps its width', () {
    // Regression: the writer always emitted the narrow <Vibrato>, so a wide
    // vibrato came back as normal. It now emits <VibratoWTremBar>.
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4',
    );
    Score withVib(bool wide) => Score(
          clef: base.clef,
          timeSignature: base.timeSignature,
          measures: base.measures,
          vibratos: [Vibrato('e0', wide: wide)],
        );
    expect(scoreFromGpif(scoreToGpif(withVib(false))).vibratos,
        [const Vibrato('e0', wide: false)]);
    expect(scoreFromGpif(scoreToGpif(withVib(true))).vibratos,
        [const Vibrato('e0', wide: true)]);
  });

  test('bend contours round-trip (prebend, bend-release, dive)', () {
    // Regression: the writer only emitted a single BendDestinationValue, so any
    // multi-point contour collapsed to a plain full bend. It now writes the
    // GPIF origin/middle/destination points.
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:w',
    );
    Score withBend(Bend b) => Score(
          clef: base.clef,
          timeSignature: base.timeSignature,
          measures: base.measures,
          bends: [b],
        );
    final contours = <List<BendPoint>>[
      [const BendPoint(0, 0), const BendPoint(0.5, 1), const BendPoint(1, 0)],
      [const BendPoint(0, 1), const BendPoint(1, 1)],
      [const BendPoint(0, 1), const BendPoint(1, 0)],
      [const BendPoint(0, 0), const BendPoint(0.5, -1), const BendPoint(1, 0)],
    ];
    for (final pts in contours) {
      final back = scoreFromGpif(scoreToGpif(withBend(Bend.curve('e0', pts))));
      expect(back.bends, [Bend.curve('e0', pts)], reason: 'contour $pts');
    }
    // A plain bend still comes back plain, not as a curve.
    expect(
        scoreFromGpif(scoreToGpif(withBend(const Bend('e0', steps: 0.5))))
            .bends,
        [const Bend('e0', steps: 0.5)]);
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

  test('a mid-score time-signature change round-trips', () {
    // Regression: only the FIRST <Time> was captured, so a meter change was
    // silently lost (the whole piece reported the initial meter).
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement(
              pitches: [Pitch(Step.g, octave: 4)],
              duration: NoteDuration(DurationBase.whole))
        ]),
        Measure(
          [
            NoteElement(
                pitches: [Pitch(Step.a, octave: 4)],
                duration: NoteDuration(DurationBase.half, dots: 1))
          ],
          timeChange: const TimeSignature(3, 4),
        ),
        Measure([
          NoteElement(
              pitches: [Pitch(Step.b, octave: 4)],
              duration: NoteDuration(DurationBase.half, dots: 1))
        ]),
      ],
    );
    final back = scoreFromGpif(scoreToGpif(score));
    expect(back.timeSignature, TimeSignature.fourFour, reason: 'initial meter');
    expect(back.measures[1].timeChange, const TimeSignature(3, 4),
        reason: 'the 3/4 change is kept on bar 2');
    // No spurious change on the bar that stays in 3/4.
    expect(back.measures[2].timeChange, isNull, reason: 'bar 3 stays 3/4');
  });

  test('single-track output is unchanged (golden)', () {
    // Locks scoreToGpif's bytes against the pre-multi-track implementation.
    final gpif = scoreToGpif(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e2:q g2 c3 e3 | g4:h a4',
    ));
    expect(gpif, _singleTrackGolden);
  });

  group('multi-track', () {
    MultiPartScore band() => MultiPartScore([
          Score.simple(
            timeSignature: TimeSignature.fourFour,
            notes: 'e4:q g4 b4 e5',
          ),
          Score.simple(
            timeSignature: TimeSignature.fourFour,
            notes: 'e1:h a1',
          ),
        ]);

    test('writes one track per part, each with its own tuning', () {
      final gpif = multiPartToGpif(band(),
          tunings: [Tuning.standardGuitar, Tuning.standardBass]);
      expect(gpifTrackNames(gpif), ['Track 1', 'Track 2']);
      expect(gpif, contains('<Track id="0">'));
      expect(gpif, contains('<Track id="1">'));
      expect(
          gpif,
          contains(
              '<Pitches>${Tuning.standardGuitar.strings.map((p) => p.midiNumber).join(' ')}</Pitches>'));
      expect(
          gpif,
          contains(
              '<Pitches>${Tuning.standardBass.strings.map((p) => p.midiNumber).join(' ')}</Pitches>'));
      // Each MasterBar references one Bar id per track.
      // Each part is one bar long, so track 0 owns bar 0 and track 1 bar 1.
      expect(gpif, contains('<Bars>0 1</Bars>'));
    });

    test('names default to the part instrument and can be overridden', () {
      final gpif = multiPartToGpif(band(), names: ['Lead', 'Bass']);
      expect(gpifTrackNames(gpif), ['Lead', 'Bass']);
    });

    test('multiPartScoreFromGpif reads every track back (all parts)', () {
      final gpif = multiPartToGpif(band(),
          tunings: [Tuning.standardGuitar, Tuning.standardBass]);
      final back = multiPartScoreFromGpif(gpif);
      expect(back.parts, hasLength(2)); // both tracks, not just track 0
      List<String> steps(Score s) => [
            for (final m in s.measures)
              for (final e in m.elements)
                if (e is NoteElement) e.pitches.first.step.name,
          ];
      expect(steps(back.parts[0]), ['e', 'g', 'b', 'e']); // guitar line
      expect(steps(back.parts[1]), ['e', 'a']); // bass line
    });

    test('both parts round-trip through scoreFromGpif with their tunings', () {
      final source = band();
      final gpif = multiPartToGpif(source,
          tunings: [Tuning.standardGuitar, Tuning.standardBass],
          names: ['Guitar', 'Bass']);

      final guitar = scoreFromGpif(gpif, trackIndex: 0);
      final bass = scoreFromGpif(gpif, trackIndex: 1);
      expect(pitchNames(guitar), pitchNames(source.parts[0]));
      expect(pitchNames(bass), pitchNames(source.parts[1]));
      expect(guitar.measures, hasLength(1));
      expect(bass.measures, hasLength(1));
      expect(
        bass.measures.single.elements.whereType<NoteElement>().first.duration,
        NoteDuration.half,
      );
    });

    test('round-trips through the .gp container', () {
      final source = band();
      final bytes = writeGpFromGpif(multiPartToGpif(source,
          tunings: [Tuning.standardGuitar, Tuning.standardBass]));
      final gpif = readGpifFromGp(bytes);
      expect(pitchNames(scoreFromGpif(gpif)), pitchNames(source.parts[0]));
      expect(pitchNames(scoreFromGpif(gpif, trackIndex: 1)),
          pitchNames(source.parts[1]));
    });

    test('a low bass part is unreachable on a guitar tuning', () {
      // The default tuning applies when tunings is short — the E1 notes then
      // fall off the fretboard, which is the documented drop behaviour.
      final gpif = multiPartToGpif(band(), tunings: [Tuning.standardGuitar]);
      expect(pitchNames(scoreFromGpif(gpif, trackIndex: 1)), isEmpty);
    });

    test('techniques survive per track', () {
      final lead = Score.simple(
          timeSignature: TimeSignature.fourFour, notes: 'e4:q g4 b4 e5');
      final ids = lead.measures.single.elements.map((e) => e.id!).toList();
      final withTech = Score(
        clef: lead.clef,
        timeSignature: lead.timeSignature,
        measures: lead.measures,
        slurs: [Slur(ids[0], ids[1])],
        bends: [Bend(ids[2], steps: 1)],
        tabNoteMarks: [TabNoteMark(ids[3], TabNoteStyle.harmonic)],
      );
      final gpif = multiPartToGpif(
        MultiPartScore([
          Score.simple(timeSignature: TimeSignature.fourFour, notes: 'e2:w'),
          withTech,
        ]),
        tunings: [Tuning.standardGuitar, Tuning.standardGuitar],
      );
      final back = scoreFromGpif(gpif, trackIndex: 1);
      expect(back.slurs, hasLength(1));
      expect(back.bends, hasLength(1));
      expect(back.tabNoteMarks.single.style, TabNoteStyle.harmonic);
      // Track 0 carries none of them.
      expect(scoreFromGpif(gpif).slurs, isEmpty);
    });

    test('pads a shorter part so the bar lists stay aligned', () {
      final gpif = multiPartToGpif(MultiPartScore([
        Score.simple(
            timeSignature: TimeSignature.fourFour, notes: 'e4:w | g4:w'),
        Score.simple(timeSignature: TimeSignature.fourFour, notes: 'e2:w'),
      ]));
      final short = scoreFromGpif(gpif, trackIndex: 1);
      expect(short.measures, hasLength(2),
          reason: 'padded to the longest part');
      expect(short.measures.last.elements, isEmpty);
      expect(pitchNames(scoreFromGpif(gpif)), ['E4', 'G4']);
    });
  });

  test('an explicit fretting plan overrides fretFor', () {
    final score = Score.simple(notes: 'e4:q');
    // fretFor opens the high-E string (String 0, Fret 0).
    expect(
      scoreToGpif(score),
      contains('<String>0</String></Property>'
          '<Property name="Fret"><Fret>0</Fret></Property>'),
    );
    // Pin e0 to the B string (index 1) at fret 5 — same sounding pitch, chosen
    // position. The arranger's choice must reach the .gp.
    final gpif = scoreToGpif(score, frettings: const {
      'e0': {1: 5},
    });
    expect(
      gpif,
      contains('<String>1</String></Property>'
          '<Property name="Fret"><Fret>5</Fret></Property>'),
    );
    expect(pitchNames(scoreFromGpif(gpif)), ['E4']); // pitch still round-trips
  });

  test('a TabVoicing pins the export string (arranged frets survive)', () {
    // Regression: the writer re-fretted every pitch with fretFor, discarding a
    // tab editor's string choice on .gp export. A TabVoicing now wins.
    final base =
        Score.simple(timeSignature: TimeSignature.fourFour, notes: 'e4:q');
    final score = Score(
      clef: base.clef,
      timeSignature: base.timeSignature,
      measures: base.measures,
      tabVoicings: const [
        TabVoicing('e0', [1])
      ], // the B string
    );
    final gpif = scoreToGpif(score);
    expect(
      gpif,
      contains('<String>1</String></Property>'
          '<Property name="Fret"><Fret>5</Fret></Property>'),
    );
    expect(pitchNames(scoreFromGpif(gpif)), ['E4']);
  });

  test('a voicing that does not fit the tuning falls back to fretFor', () {
    // E2 pinned to the high-E string is impossible (negative fret) → fretFor
    // still places it on the low-E string (index 5, fret 0).
    final base =
        Score.simple(timeSignature: TimeSignature.fourFour, notes: 'e2:q');
    final score = Score(
      clef: base.clef,
      timeSignature: base.timeSignature,
      measures: base.measures,
      tabVoicings: const [
        TabVoicing('e0', [0])
      ],
    );
    expect(
      scoreToGpif(score),
      contains('<String>5</String></Property>'
          '<Property name="Fret"><Fret>0</Fret></Property>'),
    );
  });

  test('voice 2 survives a round-trip', () {
    // Two independent voices in one bar; both must come back.
    final v1 = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 e5',
    );
    final v2 = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g3:q a3 b3 c4',
    );
    final src = Score(
      clef: v1.clef,
      timeSignature: v1.timeSignature,
      measures: [
        Measure(
          v1.measures.first.elements,
          voice2: v2.measures.first.elements,
        ),
      ],
    );
    final back = scoreFromGpif(scoreToGpif(src));
    final m = back.measures.single;
    expect(
      m.elements
          .whereType<NoteElement>()
          .map((n) => n.pitches.single.midiNumber),
      [67, 71, 74, 76], // voice 1: g4 b4 d5 e5
    );
    expect(
      m.voice2.whereType<NoteElement>().map((n) => n.pitches.single.midiNumber),
      [55, 57, 59, 60], // voice 2: g3 a3 b3 c4
    );
  });

  test('a tuplet round-trips (timing preserved, not inflated)', () {
    // Regression: without tuplet support a triplet's notes were read at full
    // value, so an eighth-triplet(=1 beat)+half(=2 beats) bar came back 3.5 beats.
    final src = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure(
          [
            for (final id in ['e0', 'e1', 'e2'])
              NoteElement(
                pitches: [Pitch.parse('g4')],
                duration: NoteDuration.eighth,
                id: id,
              ),
            NoteElement(
              pitches: [Pitch.parse('c4')],
              duration: NoteDuration.half,
              id: 'e3',
            ),
          ],
          tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2)],
        ),
      ],
    );
    final m = scoreFromGpif(scoreToGpif(src)).measures.single;
    expect(m.tuplets, hasLength(1));
    expect(m.tuplets.first.actual, 3);
    expect(m.tuplets.first.normal, 2);
    expect((m.tuplets.first.startIndex, m.tuplets.first.endIndex), (0, 2));

    double beats(Measure mm) {
      var b = 0.0;
      for (var i = 0; i < mm.elements.length; i++) {
        final (n, d) = mm.elements[i].duration.fraction;
        var v = n / d * 4;
        for (final t in mm.tuplets) {
          if (t.contains(i)) {
            v = v * t.normal / t.actual;
            break;
          }
        }
        b += v;
      }
      return b;
    }

    expect(beats(m), closeTo(3.0, 1e-9)); // not 3.5
  });

  test('key signature round-trips, including a mid-score change', () {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 e5 | d5:q e5 g5 a5',
    );
    final src = Score(
      clef: base.clef,
      keySignature: const KeySignature(1), // G major (one sharp)
      timeSignature: base.timeSignature,
      measures: [
        base.measures[0],
        base.measures[1].copyWith(keyChange: const KeySignature(-2)), // 2 flats
      ],
    );
    final back = scoreFromGpif(scoreToGpif(src));
    expect(back.keySignature.fifths, 1);
    expect(back.measures[1].keyChange?.fifths, -2);
  });

  test('dynamics round-trip (PPP…FFF)', () {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 e5',
    );
    final src = Score(
      clef: base.clef,
      timeSignature: base.timeSignature,
      measures: base.measures,
      dynamics: const [
        DynamicMarking('e0', DynamicLevel.pp),
        DynamicMarking('e2', DynamicLevel.ff),
      ],
    );
    final back = scoreFromGpif(scoreToGpif(src));
    final byId = {for (final d in back.dynamics) d.elementId: d.level};
    expect(byId['e0'], DynamicLevel.pp);
    expect(byId['e2'], DynamicLevel.ff);
  });

  test('staccato + accent articulations round-trip', () {
    NoteElement note(String p, String id,
            [Set<Articulation> arts = const {}]) =>
        NoteElement(
          pitches: [Pitch.parse(p)],
          duration: NoteDuration.quarter,
          id: id,
          articulations: arts,
        );
    final src = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          note('g4', 'e0', const {Articulation.staccato}),
          note('b4', 'e1'),
          note('d5', 'e2', const {Articulation.accent}),
          note('e5', 'e3'),
        ]),
      ],
    );
    final back = scoreFromGpif(scoreToGpif(src))
        .measures
        .single
        .elements
        .whereType<NoteElement>()
        .toList();
    expect(back[0].articulations, {Articulation.staccato});
    expect(back[1].articulations, isEmpty);
    expect(back[2].articulations, {Articulation.accent});
  });

  test('grace notes round-trip (order preserved, not timed)', () {
    final src = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement(
            pitches: [Pitch.parse('c5')],
            duration: NoteDuration.quarter,
            id: 'e0',
            graceNotes: [Pitch.parse('a4'), Pitch.parse('b4')],
          ),
          NoteElement(
            pitches: [Pitch.parse('d5')],
            duration: NoteDuration.quarter,
            id: 'e1',
          ),
        ]),
      ],
    );
    final els = scoreFromGpif(scoreToGpif(src))
        .measures
        .single
        .elements
        .whereType<NoteElement>()
        .toList();
    expect(els, hasLength(2)); // grace beats aren't timed elements
    expect(els[0].pitches.single.midiNumber, Pitch.parse('c5').midiNumber);
    expect(
      els[0].graceNotes.map((p) => p.midiNumber),
      [Pitch.parse('a4').midiNumber, Pitch.parse('b4').midiNumber],
    );
    expect(els[1].graceNotes, isEmpty);
  });
}

const _singleTrackGolden = '''
<?xml version="1.0" encoding="UTF-8"?>
<GPIF>
  <GPVersion>7</GPVersion>
  <Score><Title>crisp_notation</Title></Score>
  <Tracks><Track id="0"><Name>Guitar</Name><Staves><Staff><Properties><Property name="Tuning"><Pitches>64 59 55 50 45 40</Pitches></Property></Properties></Staff></Staves></Track></Tracks>
  <MasterBars>
    <MasterBar><Time>4/4</Time><Bars>0</Bars></MasterBar>
    <MasterBar><Time>4/4</Time><Bars>1</Bars></MasterBar>
  </MasterBars>
  <Bars>
    <Bar id="0"><Voices>0 -1 -1 -1</Voices></Bar>
    <Bar id="1"><Voices>1 -1 -1 -1</Voices></Bar>
  </Bars>
  <Voices>
    <Voice id="0"><Beats>0 1 2 3</Beats></Voice>
    <Voice id="1"><Beats>4 5</Beats></Voice>
  </Voices>
  <Beats>
    <Beat id="0"><Rhythm ref="0"/><Notes>0</Notes></Beat>
    <Beat id="1"><Rhythm ref="0"/><Notes>1</Notes></Beat>
    <Beat id="2"><Rhythm ref="0"/><Notes>2</Notes></Beat>
    <Beat id="3"><Rhythm ref="0"/><Notes>3</Notes></Beat>
    <Beat id="4"><Rhythm ref="1"/><Notes>4</Notes></Beat>
    <Beat id="5"><Rhythm ref="1"/><Notes>5</Notes></Beat>
  </Beats>
  <Notes>
    <Note id="0"><Properties><Property name="String"><String>5</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
    <Note id="1"><Properties><Property name="String"><String>5</String></Property><Property name="Fret"><Fret>3</Fret></Property></Properties></Note>
    <Note id="2"><Properties><Property name="String"><String>4</String></Property><Property name="Fret"><Fret>3</Fret></Property></Properties></Note>
    <Note id="3"><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>2</Fret></Property></Properties></Note>
    <Note id="4"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>3</Fret></Property></Properties></Note>
    <Note id="5"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>5</Fret></Property></Properties></Note>
  </Notes>
  <Rhythms>
    <Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm>
    <Rhythm id="1"><NoteValue>Half</NoteValue></Rhythm>
  </Rhythms>
</GPIF>
''';
