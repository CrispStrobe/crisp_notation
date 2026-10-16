import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

import 'support/layout_lint.dart';

/// Defects found by rendering real scores beside two reference engravers
/// (LilyPond 2.24 and Verovio 6.3) and reading the differences, one group
/// per finding. Hidden rests (`<forward>`) and staff alignment are in
/// `hidden_rest_test.dart`.
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));
  ScoreLayout layoutOf(Score s) => const LayoutEngine().layout(s, settings);

  String bar(String directions) => '''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>P</part-name></score-part></part-list><part id="P1">
<measure number="1"><attributes><divisions>1</divisions>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>$directions
<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

  bool drawsMetronome(ScoreLayout l) => l.primitives
      .whereType<GlyphPrimitive>()
      .any((g) => g.smuflName.startsWith('metNote'));

  group('a playback-only tempo prints no metronome mark', () {
    // Debussy, "L'ombre des arbres": the score says "Lent et triste" and
    // carries <sound tempo="45.5"/> for playback; "♩ = 45.5" was printed.
    const soundOnly = '<direction><direction-type><words>Lent et triste'
        '</words></direction-type><sound tempo="45.5"/></direction>';
    const printed = '<direction><direction-type><metronome>'
        '<beat-unit>quarter</beat-unit><per-minute>60</per-minute>'
        '</metronome></direction-type><sound tempo="60"/></direction>';

    test('read: a <sound tempo> alone is unprinted, a <metronome> printed', () {
      final quiet = scoreFromMusicXml(bar(soundOnly));
      expect(quiet.tempo?.bpm, 45.5);
      expect(quiet.tempo?.printed, isFalse);
      expect(scoreFromMusicXml(bar(printed)).tempo?.printed, isTrue);
    });

    test('drawn only when printed; playback keeps both', () {
      expect(
          drawsMetronome(layoutOf(scoreFromMusicXml(bar(soundOnly)))), isFalse);
      expect(drawsMetronome(layoutOf(scoreFromMusicXml(bar(printed)))), isTrue);
    });

    test('an unprinted tempo round-trips unprinted', () {
      final back =
          scoreFromMusicXml(scoreToMusicXml(scoreFromMusicXml(bar(soundOnly))));
      expect(back.tempo, const Tempo(45.5, printed: false));
    });
  });

  group('a whole-bar rest is a centred whole rest, in every meter', () {
    // Fauré, "Après un rêve": the piano's silent 3/4 bars drew a dotted half
    // rest at the bar's start.
    for (final (meter, notes) in [
      (const TimeSignature(3, 4), 'r:h. | c5:h.'),
      (const TimeSignature(6, 8), 'r:h. | c5:h.'),
      (TimeSignature.fourFour, 'r:w | c5:w'),
    ]) {
      test('$meter', () {
        final l = layoutOf(Score.simple(timeSignature: meter, notes: notes));
        final rests = l.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName.startsWith('rest'))
            .toList();
        expect(rests.map((g) => g.smuflName), [SmuflGlyph.restWhole]);
        final bar = l.measureRegions.first;
        final width = settings.metadata.bBoxOf(SmuflGlyph.restWhole).width;
        expect(rests.single.position.x + width / 2,
            closeTo((bar.startX + bar.endX) / 2, 1e-9));
        // No dot is left behind from the dotted half.
        expect(
            l.primitives.whereType<GlyphPrimitive>().where((g) =>
                g.smuflName == SmuflGlyph.augmentationDot &&
                g.elementId == rests.single.elementId),
            isEmpty);
      });
    }

    test('in whichever voice it is read into', () {
      // A piano's left hand: voice 1 empty, the bar's rest in voice 2.
      final l = layoutOf(Score(
        clef: Clef.bass,
        timeSignature: const TimeSignature(3, 4),
        measures: [
          Measure(const [], voice2: const [
            RestElement(NoteDuration(DurationBase.half, dots: 1), id: 'r'),
          ]),
        ],
      ));
      expect(
          l.primitives
              .whereType<GlyphPrimitive>()
              .where((g) => g.smuflName.startsWith('rest'))
              .map((g) => g.smuflName),
          [SmuflGlyph.restWhole]);
    });

    test('a rest that is not the whole bar is left as it is', () {
      final l = layoutOf(Score.simple(
          timeSignature: const TimeSignature(3, 4), notes: 'r:h c5:q'));
      expect(
          l.primitives
              .whereType<GlyphPrimitive>()
              .where((g) => g.smuflName.startsWith('rest'))
              .map((g) => g.smuflName),
          [SmuflGlyph.restHalf]);
    });
  });

  test('a pickup is beamed from where it falls in the meter', () {
    // PLAN.md known bug 1: six sixteenths of a 3/8 pickup in 4/4 start at
    // 5/8 — two before the beat, then four — not four and two.
    final sixteenths = [
      for (final (i, step)
          in [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a].indexed)
        NoteElement(
            pitches: [Pitch(step, octave: 5)],
            duration: const NoteDuration(DurationBase.sixteenth),
            id: 'p$i'),
    ];
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure(sixteenths, pickup: true, actualDuration: Fraction(3, 8)),
        Measure(const [
          NoteElement(
              pitches: [Pitch(Step.c, octave: 5)],
              duration: NoteDuration.whole,
              id: 'w'),
        ]),
      ],
    );
    final l = layoutOf(score);
    final heads = {
      for (final g in l.primitives.whereType<GlyphPrimitive>())
        if (g.elementId case final id? when id.startsWith('p'))
          id: g.position.x,
    };
    // The notes under a beam: heads whose stem (on the head's right for
    // stems up, its left for stems down) the beam reaches.
    final headWidth = settings.metadata.bBoxOf(SmuflGlyph.noteheadBlack).width;
    int notesUnder(BeamPrimitive b) => heads.values
        .where((x) => x + headWidth >= b.start.x - 0.1 && x <= b.end.x + 0.1)
        .length;
    final beams = l.primitives.whereType<BeamPrimitive>().toList()
      ..sort((a, b) => a.start.x.compareTo(b.start.x));
    // The longest beam of each group is its primary: two groups, of 2 then 4.
    final spans = <(double, double)>{
      for (final b in beams) (b.start.x, b.end.x),
    };
    final primaries = [
      for (final (x0, x1) in spans)
        if (!spans.any((o) => o != (x0, x1) && o.$1 <= x0 && o.$2 >= x1))
          beams.firstWhere((b) => b.start.x == x0 && b.end.x == x1),
    ];
    expect(primaries.map(notesUnder), [2, 4],
        reason: 'two before the beat, then four');
  });

  test('a pickup that states no length is placed by what it holds', () {
    // What every reader produces: the pickup flag, no `actualDuration`.
    final sixteenths = [
      for (final (i, step)
          in [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a].indexed)
        NoteElement(
            pitches: [Pitch(step, octave: 5)],
            duration: const NoteDuration(DurationBase.sixteenth),
            id: 'p$i'),
    ];
    final withLength = layoutOf(Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure(sixteenths, pickup: true, actualDuration: Fraction(3, 8)),
      ],
    ));
    final withoutLength = layoutOf(Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [Measure(sixteenths, pickup: true)],
    ));
    List<(double, double)> beams(ScoreLayout l) => [
          for (final b in l.primitives.whereType<BeamPrimitive>())
            (b.start.x, b.end.x),
        ];
    expect(beams(withoutLength), beams(withLength));
  });

  // A voice above a two-staff piano, as both reference engravers draw it:
  // the piano's barlines join its staves, the voice's stand apart, a brace
  // holds the piano and one line opens the system.
  String songXml(String pianoBar) => '''
