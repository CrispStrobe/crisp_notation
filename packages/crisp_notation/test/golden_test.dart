import 'dart:math' as math;

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step, PageMetrics;
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

/// Golden corpus: ~20 small scores at fixed size,
/// covering both clefs, all durations, dots, accidentals, chords, beams,
/// rests, key and time signatures.
///
/// Goldens are platform-sensitive; the committed images were generated on
/// macOS (see README). Regenerate with `flutter test --update-goldens`.
void main() {
  setUpAll(setUpCrispNotationForTests);

  Future<void> golden(
    WidgetTester tester,
    String name,
    Score score, {
    CrispNotationTheme theme = CrispNotationTheme.standard,
    Set<String> highlightedIds = const {},
    Map<String, Color> elementColors = const {},
    double staffSpace = 10,
    NoteheadScheme noteheadScheme = NoteheadScheme.normal,
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
                  elementColors: elementColors,
                  noteheadScheme: noteheadScheme,
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
      theme: const CrispNotationTheme(
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
      theme: CrispNotationTheme.kids,
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

  testWidgets('90 three voices', (tester) async {
    await golden(
      tester,
      '90_three_voices',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g5:q a5 b5 c6 ; e5:q f5 e5 d5 ; c4:h g4:h | '
            'b5:h a5:h ; g5:q f5 e5 r ; c4:w',
      ),
    );
  });

  testWidgets('91 four voices', (tester) async {
    await golden(
      tester,
      '91_four_voices',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 ; a4:q g4 a4 g4 ; e4:h f4:h ; c4:h r:h | '
            'g5:h e5:h ; e5:q d5 c5 d5 ; g4:h a4:h ; c4:w',
      ),
    );
  });

  testWidgets('92 non-standard key signature', (tester) async {
    await golden(
      tester,
      '92_custom_key_signature',
      Score.simple(
        // A mixed B♭ + F♯ signature the circle of fifths cannot express.
        keySignature: const KeySignature.custom([
          KeyAccidental(Step.b, -1),
          KeyAccidental(Step.f, 1),
        ]),
        timeSignature: TimeSignature.fourFour,
        // B and F sit in the signature (no accidental); a B natural cancels.
        notes: 'f4:q b4 f5 bn4',
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

  testWidgets('94 cross-staff beam', (tester) async {
    NoteElement n(Step step, int oct, String id) =>
        NoteElement.note(Pitch(step, octave: oct), NoteDuration.eighth, id: id);
    // A broken-chord figure that climbs from the bass staff into the treble
    // under one beam: two eighths on each staff, at four successive slots.
    final grand = GrandStaff(
      upper: Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            const RestElement(NoteDuration.eighth, id: 'ur0'),
            const RestElement(NoteDuration.eighth, id: 'ur1'),
            n(Step.g, 4, 'u0'),
            n(Step.c, 5, 'u1'),
            const RestElement(NoteDuration.half, id: 'ur2'),
          ]),
        ],
      ),
      lower: Score(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            n(Step.c, 3, 'l0'),
            n(Step.e, 3, 'l1'),
            const RestElement(NoteDuration.eighth, id: 'lr0'),
            const RestElement(NoteDuration.eighth, id: 'lr1'),
            const RestElement(NoteDuration.half, id: 'lr2'),
          ]),
        ],
      ),
      crossStaffBeams: const [
        CrossStaffBeam(['l0', 'l1', 'u0', 'u1'])
      ],
    );
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
                child: GrandStaffView(grandStaff: grand, staffSpace: 9),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/94_cross_staff_beam.png'),
    );
  });

  testWidgets('95 wrapped grand staff', (tester) async {
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
                  width: 320,
                  child: InteractiveGrandStaffView(
                    staffSpace: 9,
                    grandStaff: GrandStaff(
                      upper: Score.simple(
                        timeSignature: TimeSignature.fourFour,
                        notes: 'c5:q d5 e5 f5 | g5:q a5 b5 c6 | '
                            'c6:q b5 a5 g5 | f5:h e5',
                      ),
                      lower: Score.simple(
                        clef: Clef.bass,
                        timeSignature: TimeSignature.fourFour,
                        notes: 'c3:h e3 | g3:h c4 | e3:h c3 | g2:h c3',
                      ),
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
      matchesGoldenFile('goldens/95_grand_staff_wrapped.png'),
    );
  });

  testWidgets('96 cross-staff onset gridding', (tester) async {
    // Rhythmically-different hands: eight upper eighths over four lower
    // quarters. Each lower quarter lines up under the upper eighth on its beat.
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
                  staffSpace: 10,
                  grandStaff: GrandStaff(
                    upper: Score.simple(
                      timeSignature: TimeSignature.fourFour,
                      notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
                    ),
                    lower: Score.simple(
                      clef: Clef.bass,
                      timeSignature: TimeSignature.fourFour,
                      notes: 'c3:q g3 c3 g3',
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
      matchesGoldenFile('goldens/96_cross_staff_gridding.png'),
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

  testWidgets('109 editor overlay: error marks + loop band', (tester) async {
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
                  width: 300,
                  child: MultiSystemView(
                    score: Score.simple(
                      timeSignature: TimeSignature.fourFour,
                      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | '
                          'c5:q b4 a4 g4 | f4:q e4 d4 c4',
                    ),
                    staffSpace: 9,
                    // A wrong note (red) and a correct one (green), each marked.
                    errorOverlay: const {
                      'e2':
                          EditorMark(Color(0xFFD32F2F), message: 'out of key'),
                      'e9': EditorMark(Color(0xFF388E3C)),
                    },
                    // A loop band over the second measure (ids e4..e7).
                    loopRange: ('e4', 'e7'),
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
      matchesGoldenFile('goldens/109_editor_overlay.png'),
    );
  });

  testWidgets('111 grand-staff editor overlay: marks + loop band across staves',
      (tester) async {
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
                  width: 320,
                  child: InteractiveGrandStaffView(
                    staffSpace: 9,
                    grandStaff: GrandStaff(
                      upper: Score.simple(
                        timeSignature: TimeSignature.fourFour,
                        notes: 'c5:q d5 e5 f5 | g5:q a5 b5 c6 | '
                            'c6:q b5 a5 g5 | f5:h e5',
                      ),
                      lower: Score.simple(
                        clef: Clef.bass,
                        timeSignature: TimeSignature.fourFour,
                        notes: 'c3:h e3 | g3:h c4 | e3:h c3 | g2:h c3',
                      ),
                    ),
                    // A red flag on an upper note and a green one on a lower
                    // note; the loop band spans the second measure (e4..e7).
                    errorOverlay: const {
                      'e2': EditorMark(Color(0xFFD32F2F), message: 'blue note'),
                      'e5': EditorMark(Color(0xFF388E3C)),
                    },
                    loopRange: ('e4', 'e7'),
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
      matchesGoldenFile('goldens/111_grand_staff_overlay.png'),
    );
  });

  testWidgets('37 lyrics with hyphens and extender', (tester) async {
    await golden(
      tester,
      '37_lyrics',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
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
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
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
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
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
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
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
    int capo = 0,
    bool showTuning = false,
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
                  capo: capo,
                  showTuning: showTuning,
                  theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
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

  testWidgets('55 guitar tab: bends (½, full, 1½)', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 e5',
    );
    await tabGolden(
      tester,
      '55_tab_bends',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        bends: const [
          Bend('e0', steps: 0.5),
          Bend('e1'), // full
          Bend('e2', steps: 1.5),
        ],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('56 guitar tab: vibrato (normal + wide)', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q a4 c5 d5',
    );
    await tabGolden(
      tester,
      '56_tab_vibrato',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        vibratos: const [
          Vibrato('e0'), // normal
          Vibrato('e2', wide: true), // wide
        ],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('57 guitar tab: palm mute + let ring', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e2:e a2 e2 a2 | e3:q b3 g4 b3',
    );
    await tabGolden(
      tester,
      '57_tab_mute_ring',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        palmMutes: const [PalmMute('e0', 'e3')], // over the first measure
        letRings: const [LetRing('e4', 'e7')], // over the second
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('58 guitar tab: dead + ghost notes', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e2:q a2 d3 g3 | c3:q e3 g3 c4',
    );
    await tabGolden(
      tester,
      '58_tab_dead_ghost',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        tabNoteMarks: const [
          TabNoteMark('e1', TabNoteStyle.dead), // muted "x"
          TabNoteMark('e5', TabNoteStyle.dead),
          TabNoteMark('e3', TabNoteStyle.ghost), // "(n)"
          TabNoteMark('e7', TabNoteStyle.ghost),
        ],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('59 guitar tab: natural harmonics', (tester) async {
    // Octave (fret 12) and fifth (fret 7) natural harmonics.
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e5:q e4 b4 e5 | b4:q g4 d5 b4',
    );
    await tabGolden(
      tester,
      '59_tab_harmonics',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        tabNoteMarks: const [
          TabNoteMark('e0', TabNoteStyle.harmonic), // ⟨12⟩
          TabNoteMark('e3', TabNoteStyle.harmonic),
          TabNoteMark('e5', TabNoteStyle.harmonic),
        ],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('60 guitar tab: capo + tuning labels', (tester) async {
    await tabGolden(
      tester,
      '60_tab_capo_tuning',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'e2:q g2 c3 e3 | g4:q e4 c4 g3',
      ),
      Tuning.standardGuitar,
      capo: 2,
      showTuning: true,
    );
  });

  testWidgets('61 guitar tab: tapping + tremolo bar', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e5:q c5 g4 e4',
    );
    await tabGolden(
      tester,
      '61_tab_tap_whammy',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        taps: const [Tap('e0'), Tap('e1')], // tapped notes
        tremoloBars: const [
          TremoloBar('e2'), // whole-step dive
          TremoloBar('e3', steps: -1.5), // 1½-step dive
        ],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('62 lead sheet: chord diagrams above the staff', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q e4 g4 c5 | g4:q e4 c4 g3',
    );
    await golden(
      tester,
      '62_chord_diagrams',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        chordDiagrams: const [
          PlacedChordDiagram(
              'e0',
              ChordDiagram([0, 1, 0, 2, 3, -1],
                  name: 'C', fingers: [null, 1, null, 2, 3, null])),
          PlacedChordDiagram(
              'e4',
              ChordDiagram([3, 0, 0, 0, 2, 3],
                  name: 'G', fingers: [3, null, null, null, 2, 4])),
        ],
      ),
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      staffSpace: 12,
    );
  });

  testWidgets('75 four-staff system (SATB) with a bracket', (tester) async {
    final system = StaffSystem([
      Score.simple(
          clef: Clef.treble,
          notes: 'c5:q d5 e5 f5 | g5:h a5:h',
          keySignature: const KeySignature(1)),
      Score.simple(
          clef: Clef.treble,
          notes: 'g4:q g4 g4 a4 | b4:h c5:h',
          keySignature: const KeySignature(1)),
      Score.simple(
          clef: Clef.bass,
          notes: 'e3:q f3 g3 a3 | d3:h e3:h',
          keySignature: const KeySignature(1)),
      Score.simple(
          clef: Clef.bass,
          notes: 'c3:q b2 a2 g2 | g2:h c3:h',
          keySignature: const KeySignature(1)),
    ], brackets: const [
      StaffBracket(0, 3)
    ]);
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
                child: StaffSystemView(system: system, staffSpace: 12),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/75_staff_system_satb.png'),
    );
  });

  testWidgets('76 two-voice ABC tune as a staff system', (tester) async {
    final system = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\n'
        'V:1 clef=treble\n'
        'V:2 clef=bass\n'
        'K:G\n'
        'V:1\n'
        'G A B c | d2 e2 |\n'
        'V:2\n'
        'G,2 B,2 | C2 D2 |\n');
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
                child: StaffSystemView(
                  system: StaffSystem(system.staves,
                      brackets: const [StaffBracket(0, 1)]),
                  staffSpace: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/76_abc_two_voice_system.png'),
    );
  });

  testWidgets('77 MusicXML multi-part as a bracketed system', (tester) async {
    String part(String id, String step, int octave, String sign) => '''
<part id="$id"><measure number="1">
  <attributes><divisions>2</divisions><key><fifths>0</fifths></key>
    <time><beats>4</beats><beat-type>4</beat-type></time>
    <clef><sign>$sign</sign><line>${sign == 'F' ? 4 : 2}</line></clef>
  </attributes>
  <note><pitch><step>$step</step><octave>$octave</octave></pitch>
    <duration>4</duration><type>half</type></note>
  <note><pitch><step>$step</step><octave>$octave</octave></pitch>
    <duration>4</duration><type>half</type></note>
</measure></part>''';
    final system = staffSystemFromMusicXml('''
<score-partwise version="4.0">
  <part-list>
    <part-group type="start" number="1"><group-symbol>bracket</group-symbol></part-group>
    <score-part id="P1"/><score-part id="P2"/>
    <part-group type="stop" number="1"/>
  </part-list>
  ${part('P1', 'E', 5, 'G')}${part('P2', 'C', 3, 'F')}
</score-partwise>
''');
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
                child: StaffSystemView(system: system, staffSpace: 12),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/77_musicxml_multipart_system.png'),
    );
  });

  testWidgets('79 up-bow / down-bow marks', (tester) async {
    await golden(
      tester,
      '79_bowing',
      scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nvG uA vB uc|vd2 uc2|\n'),
      staffSpace: 12,
    );
  });

  testWidgets('84 C- and F-clef positions with a key signature',
      (tester) async {
    // Soprano, mezzo-soprano, baritone and sub-bass, each with three sharps.
    for (final (name, clef) in [
      ('84a_soprano', Clef.soprano),
      ('84b_mezzo', Clef.mezzoSoprano),
      ('84c_baritone', Clef.baritone),
      ('84d_subbass', Clef.subbass),
    ]) {
      await golden(
        tester,
        name,
        Score(
          clef: clef,
          keySignature: const KeySignature(3),
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              NoteElement.note(clef.pitchAt(0), NoteDuration.quarter, id: 'e0'),
              NoteElement.note(clef.pitchAt(2), NoteDuration.quarter, id: 'e1'),
              NoteElement.note(clef.pitchAt(4), NoteDuration.quarter, id: 'e2'),
              NoteElement.note(clef.pitchAt(8), NoteDuration.quarter, id: 'e3'),
            ]),
          ],
        ),
        staffSpace: 12,
      );
    }
  });

  testWidgets('83 percussion (neutral) clef', (tester) async {
    await golden(
      tester,
      '83_percussion_clef',
      Score(
        clef: Clef.percussion,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            NoteElement.note(
                const Pitch(Step.f, octave: 4), NoteDuration.quarter,
                id: 'e0'),
            NoteElement.note(
                const Pitch(Step.c, octave: 5), NoteDuration.quarter,
                id: 'e1'),
            NoteElement.note(
                const Pitch(Step.f, octave: 4), NoteDuration.quarter,
                id: 'e2'),
            NoteElement.note(
                const Pitch(Step.c, octave: 5), NoteDuration.quarter,
                id: 'e3'),
          ]),
          Measure([
            NoteElement.note(const Pitch(Step.f, octave: 4), NoteDuration.half,
                id: 'e4'),
            NoteElement.note(const Pitch(Step.c, octave: 5), NoteDuration.half,
                id: 'e5'),
          ]),
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('88 two voices with accidentals in one column', (tester) async {
    await golden(
      tester,
      '88_two_voice_accidentals',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'f#5:h d#5:h ; b4:h g#4:h',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('87 dense accidentals + articulations do not collide',
      (tester) async {
    await golden(
      tester,
      '87_dense_accidentals',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: "c#5:s' d#5' e5' f#5' g#5:s' a#5' b5' c#6' | "
            'f#4:e a#4 c#5 e5 g#5:e b5 d#6 f#6',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('86 skyline: chord symbols clear only local ink', (tester) async {
    // The chord symbols sit low over their own bar; the high ledger run in the
    // second bar (no symbols) does not lift them (per-column skyline).
    await golden(
      tester,
      '86_skyline_annotations',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q e4 g4 c5 | a5:q c6 a5 g5',
        annotations: 'C * * * * * * *',
      ),
      staffSpace: 11,
    );
  });

  testWidgets('85 additive time signature 3+2/8', (tester) async {
    await golden(
      tester,
      '85_additive_meter',
      Score.simple(
        timeSignature: TimeSignature.additive([3, 2], 8),
        notes: 'c5:e d5 e5 f5 g5 | a5:e g5 f5 e5 d5',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('82 common and cut time symbols', (tester) async {
    await golden(
      tester,
      '82_common_time',
      Score.simple(
        timeSignature: TimeSignature.commonTime,
        notes: 'c5:q d5 e5 f5 | g5:h a5:h',
      ),
      staffSpace: 12,
    );
    await golden(
      tester,
      '82_cut_time',
      Score.simple(
        timeSignature: TimeSignature.cutTime,
        notes: 'c5:h g5:h | c6:w',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('81 paginated page with justified systems', (tester) async {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: List.filled(16, 'c5:e d5 e5 f5 g5 a5 b5 c6').join(' | '),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: ScorePageView(
                  score: score,
                  metrics: const PageMetrics(width: 56, height: 68),
                  staffSpace: 7,
                  systemGap: 7,
                  drawPageBorder: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/81_paginated_page.png'),
    );
  });

  testWidgets('80 measure numbers with a pickup (anacrusis)', (tester) async {
    // A quarter-note upbeat, then full 4/4 bars: the pickup is unnumbered and
    // the first full bar reads 1.
    final score =
        scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:G\nD|G G G A|B B B2|A A A B|G4|\n');
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
                  staffSpace: 11,
                  showMeasureNumbers: true,
                  theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/80_measure_numbers_pickup.png'),
    );
  });

  testWidgets('78 nested brackets: an outer bracket over an inner brace',
      (tester) async {
    final system = StaffSystem([
      Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
      Score.simple(clef: Clef.treble, notes: 'e4:q f4 g4 a4'),
      Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
    ], brackets: const [
      // A section bracket over all three, with a piano brace on the lower two.
      StaffBracket(0, 2),
      StaffBracket(1, 2, kind: StaffBracketKind.brace),
    ]);
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
                child: StaffSystemView(system: system, staffSpace: 12),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/78_nested_brackets.png'),
    );
  });

  testWidgets('74 beat-count overlay (with note names)', (tester) async {
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
                  score: Score.simple(
                    timeSignature: TimeSignature.fourFour,
                    notes: 'c5:e d5 e5 f5 g5 a5 b5 c6 | c5:q e5 g5 c6',
                  ),
                  staffSpace: 12,
                  showNoteNames: true,
                  showBeatNumbers: true,
                  theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/74_beat_numbers.png'),
    );
  });

  testWidgets('73 note-name overlay for teaching views', (tester) async {
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
                  score: Score.simple(
                    timeSignature: TimeSignature.fourFour,
                    notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
                  ),
                  staffSpace: 12,
                  showNoteNames: true,
                  theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/73_note_names.png'),
    );
  });

  testWidgets('72 per-element note coloring', (tester) async {
    // App-supplied colors: a couple of notes red and green (e.g. out-of-range
    // or right/wrong feedback) while the rest stay the default ink.
    await golden(
      tester,
      '72_note_colors',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
      ),
      elementColors: const {
        'e2': Color(0xFFD32F2F), // red
        'e5': Color(0xFF388E3C), // green
        'e7': Color(0xFF1976D2), // blue
      },
      staffSpace: 12,
    );
  });

  testWidgets('71 breath marks and caesura', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 | g5:h a5:h',
    );
    await golden(
      tester,
      '71_breath_marks',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        breathMarks: const [
          BreathMark('e1', BreathSymbol.comma), // after d5
          BreathMark('e3', BreathSymbol.comma), // after f5
          BreathMark('e4', BreathSymbol.caesura), // grand pause after g5
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('70 figured bass under a continuo line', (tester) async {
    final base = Score.simple(
      clef: Clef.bass,
      timeSignature: TimeSignature.fourFour,
      notes: 'c3:q g2 a2 e2 | f2:q g2 c3:h',
    );
    await golden(
      tester,
      '70_figured_bass',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        figuredBass: const [
          FiguredBass('e1', ['6']),
          FiguredBass('e2', ['6', '5']),
          FiguredBass('e3', ['7']),
          FiguredBass('e4', ['#6', '4']),
          FiguredBass('e5', ['5', '3']),
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('99 figured bass: slashed figures + continuation lines',
      (tester) async {
    final base = Score.simple(
      clef: Clef.bass,
      timeSignature: TimeSignature.fourFour,
      notes: 'c3:q g2 a2 e2 | f2:q g2 c3:h',
    );
    await golden(
      tester,
      '99_figured_bass_slash_extend',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        figuredBass: const [
          FiguredBass('e0', [r'6\']), // slashed six (raised sixth)
          FiguredBass('e1', ['_']), // held over the moving bass
          FiguredBass('e2', [r'4\', '2']), // slashed four over a plain two
          FiguredBass('e3', ['_']), // continuation line
          FiguredBass('e4', ['7', r'5\']), // slashed five in a stack
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('100 laissez-vibrer ties (let ring)', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q g4 e5 c4',
    );
    await golden(
      tester,
      '100_laissez_vibrer',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        laissezVibrer: const [
          LaissezVibrer('e0'), // auto (opposite the stem)
          LaissezVibrer('e1'), // auto
          LaissezVibrer('e2', down: true), // forced underside
          LaissezVibrer('e3', down: false), // forced topside
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('101 lyric elision (two syllables on one note)', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q a4 b4 c5',
    );
    await golden(
      tester,
      '101_lyric_elision',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        lyrics: const [
          // "de_o" elided onto one note, then two plain syllables.
          Lyric('e0', 'de', elidesToNext: true),
          Lyric('e0', 'o'),
          Lyric('e1', 'in'),
          Lyric('e2', 'ex', hyphenToNext: true),
          Lyric('e3', 'cel'),
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('69 jazz articulations: scoop, doit, fall, plop', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 g5',
    );
    await golden(
      tester,
      '69_jazz_articulations',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        jazzMarks: const [
          JazzMark('e0', JazzArticulation.scoop), // before, rises in
          JazzMark('e1', JazzArticulation.doit), // after, flicks up
          JazzMark('e2', JazzArticulation.fall), // after, drops
          JazzMark('e3', JazzArticulation.plop), // before, drops in
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('98 jazz articulations: lift, flip, smear, bend', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q b4 d5 g5',
    );
    await golden(
      tester,
      '98_jazz_lift_flip_smear_bend',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        jazzMarks: const [
          JazzMark('e0', JazzArticulation.lift), // after, rises off
          JazzMark('e1', JazzArticulation.flip), // after, flips over
          JazzMark('e2', JazzArticulation.smear), // before, smears in
          JazzMark('e3', JazzArticulation.bend), // after, bends
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('68 multi-verse lyrics stack below the staff', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q b4 a4 g4 | a4:q b4 c5:q r:q',
    );
    // Two verses on the same seven notes (e0…e6, the rest carries none), each
    // its own row.
    const words1 = ['Joy', 'to', 'the', 'world', 'the', 'Lord', 'comes'];
    const words2 = ['Let', 'earth', 're-', 'ceive', 'her', 'King', 'now'];
    List<Lyric> verse(List<String> words, int v) => [
          for (var i = 0; i < words.length; i++)
            Lyric('e$i', words[i].replaceAll('-', ''),
                hyphenToNext: words[i].endsWith('-'), verse: v),
        ];
    await golden(
      tester,
      '68_multi_verse_lyrics',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        lyrics: [...verse(words1, 1), ...verse(words2, 2)],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('67 text never overlaps: wide chords + lyrics on close notes',
      (tester) async {
    // Wide chord symbols and multi-letter syllables over fast notes would
    // collide if centered blindly; the layout must space them apart.
    await golden(
      tester,
      '67_text_no_overlap',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:e e4 g4 c5 g4 e4 c4 e4 | c4:e e4 g4 c5 g4 e4 c4 e4',
        annotations: 'Cmaj7 Am7 Dm7 G7 Cmaj7 Fmaj7 Bm7b5 E7 Cmaj7',
        lyrics: 'Su- per- ca- li- fra- gi- lis- tic ex',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('66 notehead shapes', (tester) async {
    NoteElement head(NoteheadShape shape, NoteDuration dur, String id) =>
        NoteElement.note(const Pitch(Step.b, octave: 4), dur,
            notehead: shape, id: id);
    // Row 1: quarter notes — x, diamond, triangle, slash, circled-x, normal.
    // Row 2: the open (half/whole) variants of x and diamond.
    await golden(
      tester,
      '66_notehead_shapes',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            head(NoteheadShape.x, NoteDuration.quarter, 'e0'),
            head(NoteheadShape.diamond, NoteDuration.quarter, 'e1'),
            head(NoteheadShape.triangleUp, NoteDuration.quarter, 'e2'),
            head(NoteheadShape.slash, NoteDuration.quarter, 'e3'),
          ]),
          Measure([
            head(NoteheadShape.circleX, NoteDuration.quarter, 'e4'),
            head(NoteheadShape.normal, NoteDuration.quarter, 'e5'),
            head(NoteheadShape.x, NoteDuration.half, 'e6'),
          ]),
          Measure([
            head(NoteheadShape.diamond, NoteDuration.half, 'e7'),
            head(NoteheadShape.diamond, NoteDuration.whole, 'e8'),
          ]),
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('65 barline styles', (tester) async {
    // double, dashed, dotted, heavy, then a final barline to close.
    await golden(
      tester,
      '65_barline_styles',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:w !barline=doubleBar | d5:w !barline=dashed |'
            ' e5:w !barline=dotted | f5:w !barline=heavy |'
            ' g5:w !barline=finalBar',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('102 tick, short and reverse-final barlines', (tester) async {
    // A tick (top-line stroke), a short (mid-staff stroke), then a
    // reverse-final (thick+thin) closing the piece.
    await golden(
      tester,
      '102_tick_short_reverse_barlines',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:w !barline=tick | d5:w !barline=short |'
            ' e5:w !barline=reverseFinal',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('105 Sacred Harp four-shape noteheads', (tester) async {
    // A C-major scale + a triad: fa sol la fa sol la mi fa, then a fa-la-do
    // chord, in four-shape (Sacred Harp) noteheads.
    await golden(
      tester,
      '105_shape_notes',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
      ),
      noteheadScheme: NoteheadScheme.sacredHarp,
      staffSpace: 12,
    );
  });

  testWidgets('108 extended trill (tr + wavy line)', (tester) async {
    // A trill whose wavy line runs across three notes to the final one.
    await golden(
      tester,
      '108_trill_extension',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: Score.simple(notes: 'c5:q d5 e5 f5').measures,
        trillExtensions: const [TrillExtension('e0', 'e2')],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('115 interchangeable meter (3/4 + 2/4)', (tester) async {
    // Both signatures shown at the start; the second bar switches to 2/4.
    await golden(
      tester,
      '115_interchangeable_meter',
      Score.simple(
        timeSignature:
            const TimeSignature(3, 4, alternate: TimeSignature(2, 4)),
        notes: 'c5:q d5 e5 | !time=2/4 f5:q g5',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('114 baroque ornaments (inverted turn, trilled accidentals)',
      (tester) async {
    NoteElement orn(int step, Ornament o, String id) => NoteElement(
          pitches: [Pitch(Step.values[step], octave: 5)],
          duration: NoteDuration.quarter,
          ornament: o,
          id: id,
        );
    await golden(
      tester,
      '114_baroque_ornaments',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            orn(0, Ornament.invertedTurn, 'e0'),
            orn(1, Ornament.trillSharp, 'e1'),
            orn(2, Ornament.trillFlat, 'e2'),
            orn(3, Ornament.trillNatural, 'e3'),
          ]),
        ],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('113 portamento (curved slide)', (tester) async {
    await golden(
      tester,
      '113_portamento',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: Score.simple(notes: 'c5:h g5:h').measures,
        portamentos: const [Portamento('e0', 'e1')],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('112 cue (small) notes', (tester) async {
    // Full-size notes framing two small cue notes (head, stem and flag scaled).
    await golden(
      tester,
      '112_cue_notes',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: Score.simple(notes: 'c5:q d5:q e5:q f5:q').measures,
        cueNoteIds: const ['e1', 'e2'],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('109 pitch-name noteheads', (tester) async {
    await golden(
      tester,
      '109_pitch_name_notes',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
      ),
      noteheadScheme: NoteheadScheme.pitchName,
      staffSpace: 14,
    );
  });

  testWidgets('110 solfège noteheads', (tester) async {
    await golden(
      tester,
      '110_solfege_notes',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
      ),
      noteheadScheme: NoteheadScheme.solfege,
      staffSpace: 14,
    );
  });

  testWidgets('106 Aikin seven-shape noteheads', (tester) async {
    // do re mi fa sol la ti do — a distinct shape per scale degree.
    await golden(
      tester,
      '106_aikin_shape_notes',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
      ),
      noteheadScheme: NoteheadScheme.aikin,
      staffSpace: 12,
    );
  });

  testWidgets('104 compound 6/8 beams in threes', (tester) async {
    await golden(
      tester,
      '104_compound_beaming',
      Score.simple(
        timeSignature: TimeSignature.sixEight,
        notes: 'c5:e d5 e5 f5 g5 a5 | g5:e f5 e5 d5 e5 c5',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('103 palm mute, let ring & vibrato on the notation staff',
      (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g5:q g5 g5 g5 | c6:h b5:h',
    );
    await golden(
      tester,
      '103_notation_pm_letring_vibrato',
      theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        palmMutes: const [PalmMute('e0', 'e3')],
        letRings: const [LetRing('e4', 'e5')],
        vibratos: const [Vibrato('e5', wide: true)],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('64 beams over rests', (tester) async {
    // Rests inside a beat do not break the beam (it spans the gap); a rest at
    // a beat boundary still separates. Beat 1: 16th, 16th-rest, two 16ths.
    // Beat 2: 8th, 8th. Beat 3: two 8ths split by an 8th-rest (each flags).
    await golden(
      tester,
      '64_beams_over_rests',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:s r:s a4:s b4:s c5:e c5 g4:e r:e a4:e r:e',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('89 beam subdivision in cut time', (tester) async {
    // The half-note beat groups all eight sixteenths under one continuous
    // primary beam, but the secondary beam breaks at the quarter-note metric
    // point (two secondary segments, showing the sub-pulse).
    await golden(
      tester,
      '89_beam_subdivision_cut_time',
      Score.simple(
        timeSignature: TimeSignature.cutTime,
        notes: 'c5:s d5 e5 f5 g5 a5 b5 c6 r:h',
      ),
      staffSpace: 12,
    );
  });

  testWidgets('93 cross-measure beam', (tester) async {
    // An eighth ends bar 1 and an eighth opens bar 2, beamed together across
    // the barline via CrossMeasureBeam (instead of each note flagging).
    NoteElement n(String step, int oct, DurationBase base, String id,
            {int dots = 0}) =>
        NoteElement(
          pitches: [Pitch(Step.values.byName(step), octave: oct)],
          duration: NoteDuration(base, dots: dots),
          id: id,
        );
    await golden(
      tester,
      '93_cross_measure_beam',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            n('g', 4, DurationBase.half, 'a'),
            n('a', 4, DurationBase.quarter, 'b', dots: 1),
            n('b', 4, DurationBase.eighth, 'x'),
          ]),
          Measure([
            n('c', 5, DurationBase.eighth, 'y'),
            n('b', 4, DurationBase.quarter, 'c', dots: 1),
            n('a', 4, DurationBase.half, 'd'),
          ]),
        ],
        crossMeasureBeams: const [CrossMeasureBeam('x', 'y')],
      ),
      staffSpace: 12,
    );
  });

  testWidgets('63 guitar tab: artificial + pinch harmonics', (tester) async {
    // Natural (⟨12⟩), artificial ("A.H.") and pinch ("P.H.") harmonics — all
    // show the bracketed fret; the two synthetic ones add a label above.
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e5:q e4 b4 e5 | b4:q g4 d5 b4',
    );
    await tabGolden(
      tester,
      '63_tab_harmonic_types',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        tabNoteMarks: const [
          TabNoteMark('e0', TabNoteStyle.harmonic),
          TabNoteMark('e2', TabNoteStyle.artificialHarmonic),
          TabNoteMark('e4', TabNoteStyle.pinchHarmonic),
          TabNoteMark('e6', TabNoteStyle.artificialHarmonic),
        ],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('96 tab: fingering, slap/pop, tremolo picking', (tester) async {
    final base = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q a4 b4 c5',
    );
    await tabGolden(
      tester,
      '96_tab_fingering_slap_tremolo',
      Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        tabFingerings: const [TabFingering('e0', RightHandFinger.thumb)],
        slapPops: const [SlapPop('e1'), SlapPop('e2', pop: true)],
        tremoloPickings: const [TremoloPicking('e3')],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('97 tab: ornaments, articulations, rasgueado', (tester) async {
    NoteElement n(String pitch, String id,
            {Ornament? ornament, Set<Articulation> articulations = const {}}) =>
        NoteElement(
          pitches: [Pitch.parse(pitch)],
          duration: const NoteDuration(DurationBase.quarter),
          id: id,
          ornament: ornament,
          articulations: articulations,
        );
    await tabGolden(
      tester,
      '97_tab_ornaments_articulations_rasgueado',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            n('g4', 'e0', ornament: Ornament.trill),
            n('a4', 'e1', articulations: const {Articulation.staccato}),
            n('b4', 'e2', articulations: const {Articulation.accent}),
            n('c5', 'e3'),
          ]),
        ],
        rasgueados: const [Rasgueado('e3')],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('107 tab: grace notes (acciaccatura + appoggiatura)',
      (tester) async {
    NoteElement n(String pitch, String id,
            {List<String> grace = const [],
            GraceStyle style = GraceStyle.acciaccatura}) =>
        NoteElement.note(
          Pitch.parse(pitch),
          const NoteDuration(DurationBase.quarter),
          id: id,
          graceNotes: [for (final g in grace) Pitch.parse(g)],
          graceStyle: style,
        );
    await tabGolden(
      tester,
      '107_tab_grace_notes',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            // Lead with a plain note so the graced notes have room; each grace
            // sits on the same string just below its principal.
            n('e4', 'e0'), // plain, for contrast
            n('d4', 'e1', grace: ['c4']), // acciaccatura, B string (1→3)
            n('g4', 'e2', grace: ['f4']), // acciaccatura, high E (1→3)
            n('b4', 'e3',
                grace: ['a4'], style: GraceStyle.appoggiatura), // no slash
          ]),
        ],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets(
      '115 tab: bend curves, whammy, slide in/out, pick-stroke, arpeggio',
      (tester) async {
    NoteElement n(String pitch, String id) => NoteElement.note(
          Pitch.parse(pitch),
          const NoteDuration(DurationBase.quarter),
          id: id,
        );
    await tabGolden(
      tester,
      '115_tab_technique_tail',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            n('g4', 'e0'), // bend-release contour
            n('a4', 'e1'), // whammy dive-and-return
            n('b4', 'e2'), // slide out (upward) + pick-stroke
            NoteElement(
              pitches: const [
                Pitch(Step.c, octave: 4),
                Pitch(Step.e, octave: 4),
                Pitch(Step.g, octave: 4),
              ],
              duration: const NoteDuration(DurationBase.quarter),
              id: 'e3',
              arpeggio: Arpeggio.up, // rolled chord
            ),
          ]),
        ],
        bends: const [
          Bend.curve('e0', [BendPoint(0.5, 1.0), BendPoint(1.0, 0.0)]),
        ],
        tremoloBars: const [
          TremoloBar.curve('e1', [BendPoint(0.5, -1.0), BendPoint(1.0, 0.0)]),
        ],
        slideInOuts: const [TabSlide('e2', SlideInOut.outUpward)],
        pickStrokes: const [PickStroke('e2', up: true)],
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('117 tab: Tier-3 tail (harmonics, rasgueado, golpe, wah, fade)',
      (tester) async {
    NoteElement n(String pitch, String id) => NoteElement.note(
          Pitch.parse(pitch),
          const NoteDuration(DurationBase.quarter),
          id: id,
        );
    await tabGolden(
      tester,
      '117_tab_tier3_tail',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            n('g4', 'e0'), // tapped harmonic
            n('a4', 'e1'), // rasgueado with a finger pattern
            n('b4', 'e2'), // golpe + wah (open)
            n('c5', 'e3'), // fade-in target
          ]),
        ],
        tabNoteMarks: const [TabNoteMark('e0', TabNoteStyle.tappedHarmonic)],
        rasgueados: const [Rasgueado('e1', pattern: 'p a m i')],
        golpes: const [Golpe('e2')],
        wahs: const [Wah('e2', open: true)],
        fades: const [Fade('e1', 'e3')], // fade-in swell across the bar
      ),
      Tuning.standardGuitar,
    );
  });

  testWidgets('118 notation staff paired with tab (Phase 6.3)', (tester) async {
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
                child: NotationTabView(
                  score: Score.simple(
                    timeSignature: TimeSignature.fourFour,
                    notes: 'e3:q g3 c4 e4 | d4:q b3 g3 d3 | c4:h e4:h',
                  ),
                  tuning: Tuning.standardGuitar,
                  staffSpace: 12,
                  theme: const CrispNotationTheme(textFontFamily: 'Roboto'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/118_notation_tab_pair.png'),
    );
  });

  testWidgets('119 piano-keyboard visualizer (L/R hands lit)', (tester) async {
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
                child: const PianoKeyboardView(
                  firstMidi: 48, // C3
                  lastMidi: 84, // C6
                  whiteKeyWidth: 14,
                  height: 72,
                  // Left hand (blue) plays a C-major triad low; right hand
                  // (orange) plays a C-major triad an octave-plus up.
                  highlightedPitches: {48, 52, 55, 72, 76, 79},
                  pitchColors: {
                    48: Color(0xFF1E88E5),
                    52: Color(0xFF1E88E5),
                    55: Color(0xFF1E88E5),
                    72: Color(0xFFF4511E),
                    76: Color(0xFFF4511E),
                    79: Color(0xFFF4511E),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/119_piano_keyboard.png'),
    );
  });

  testWidgets('120 fretboard visualizer (open E-major chord)', (tester) async {
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
                child: const FretboardView(
                  frets: 12,
                  // An open E-major chord — its pitches light every fretboard
                  // position that sounds them (open strings ringed).
                  highlightedPitches: {40, 47, 52, 56, 59, 64},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/120_fretboard.png'),
    );
  });

  testWidgets('121 hide empty staves (Phase 2.3)', (tester) async {
    // A 3-staff system whose middle staff rests the whole system.
    final system = StaffSystem([
      Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5 | g5:h a5:h'),
      Score.simple(clef: Clef.treble, notes: 'r:w | r:w'),
      Score.simple(clef: Clef.bass, notes: 'c3:q b2 a2 g2 | g2:h c3:h'),
    ], brackets: const [
      StaffBracket(0, 2)
    ]);
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
                child: StaffSystemView(
                  system: system,
                  staffSpace: 12,
                  hideEmptyStaves: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/121_hide_empty_staves.png'),
    );
  });

  testWidgets('122 metric secondary-beam breaks in 6/8 (Phase 4.7)',
      (tester) async {
    // Twelve sixteenths in 6/8: primary 8th-beams group them by the two
    // dotted-quarter beats, and the secondary 16th-beams break at each eighth
    // pulse (three pairs per beat) — not at a quarter as a simple meter would.
    await golden(
      tester,
      '122_compound_beam_breaks',
      Score.simple(
        timeSignature: const TimeSignature(6, 8),
        notes: 'c5:s d5 e5 f5 g5 a5 g5 f5 e5 d5 c5 b4',
      ),
    );
  });

  testWidgets('126 measure-repeat signs (1 / 2-bar)', (tester) async {
    NoteElement n(String p) =>
        NoteElement.note(Pitch.parse(p), const NoteDuration(DurationBase.half));
    await golden(
      tester,
      '126_measure_repeat',
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([n('c5'), n('e5')]),
          Measure(const [], measureRepeat: 1), // repeat previous bar
          Measure([n('d5'), n('f5')]),
          Measure(const [], measureRepeat: 2), // repeat previous two bars
        ],
      ),
    );
  });
}
