import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// Golden corpus per HANDOVER.md §5: ~20 small scores at fixed size,
/// covering both clefs, all durations, dots, accidentals, chords, beams,
/// rests, key and time signatures.
///
/// Goldens are platform-sensitive; the committed images were generated on
/// macOS (see README). Regenerate with `flutter test --update-goldens`.
void main() {
  setUpAll(setUpPartituraForTests);

  Future<void> golden(
    WidgetTester tester,
    String name,
    Score score, {
    PartituraTheme theme = PartituraTheme.standard,
    Set<String> highlightedIds = const {},
    double staffSpace = 10,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: StaffView(
                  score: score,
                  staffSpace: staffSpace,
                  theme: theme,
                  highlightedIds: highlightedIds,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('01 treble C major scale', (tester) async {
    await golden(
      tester,
      '01_treble_c_major_scale',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
      ),
    );
  });

  testWidgets('02 bass C major scale', (tester) async {
    await golden(
      tester,
      '02_bass_c_major_scale',
      Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:q d3 e3 f3 | g3 a3 b3 c4',
      ),
    );
  });

  testWidgets('03 note durations', (tester) async {
    await golden(
      tester,
      '03_durations',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:w | c5:h c5:h | c5:q c5 c5 c5',
      ),
    );
  });

  testWidgets('04 dotted notes', (tester) async {
    await golden(
      tester,
      '04_dotted',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:h. e5:q | a4:q. b4:e c5:h | g4:h..  g4:s g4:s',
      ),
    );
  });

  testWidgets('05 rests', (tester) async {
    await golden(
      tester,
      '05_rests',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'r:w | r:h r:q r:e r:s r:s | c5:q r:q. c5:e r:h',
      ),
    );
  });

  testWidgets('06 accidentals', (tester) async {
    await golden(
      tester,
      '06_accidentals',
      Score.simple(
        notes: 'f#4:q bb4 cn5 g##4 | dbb5:q f#4 f4 f#5',
      ),
    );
  });

  testWidgets('07 key signature 7 sharps (treble)', (tester) async {
    await golden(
      tester,
      '07_key_seven_sharps',
      Score.simple(
        keySignature: const KeySignature(7),
        notes: 'c#4:q d#4 e#4 f#4',
      ),
    );
  });

  testWidgets('08 key signature 7 flats (treble)', (tester) async {
    await golden(
      tester,
      '08_key_seven_flats',
      Score.simple(
        keySignature: const KeySignature(-7),
        notes: 'cb5:q bb4 ab4 gb4',
      ),
    );
  });

  testWidgets('09 key signatures in bass clef', (tester) async {
    await golden(
      tester,
      '09_key_bass',
      Score.simple(
        clef: Clef.bass,
        keySignature: const KeySignature(-4),
        notes: 'ab2:q bb2 c3 db3',
      ),
    );
  });

  testWidgets('10 waltz time 3/4', (tester) async {
    await golden(
      tester,
      '10_time_three_four',
      Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: 'g4:q b4 d5 | c5:h.',
      ),
    );
  });

  testWidgets('11 time signature 12/8 (two digits)', (tester) async {
    await golden(
      tester,
      '11_time_twelve_eight',
      Score.simple(
        timeSignature: const TimeSignature(12, 8),
        notes: 'c5:h. c5:h.',
      ),
    );
  });

  testWidgets('12 triads and inversions', (tester) async {
    await golden(
      tester,
      '12_chords',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4+e4+g4:h e4+g4+c5:h | d4+f4:q f4+a4 g4+b4 d5+f5+a5',
      ),
    );
  });

  testWidgets('13 chord seconds cluster', (tester) async {
    await golden(
      tester,
      '13_chord_seconds',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4+d4:h e5+f5:h | b3+c4+d4:w',
      ),
    );
  });

  testWidgets('14 beamed eighths', (tester) async {
    await golden(
      tester,
      '14_beams_eighths',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
      ),
    );
  });

  testWidgets('15 beamed sixteenths and secondary beams', (tester) async {
    await golden(
      tester,
      '15_beams_sixteenths',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:s d5 e5 f5 g5:e a5:s b5:s c6:q c5:q',
      ),
    );
  });

  testWidgets('16 beam slant clamp', (tester) async {
    await golden(
      tester,
      '16_beam_slant',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:e c5 g4 c5 c4:e e4 g4 c5',
      ),
    );
  });

  testWidgets('17 ledger lines far above and below', (tester) async {
    await golden(
      tester,
      '17_ledger_lines',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'a3:q c4 a5 c6 | e6:h g3:h',
      ),
    );
  });

  testWidgets('18 melody: Alle meine Entchen (G major)', (tester) async {
    await golden(
      tester,
      '18_melody_entchen',
      Score.simple(
        keySignature: const KeySignature(1),
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:e a4 b4 c5 d5:q d5 | e5:e e5 e5 e5 d5:h',
      ),
      staffSpace: 9,
    );
  });

  testWidgets('19 highlights and per-element colors', (tester) async {
    await golden(
      tester,
      '19_highlight',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q e4 g4 c5',
      ),
      theme: const PartituraTheme(
        elementColors: {'e0': Color(0xFF43A047)},
      ),
      highlightedIds: const {'e2'},
    );
  });

  testWidgets('20 kids theme', (tester) async {
    await golden(
      tester,
      '20_kids_theme',
      Score.simple(
        timeSignature: TimeSignature.twoFour,
        notes: 'g4:q b4 | c5:e d5 e5 f5 | g5:h',
      ),
      theme: PartituraTheme.kids,
      highlightedIds: const {'e1'},
      staffSpace: 12,
    );
  });

  testWidgets('22 ghost note during a drag', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: InteractiveStaff(
                  score: Score.simple(notes: 'c5:q | r:q'),
                  staffSpace: 12,
                  ghostDuration: NoteDuration.half,
                  onStaffTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final measure1 = staff.scoreLayout!.measureRegions[1];
    final target = tester.getTopLeft(find.bySubtype<StaffView>()) +
        staff.staffToLocal(math.Point(measure1.endX - 0.4, 1.5));
    final gesture = await tester.startGesture(target - const Offset(0, 40));
    await gesture.moveTo(target);
    await tester.pump();
    expect(staff.ghostNote, isNotNull, reason: 'golden must show the ghost');
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/22_ghost_note.png'),
    );
    await gesture.up();
  });

  testWidgets('23 fit-to-width scaling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 500,
                  child: StaffView(
                    score: Score.simple(
                      timeSignature: TimeSignature.fourFour,
                      notes: 'c4:q e4 g4 c5',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/23_fit_to_width.png'),
    );
  });

  testWidgets('24 alto clef: viola line in F major', (tester) async {
    await golden(
      tester,
      '24_alto_clef',
      Score.simple(
        clef: Clef.alto,
        keySignature: const KeySignature(-1),
        timeSignature: TimeSignature.threeFour,
        notes: 'f3:q a3 c4 | c4:e d4 e4 f4 g4:q | a4+c4:h.',
      ),
    );
  });

  testWidgets('25 tenor clef: cello line in D major', (tester) async {
    await golden(
      tester,
      '25_tenor_clef',
      Score.simple(
        clef: Clef.tenor,
        keySignature: const KeySignature(2),
        timeSignature: TimeSignature.fourFour,
        notes: 'd3:q f#3 a3 d4 | c#4:e b3 a3 g3 f#3:h',
      ),
    );
  });

  testWidgets('26 ties', (tester) async {
    await golden(
      tester,
      '26_ties',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:h~ c5:q a4:q~ | a4:h c4+e4:h~ | c4+e4:w~ | c4+e4:w',
      ),
    );
  });

  testWidgets('27 slurs', (tester) async {
    await golden(
      tester,
      '27_slurs',
      Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: 'c4:q( d4 e4) | g5:e( a5 g5 f5 e5 d5) | c5:q( c6 g4) ',
      ),
    );
  });

  testWidgets('28 tuplets', (tester) async {
    await golden(
      tester,
      '28_tuplets',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '3[c5:e d5 e5] 3[c4:e r e4] 5[g4:s a4 b4 c5 d5] e5:q',
      ),
    );
  });

  testWidgets('29 articulations', (tester) async {
    await golden(
      tester,
      '29_articulations',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: "c5:q' a4_ g4> c5^ | c4+e4:q' d5>' f4:h@",
      ),
    );
  });

  testWidgets('30 dynamics and hairpins', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 | g5:h e5:h',
    );
    await golden(
      tester,
      '30_dynamics',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        dynamics: const [
          DynamicMarking('e0', DynamicLevel.p),
          DynamicMarking('e4', DynamicLevel.ff),
          DynamicMarking('e5', DynamicLevel.mp),
        ],
        hairpins: const [
          Hairpin('e0', 'e3', HairpinType.crescendo),
          Hairpin('e4', 'e5', HairpinType.diminuendo),
        ],
      ),
    );
  });

  testWidgets('31 grace notes', (tester) async {
    await golden(
      tester,
      '31_grace_notes',
      Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: '{g4}a4:q {f4,g4}a4:q {b4}c5:q | {c4}g4:h.',
      ),
    );
  });

  testWidgets('32 fine durations and breve', (tester) async {
    await golden(
      tester,
      '32_fine_durations',
      Score.simple(
        notes: 'c5:t d5 e5 f5 g5:x a5 b5 c6 g5:t r:t a4:x r:x | c5:b',
      ),
    );
  });

  testWidgets('33 mid-score changes, repeats and voltas', (tester) async {
    await golden(
      tester,
      '33_changes_repeats',
      Score.simple(
        keySignature: const KeySignature(2),
        timeSignature: TimeSignature.fourFour,
        notes: '!repeat d4:q f#4 a4 d5 | '
            '!endrepeat !volta=1 !key=-1 !time=3/4 bb4:q c5 d5 | '
            '!volta=2 !clef=bass d3:h.',
      ),
      staffSpace: 9,
    );
  });

  testWidgets('34 two voices', (tester) async {
    await golden(
      tester,
      '34_two_voices',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 ; c4:h e4:h | '
            'g5:e f5 e5 d5 e5:h ; c4:q r b3 c4 | '
            'e5:w ; c4:q c4 c4:h',
      ),
    );
  });

  testWidgets('35 grand staff', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: GrandStaffView(
                  grandStaff: GrandStaff(
                    upper: Score.simple(
                      keySignature: const KeySignature(1),
                      timeSignature: TimeSignature.fourFour,
                      notes: 'd5:q b4 g4 b4 | c5:e d5 e5 c5 d5:h',
                    ),
                    lower: Score.simple(
                      clef: Clef.bass,
                      keySignature: const KeySignature(1),
                      timeSignature: TimeSignature.fourFour,
                      notes: 'g2:h d3:h | c3:q e3 g3+b3:h',
                    ),
                  ),
                  staffSpace: 9,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/35_grand_staff.png'),
    );
  });

  testWidgets('21 unmetered snippet in bass with chords', (tester) async {
    await golden(
      tester,
      '21_bass_unmetered_chords',
      Score.simple(
        clef: Clef.bass,
        keySignature: const KeySignature(2),
        notes: 'd3:q f#3+a3 d3+f#3+a3:h | g2+b2+d3:w',
      ),
    );
  });

  testWidgets('36 multi-system line breaking', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 420,
                  child: MultiSystemView(
                    score: Score.simple(
                      keySignature: const KeySignature(1),
                      timeSignature: TimeSignature.fourFour,
                      notes: 'g4:q a4 b4 c5 | d5:e c5 b4 a4 g4:h |'
                          'e4:q g4 b4 d5 | c5:q a4 f#4 d4 |'
                          'g4:e a4 b4 c5 d5:q g5 | f#5:q e5 d5 c5 | g4:w',
                    ),
                    staffSpace: 9,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/36_multi_system.png'),
    );
  });

  testWidgets('37 lyrics with hyphens and extender', (tester) async {
    await golden(
      tester,
      '37_lyrics',
      theme: const PartituraTheme(textFontFamily: 'Roboto'),
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q c4 g4 g4 | a4:q a4 g4:q g4 | f4:q f4 e4 e4 |'
            'd4:q d4 c4:h',
        lyrics: 'Twin- kle twin- kle lit- tle star_ * how I won- der '
            'what you are',
      ),
    );
  });

  testWidgets('38 chord symbols above the staff', (tester) async {
    await golden(
      tester,
      '38_chord_symbols',
      theme: const PartituraTheme(textFontFamily: 'Roboto'),
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4+e4+g4:h a3+c4+e4:h | f3+a3+c4:h g3+b3+d4:h | c4+e4+g4:w',
        annotations: 'C Am F G7 C',
      ),
    );
  });

  testWidgets('40 accidental stacking in dense chords', (tester) async {
    await golden(
      tester,
      '40_accidental_stacking',
      Score.simple(
        notes: 'f#4+f#5:h c#4+d#4+e#4:h | c#4+f#4+a#4+c#5+f#5:w |'
            'bb3+eb4+ab4+db5:w',
      ),
    );
  });

  testWidgets('41 ornaments', (tester) async {
    await golden(
      tester,
      '41_ornaments',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: r'c5:q% d5$ e5& f5? | g5:h@% c6:h?',
      ),
    );
  });

  testWidgets('42 multi-measure rest', (tester) async {
    await golden(
      tester,
      '42_multi_rest',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | !mrest=16 | g4:w',
      ),
    );
  });

  testWidgets('43 octave clefs and ottava bracket', (tester) async {
    final base = Score.simple(
      clef: Clef.treble8vb,
      timeSignature: TimeSignature.fourFour,
      notes: 'c3:q e3 g3 c4 | c6:q d6 e6 f6 | g5:w',
    );
    await golden(
      tester,
      '43_octave_clefs_ottava',
      theme: const PartituraTheme(textFontFamily: 'Roboto'),
      Score(
        clef: base.clef,
        keySignature: base.keySignature,
        timeSignature: base.timeSignature,
        measures: base.measures,
        ottavas: const [Ottava('e4', 'e7')],
      ),
    );
  });

  testWidgets('44 navigation marks', (tester) async {
    await golden(
      tester,
      '44_navigation_marks',
      theme: const PartituraTheme(textFontFamily: 'Roboto'),
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '!nav=segno c4:q e4 g4 e4 | !nav=fine g4:q e4 c4 r | '
            '!nav=coda c4:q e4 g4 c5 | !nav=dalSegnoAlFine g4:h e4',
      ),
      staffSpace: 9,
    );
  });

  testWidgets('45 fingering numbers', (tester) async {
    await golden(
      tester,
      '45_fingerings',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q=1 d4:q=2 e4:q=3 f4:q=4 | g4:q=5 e4:q=3 c4:q=1 r:q | '
            'c4+e4+g4:h=1,3,5 r:h',
      ),
      staffSpace: 9,
    );
  });

  testWidgets('46 arpeggiated chords', (tester) async {
    NoteElement roll(String pitches, Arpeggio dir) => NoteElement(
          pitches: [for (final p in pitches.split('+')) Pitch.parse(p)],
          duration: NoteDuration.half,
          arpeggio: dir,
        );
    await golden(
      tester,
      '46_arpeggios',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            roll('c4+e4+g4+c5', Arpeggio.up),
            roll('d4+f4+a4+d5', Arpeggio.down),
          ]),
        ],
      ),
      staffSpace: 10,
    );
  });

  testWidgets('47 glissando', (tester) async {
    await golden(
      tester,
      '47_glissando',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            NoteElement.note(Pitch.parse('c4'), NoteDuration.half, id: 'a'),
            NoteElement.note(Pitch.parse('g5'), NoteDuration.half, id: 'b'),
          ]),
        ],
        glissandos: const [Glissando('a', 'b')],
      ),
      staffSpace: 10,
    );
  });

  testWidgets('48 tremolo', (tester) async {
    NoteElement trem(String pitch, int strokes) => NoteElement.note(
          Pitch.parse(pitch),
          NoteDuration.quarter,
          tremolo: strokes,
        );
    await golden(
      tester,
      '48_tremolo',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            trem('b4', 1),
            trem('b4', 2),
            trem('b4', 3),
            trem('g4', 3),
          ]),
        ],
      ),
      staffSpace: 10,
    );
  });

  testWidgets('49 pedal marks', (tester) async {
    await golden(
      tester,
      '49_pedal',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            NoteElement.note(Pitch.parse('c4'), NoteDuration.quarter, id: 'a'),
            NoteElement.note(Pitch.parse('e4'), NoteDuration.quarter),
            NoteElement.note(Pitch.parse('g4'), NoteDuration.quarter),
            NoteElement.note(Pitch.parse('c5'), NoteDuration.quarter, id: 'd'),
          ]),
        ],
        pedals: const [Pedal('a', 'd')],
      ),
      staffSpace: 10,
    );
  });

  testWidgets('50 feathered beams', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:e a4 b4 c5 d5 e5 f5 g5 | g5:e f5 e5 d5 c5 b4 a4 g4',
    );
    await golden(
      tester,
      '50_feathered_beams',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        featheredBeams: const [
          FeatheredBeam('e0', 'e7', beginBeams: 1, endBeams: 4), // accel.
          FeatheredBeam('e8', 'e15', beginBeams: 4, endBeams: 1), // rit.
        ],
      ),
      staffSpace: 10,
    );
  });

  testWidgets('51 forced horizontal beam', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
    );
    await golden(
      tester,
      '51_beam_slant',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        // One horizontal beam over the whole ascending run (would slope up).
        beamSlants: const [BeamSlant('e0', 'e7')],
      ),
      staffSpace: 10,
    );
  });

  Future<void> tabGolden(
    WidgetTester tester,
    String name,
    Score score,
    Tuning tuning, {
    double staffSpace = 12,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: TabStaffView(
                  score: score,
                  tuning: tuning,
                  staffSpace: staffSpace,
                  theme: const PartituraTheme(textFontFamily: 'Roboto'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('52 guitar tab: open strings, melody, chords', (tester) async {
    await tabGolden(
      tester,
      '52_tab_basic',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'e2:q a2 d3 g3 | b3:q e4 g4 b4 | '
            'c3:q e3 g3 c4 | e2+b2+e4:h a2+e3+a3:h',
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('53 guitar tab: rhythm (beams, flags, stems)', (tester) async {
    await tabGolden(
      tester,
      '53_tab_rhythm',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'e2:e a2 d3 g3 b3:s e4 g4 b4 | '
            'e3:q a2:e d3 g3:q | e2:h a2+e3+a3:h',
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('54 guitar tab: slides + hammer-on/pull-off', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'd3:q( f3) a3:q c4 | e3:q( g3) b3:q d4',
    );
    await tabGolden(
      tester,
      '54_tab_techniques',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        slurs: base.slurs, // ( ) → hammer-on/pull-off arcs
        glissandos: const [
          Glissando('e2', 'e3'), // a3 → c4 slide
          Glissando('e6', 'e7'), // b3 → d4 slide
        ],
      ),
      Tuning.standardGuitar,
    );
  });
}