<score-partwise version="3.1"><part-list>
<score-part id="P1"><part-name>Voice</part-name></score-part>
<score-part id="P2"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1"><attributes><divisions>2</divisions>
<time><beats>3</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>G</step><octave>4</octave></pitch><duration>6</duration>
<voice>1</voice><type>half</type><dot/></note></measure></part>
<part id="P2"><measure number="1"><attributes><divisions>2</divisions>
<time><beats>3</beats><beat-type>4</beat-type></time><staves>2</staves>
<clef number="1"><sign>G</sign><line>2</line></clef>
<clef number="2"><sign>F</sign><line>4</line></clef></attributes>
$pianoBar</measure></part></score-partwise>''';

  test('a chord across the piano staves loses neither half', () {
    // Fauré, "Après un rêve", bar 3: each eighth chord has A3 and C4 on the
    // bass staff and E-flat 4 and G4 on the treble — the treble half was
    // merged into one note.
    String chord() => '''
<note><pitch><step>A</step><octave>3</octave></pitch><duration>1</duration>
<voice>1</voice><type>eighth</type><staff>2</staff></note>
<note><chord/><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration>
<voice>1</voice><type>eighth</type><staff>2</staff></note>
<note><chord/><pitch><step>E</step><alter>-1</alter><octave>4</octave></pitch>
<duration>1</duration><voice>1</voice><type>eighth</type><staff>1</staff></note>
<note><chord/><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration>
<voice>1</voice><type>eighth</type><staff>1</staff></note>''';
    final sys =
        staffSystemFromMusicXml(songXml(List.filled(6, chord()).join()));
    final treble = sys.staves[1].measures.single.elements;
    final bass = sys.staves[2].measures.single.elements;
    expect(treble, hasLength(6));
    expect(bass, hasLength(6));
    for (final e in treble.cast<NoteElement>()) {
      expect(e.pitches, const [
        Pitch(Step.e, alter: -1, octave: 4),
        Pitch(Step.g, octave: 4),
      ]);
    }
    for (final e in bass.cast<NoteElement>()) {
      expect(e.pitches,
          const [Pitch(Step.a, octave: 3), Pitch(Step.c, octave: 4)]);
    }
  });

  test('the piano\'s barlines join its staves; the voice\'s stand apart', () {
    final sys = staffSystemFromMusicXml(songXml('''
<note><pitch><step>C</step><octave>5</octave></pitch><duration>6</duration>
<voice>1</voice><type>half</type><dot/><staff>1</staff></note>
<backup><duration>6</duration></backup>
<note><pitch><step>C</step><octave>3</octave></pitch><duration>6</duration>
<voice>5</voice><type>half</type><dot/><staff>2</staff></note>'''));
    // The piano's staves form a group; the voice, outside it, stands alone.
    expect(sys.barlineGroups, const [BarlineGroup(1, 2)]);
    expect(sys.brackets.single.kind, StaffBracketKind.brace);

    final svg = staffSystemToSvg(layoutStaffSystem(sys, settings));
    // The brace glyph is drawn, left of the staves.
    expect(svg, contains(smuflCodepoints['brace']));
  });

  test('a grand staff in SVG has its brace and joined barlines', () {
    final g = layoutGrandStaff(
        GrandStaff(
            upper: Score.simple(notes: 'c5:w | d5:w'),
            lower: Score.simple(clef: Clef.bass, notes: 'c3:w | d3:w')),
        settings);
    final svg = grandStaffToSvg(g);
    expect(svg, contains(smuflCodepoints['brace']));
    // A connector between the staves at each barline: from the upper staff's
    // bottom line (y = 4) down to the lower staff's top.
    expect(RegExp(r'<line x1="[\d.]+" y1="4" ').allMatches(svg).length,
        greaterThanOrEqualTo(3));
  });

  test('a voice inside the other voice\'s chord moves off its stem', () {
    // Debussy, bar 1 of the piano: voice 2's E inside voice 1's A-A chord
    // was drawn through the chord's stem.
    for (final notes in ['a3+a4:q b3+b4 e4 ; e4:h.', 'c4+c5:h ; g4:h']) {
      final l = layoutOf(
          Score.simple(timeSignature: const TimeSignature(3, 4), notes: notes));
      expect(lintLayout(l, settings).where((i) => i.rule == 'voice-collision'),
          isEmpty,
          reason: notes);
    }
  });

  group('the title block', () {
    // The Debussy: a song (movement) within a cycle (work), poet and
    // transcriber named — LilyPond and Verovio print all of it.
    const head = '''
<score-partwise version="3.1">
<work><work-title>Ariettes oubliées</work-title></work>
<movement-title>L'Ombre des Arbres</movement-title>
<identification><creator type="composer">Claude Debussy</creator>
<creator type="lyricist">Paul Verlaine</creator>
<creator type="arranger">Transcribed from IMSLP</creator>
<rights>OpenScore (CC0)</rights></identification>
<part-list><score-part id="P1"><part-name>Voice</part-name></score-part>
</part-list><part id="P1"><measure number="1"><attributes>
<divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

    test('reads the cycle as title, the song as subtitle', () {
      final m = scoreFromMusicXml(head).metadata;
      expect(m.title, 'Ariettes oubliées');
      expect(m.subtitle, "L'Ombre des Arbres");
      expect(m.lyricist, 'Paul Verlaine');
      expect(m.arranger, 'Transcribed from IMSLP');
      expect(m.copyright, 'OpenScore (CC0)');
    });

    test('round-trips through MusicXML', () {
      final m = scoreFromMusicXml(head).metadata;
      expect(
          scoreFromMusicXml(scoreToMusicXml(scoreFromMusicXml(head))).metadata,
          m);
    });

    test('SVG prints every line, and the copyright at the foot', () {
      final svg = staffSystemSystemsToSvg(
          layoutStaffSystemSystems(staffSystemFromMusicXml(head), settings,
              maxWidth: 60),
          showTitle: true);
      for (final text in [
        'Ariettes oubliées',
        'L&apos;Ombre des Arbres',
        'Paul Verlaine',
        'Claude Debussy',
        'Transcribed from IMSLP',
        'OpenScore (CC0)',
      ]) {
        expect(
            svg.contains(text) || svg.contains(text.replaceAll('&apos;', "'")),
            isTrue,
            reason: text);
      }
    });
  });

  group('text keeps the style the score gives it', () {
    // Fauré: <words font-style="italic">dolce</words>, <words
    // font-weight="bold">Andantino</words>; both were drawn plain.
    const bar = '''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>P</part-name></score-part></part-list><part id="P1">
<measure number="1"><attributes><divisions>1</divisions>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<direction placement="below"><direction-type><words font-style="italic">dolce</words></direction-type></direction>
<direction placement="above"><direction-type><words font-weight="bold">Allegro</words></direction-type></direction>
<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration>
<type>whole</type></note></measure></part></score-partwise>''';

    test('read, laid out and exported', () {
      final score = scoreFromMusicXml(bar);
      final dolce = score.annotations.firstWhere((a) => a.text == 'dolce');
      final allegro = score.annotations.firstWhere((a) => a.text == 'Allegro');
      expect((dolce.italic, dolce.bold), (true, false));
      expect((allegro.italic, allegro.bold), (false, true));
      final texts = layoutOf(score).primitives.whereType<TextPrimitive>();
      expect(texts.firstWhere((t) => t.text == 'dolce').italic, isTrue);
      expect(texts.firstWhere((t) => t.text == 'Allegro').bold, isTrue);
      final svg = scoreToSvg(layoutOf(score));
      expect(svg, contains('font-style="italic"'));
      expect(svg, contains('font-weight="bold"'));
    });

    test('round-trips through MusicXML', () {
      final score = scoreFromMusicXml(bar);
      expect(scoreFromMusicXml(scoreToMusicXml(score)).annotations,
          score.annotations);
    });
  });

  group('a stem direction the source states is kept', () {
    // A note on the middle line goes either way; the source's choice wins.
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          const NoteElement(
              pitches: [Pitch(Step.b, octave: 4)],
              duration: NoteDuration.quarter,
              stemsDown: false,
              id: 'up'),
          const NoteElement(
              pitches: [Pitch(Step.b, octave: 4)],
              duration: NoteDuration.quarter,
              stemsDown: true,
              id: 'down'),
          const NoteElement(
              pitches: [Pitch(Step.b, octave: 4)],
              duration: NoteDuration.half,
              id: 'auto'),
        ]),
      ],
    );
    bool? downOf(Score s, int i) =>
        (s.measures.first.elements[i] as NoteElement).stemsDown;

    test('through MusicXML, MEI, MuseScore and kern', () {
      for (final (name, back) in [
        ('MusicXML', scoreFromMusicXml(scoreToMusicXml(score))),
        ('MEI', scoreFromMei(scoreToMei(score))),
        ('MuseScore', scoreFromMscx(scoreToMscx(score))),
        ('kern', scoreFromKern(scoreToKern(score))),
      ]) {
        expect([
          downOf(back, 0),
          downOf(back, 1),
          downOf(back, 2)
        ], [
          false,
          true,
          null
        ], reason: name);
      }
    });

    test('the layout draws it', () {
      final l = layoutOf(score);
      double stemTipY(String id) => l.primitives
          .whereType<LinePrimitive>()
          .where((p) => p.elementId == id && p.from.x == p.to.x)
          .map((p) => p.from.y < p.to.y ? p.from.y : p.to.y)
          .reduce((a, b) => a < b ? a : b);
      // B4 is the middle line (y = 2): an up stem reaches above it, a down
      // stem starts at it.
      expect(stemTipY('up'), lessThan(1));
      expect(stemTipY('down'), closeTo(2, 0.3));
    });

    test('a beam group follows its stated stem', () {
      final eighths = [
        for (final (i, step) in [Step.b, Step.c, Step.d, Step.e].indexed)
          NoteElement(
              pitches: [Pitch(step, octave: 5)],
              duration: const NoteDuration(DurationBase.eighth),
              stemsDown: i == 0 ? false : null,
              id: 'b$i'),
      ];
      final l = layoutOf(Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(2, 4),
          measures: [Measure(eighths)]));
      // High notes would beam stems down; the first note says up.
      final beam = l.primitives.whereType<BeamPrimitive>().first;
      expect(beam.start.y, lessThan(0), reason: 'beam above the staff');
    });
  });

  group('verse numbers', () {
    Score song(int verses, {int bars = 1}) {
      final base = Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: List.filled(bars, 'c5:q d5 e5 f5').join(' | '));
      final ids = [
        for (final m in base.measures)
          for (final e in m.elements) e.id!,
      ];
      return base.copyWith(lyrics: [
        for (var v = 1; v <= verses; v++)
          for (final id in ids) Lyric(id, 'la', verse: v),
      ]);
    }

    Iterable<String> numbers(ScoreLayout l) => l.primitives
        .whereType<TextPrimitive>()
        .map((t) => t.text)
        .where((t) => RegExp(r'^\d+\.$').hasMatch(t));

    test('two verses are numbered, before their first syllable', () {
      final l = layoutOf(song(2));
      expect(numbers(l).toList(), ['1.', '2.']);
      final one = l.primitives
          .whereType<TextPrimitive>()
          .firstWhere((t) => t.text == '1.');
      final firstLa = l.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == 'la')
          .map((t) => t.position.x)
          .reduce((a, b) => a < b ? a : b);
      expect(one.position.x, lessThan(firstLa));
    });

    test('one verse is not', () {
      expect(numbers(layoutOf(song(1))), isEmpty);
    });

    test('a wrapped song numbers only the line where the lyrics begin', () {
      final lines = layoutSystems(song(2, bars: 4), settings,
          maxWidth: 30, systemBreaks: const {1, 2, 3}).systems;
      expect(lines, hasLength(4));
      expect(numbers(lines.first.layout), hasLength(2));
      for (final line in lines.skip(1)) {
        expect(numbers(line.layout), isEmpty);
      }
    });
  });

  test('house styles: engraved is denser, spacious roomier, none collide', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: List.filled(16, 'c5:e d5 e5 f5 g5:q a5').join(' | '),
    );
    int lines(LayoutSettings s) =>
        layoutSystems(score, s, maxWidth: 80).systems.length;
    final engraved = LayoutSettings.engraved(metadata: settings.metadata);
    final spacious = LayoutSettings.spacious(metadata: settings.metadata);
    expect(lines(engraved), lessThanOrEqualTo(lines(settings)));
    expect(lines(spacious), greaterThanOrEqualTo(lines(settings)));
    for (final s in [engraved, spacious]) {
      for (final line in layoutSystems(score, s, maxWidth: 80).systems) {
        expect(
            lintLayout(line.layout, s, closes: false)
                .where((i) => i.rule.contains('collision')),
            isEmpty);
      }
    }
  });

  test('a renderer\'s own text measure replaces the estimate', () {
    final score = Score.simple(
        notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
        lyrics: 'one two three four five six se- ven');
    double spanOf(LayoutSettings s) {
      final xs = const LayoutEngine()
          .layout(score, s)
          .primitives
          .whereType<TextPrimitive>()
          .map((t) => t.position.x);
      return xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);
    }

    final narrow = LayoutSettings(
        metadata: settings.metadata,
        textWidth: (t, size) => 0.3 * size * t.length);
    final wide = LayoutSettings(
        metadata: settings.metadata,
        textWidth: (t, size) => 0.9 * size * t.length);
    expect(spanOf(wide), greaterThan(spanOf(narrow)));
  });

  test('two voices resting alike draw one rest, in place', () {
    final l = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q r:q d5:h ; a4:q r:q b4:h'));
    final rests = l.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName == SmuflGlyph.restQuarter)
        .toList();
    expect(rests, hasLength(1));
    expect(rests.single.position.y, 2.0, reason: 'on the middle line');
  });
}
