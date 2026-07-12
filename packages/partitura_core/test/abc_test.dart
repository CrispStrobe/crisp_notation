import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

List<String> _pitches(Score s) => [
      for (final m in s.measures)
        for (final e in m.elements)
          if (e is NoteElement)
            e.pitches
                .map((p) => '${p.step.name}${p.alter}/${p.octave}')
                .join('+')
          else
            'rest',
    ];

List<String> _durs(Score s) => [
      for (final m in s.measures)
        for (final e in m.elements)
          '${e.duration.base.name}.${e.duration.dots}',
    ];

void main() {
  group('ABC import', () {
    test('header: meter, unit length, key, clef', () {
      final s = scoreFromAbc('X:1\nM:3/4\nL:1/4\nK:Bb\nB c d|\n');
      expect(s.timeSignature, const TimeSignature(3, 4));
      expect(s.keySignature.fifths, -2); // Bb major
      expect(s.measures.single.elements, hasLength(3));
    });

    test('modes map to the right key signature', () {
      expect(scoreFromAbc('X:1\nK:Edor\nE|\n').keySignature.fifths, 2);
      expect(scoreFromAbc('X:1\nK:Am\nA|\n').keySignature.fifths, 0);
      expect(scoreFromAbc('X:1\nK:Dm\nD|\n').keySignature.fifths, -1);
      expect(scoreFromAbc('X:1\nK:Gmix\nG|\n').keySignature.fifths, 0);
    });

    test('pitches: octave marks and default note length', () {
      final s = scoreFromAbc('X:1\nL:1/8\nK:C\nC, C c c2 c\'|\n');
      final notes = s.measures.single.elements.cast<NoteElement>();
      expect(notes.map((n) => n.pitches.single.octave), [3, 4, 5, 5, 6]);
      expect(notes[3].duration, NoteDuration.quarter); // c2 at L=1/8
    });

    test('key signature applies to unmarked notes; naturals persist', () {
      // In G major, F is sharp; =F is natural and holds for the measure.
      final s = scoreFromAbc('X:1\nL:1/4\nK:G\nF =F F | F|\n');
      final m0 = s.measures[0].elements.cast<NoteElement>();
      expect(m0[0].pitches.single.alter, 1); // key sharp
      expect(m0[1].pitches.single.alter, 0); // explicit natural
      expect(m0[2].pitches.single.alter, 0); // natural persists in the bar
      expect(s.measures[1].elements.cast<NoteElement>()[0].pitches.single.alter,
          1); // sharp again next bar
    });

    test('broken rhythm, ties, tuplets, slurs, grace, staccato', () {
      final s = scoreFromAbc(
          'X:1\nM:4/4\nL:1/4\nK:C\nA>B c<d|(3EFG A-A|{gg}B .c d e|\n');
      final m0 = s.measures[0].elements.cast<NoteElement>();
      expect(m0.map((n) => '${n.duration.base.name}.${n.duration.dots}'),
          ['quarter.1', 'eighth.0', 'eighth.0', 'quarter.1']);
      expect(s.measures[1].tuplets.single.actual, 3);
      expect(s.measures[1].elements.cast<NoteElement>()[3].tieToNext, isTrue);
      expect(s.slurs, isEmpty); // none here
      final m2 = s.measures[2].elements.cast<NoteElement>();
      expect(m2[0].graceNotes, hasLength(2));
      expect(m2[1].articulations, {Articulation.staccato});
    });

    test('decorations: !…! articulations, ornaments and dynamics', () {
      final s = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\n'
          '!trill!C !fermata!D !p!E !accent!F|!tenuto!G !marcato!A B d|\n');
      final n = s.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      expect(n[0].ornament, Ornament.trill); // C
      expect(n[1].articulations, {Articulation.fermata}); // D
      expect(n[3].articulations, {Articulation.accent}); // F
      expect(n[4].articulations, {Articulation.tenuto}); // G
      expect(n[5].articulations, {Articulation.marcato}); // A
      expect(s.dynamics.single.level, DynamicLevel.p); // on E (n[2])
    });

    test('bowing: u/v shorthand and !upbow!/!downbow! decorations', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\nuC vD !upbow!E !downbow!F|\n');
      final n = s.measures.single.elements.cast<NoteElement>();
      expect(n[0].articulations, {Articulation.upBow});
      expect(n[1].articulations, {Articulation.downBow});
      expect(n[2].articulations, {Articulation.upBow});
      expect(n[3].articulations, {Articulation.downBow});
      // Round-trips as u/v.
      final back = scoreFromAbc(scoreToAbc(s));
      final bn = back.measures.single.elements.cast<NoteElement>();
      expect(bn[0].articulations, {Articulation.upBow});
      expect(bn[1].articulations, {Articulation.downBow});
    });

    test('shorthand decorations ~ H T M P', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\n~C HD TE MF Pc|\n');
      final n = s.measures.single.elements.cast<NoteElement>();
      expect(n[0].ornament, Ornament.turn); // ~
      expect(n[1].articulations, {Articulation.fermata}); // H
      expect(n[2].ornament, Ornament.trill); // T
      expect(n[3].ornament, Ornament.mordent); // M
      expect(n[4].ornament, Ornament.shortTrill); // P
    });

    test('navigation decorations !segno! !D.S.! drive the playback jump', () {
      final s = scoreFromAbc(
          'X:1\nM:4/4\nL:1/4\nK:C\n!segno!A B C D|E F G A !D.S.!|\n');
      expect(s.measures[0].navigation, NavigationMark.segno);
      expect(s.measures[1].navigation, NavigationMark.dalSegno);
      // The D.S. replays from the segno: 8 notes then both bars again.
      expect(playbackTimeline(s), hasLength(16));
    });

    test('inline fields [K:] [M:] [L:] change key/meter/length mid-tune', () {
      final s = scoreFromAbc(
          'X:1\nM:4/4\nL:1/8\nK:C\nCDEF|[K:D]DEFG|[M:3/4][L:1/4]A B c|\n');
      expect(s.measures[1].keyChange?.fifths, 2); // D major
      // The new key sharpens unmarked F in that measure.
      expect(
          s.measures[1].elements
              .cast<NoteElement>()
              .firstWhere((n) => n.pitches.single.step == Step.f)
              .pitches
              .single
              .alter,
          1);
      expect(s.measures[2].timeChange, const TimeSignature(3, 4));
      expect(s.measures[2].elements.first.duration, NoteDuration.quarter);
    });

    test('slurs and quoted chord symbols', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\n"C"(CE) "G"G z|\n');
      expect(s.slurs, hasLength(1));
      expect(s.annotations.map((a) => a.text), ['C', 'G']);
    });

    test('bar lines: repeats and double/final', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\n|:C D:| E F|| G4|]\n');
      expect(s.measures[0].startRepeat, isTrue);
      expect(s.measures[0].endRepeat, isTrue);
      expect(s.measures[1].barline, BarlineStyle.doubleBar);
      expect(s.measures[2].barline, BarlineStyle.finalBar);
    });

    test('variant endings (voltas), both |1 and [1 forms', () {
      for (final abc in [
        'X:1\nM:4/4\nL:1/4\nK:C\n|:A B|C D|1E F:|2G A|]\n',
        'X:1\nM:4/4\nL:1/4\nK:C\n|:A B|C D|[1E F:|[2G A|]\n',
      ]) {
        final s = scoreFromAbc(abc);
        expect(s.measures[0].startRepeat, isTrue);
        final v1 = s.measures.firstWhere((m) => m.volta == 1);
        expect(v1.endRepeat, isTrue);
        expect(s.measures.any((m) => m.volta == 2), isTrue);
        expect(s.measures.last.barline, BarlineStyle.finalBar);
      }
    });

    test('a bar directly before a chord is not eaten', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\nC|[EG]|\n');
      expect(s.measures[1].elements.single, isA<NoteElement>());
      expect(
          (s.measures[1].elements.single as NoteElement).pitches, hasLength(2));
    });

    test('w: lyrics align to notes with hyphens', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:G\nB A G A|\n'
          'w:Ma- ry had a\n');
      expect(s.lyrics.map((l) => l.text), ['Ma', 'ry', 'had', 'a']);
      expect(s.lyrics.first.hyphenToNext, isTrue);
    });

    test('multi-measure rest Z becomes a multi-rest measure', () {
      final s = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nC D E F|Z4|G A B c|\n');
      expect(s.measures[1].multiRest, 4);
      expect(s.measures[1].elements, isEmpty);
      // Round-trips.
      final back = scoreFromAbc(scoreToAbc(s));
      expect(back.measures[1].multiRest, 4);
    });

    test('positioned annotations "^…"/"_…" strip the position marker', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\n"_pizz."C "^arco"D E F|\n');
      expect(s.annotations.map((a) => a.text), ['pizz.', 'arco']);
    });

    test('acciaccatura grace {/…} reads its notes', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\n{/g}C D|\n');
      expect((s.measures.single.elements.first as NoteElement).graceNotes,
          hasLength(1));
    });

    test('multi-voice imports the first voice', () {
      final s = scoreFromAbc('X:1\nM:4/4\nL:1/4\nV:1\nV:2\nK:C\n'
          '[V:1] C D E F|\n[V:2] c d e f|\n');
      final octaves = s.measures.single.elements
          .cast<NoteElement>()
          .map((n) => n.pitches.single.octave);
      expect(octaves, everyElement(4)); // voice 1 (uppercase), not voice 2
    });

    test('a missing K: field is a FormatException', () {
      expect(
          () => scoreFromAbc('X:1\nT:No key\nCDEF\n'), throwsFormatException);
    });
  });

  group('fidelity: the abcjs example tune-book', () {
    // Real tunes used as import-fidelity fixtures: they must import without
    // error (features we don't model yet are skipped, not fatal). The melodies
    // ("Money Lost", "Pretty Little Liza", "Mary Had a Little Lamb") are
    // traditional / public-domain; the ABC encodings are from the abcjs
    // documentation example tune-book (docs.abcjs.net/analysis/tune-book.html —
    // abcjs is MIT-licensed), so they carry no license friction as test data.
    const moneyLost = '''
X: 1
T:Money Lost
M:3/4
L:1/8
Q:1/4=100
K:Dm
Ade|:"Dm"(f2d)e gf|"A7"e2^c4|"Gm"B>>^c BA BG|"A"A3Ade|"Dm"(f2d)e gf|"A7"e2^c4|
"Gm"A>>B "A7"AG FE|1"Dm"D3Ade:|2"Dm"D3DEF||:"Gm"(G2D)E FG|"Dm"A2F4|"Gm"B>>c "A7"BA BG|
"Dm"A3 DEF|"Gm"(G2D)EFG|"Dm"A2F4|"E7"E>>F "A7"ED^C2|1"Dm"D3DEF:|2"Dm"D6||
''';
    const prettyLiza = '''
X: 32
T:Pretty Little Liza
M:4/4
L:1/8
Q:1/2=106
K:Am
"Am"A2AA c2dd|e2eg e2dc|A2AA c2dd|e2cc A2cc|"Em"B2BB B2BB|
B2BB B2BB|"Am"A2AA c2dd|e2eg e2c2|"D"d2dd d2dd|d2dd d2cd|
"Am"e2cc A2c2|"G"BAG2 BAG2|"Am"A2AA A2AA|A2AA A2AA|:"Am"e4 a3e|"G"g2d2- d2eg|
"Am"a2aa ged2|"Em"e2ee e2ee|"Am"e4 a3e|"G"g2d2- d2Bc|"Em"d2e2 dcB2|"Am"A2AA A2AA:|
''';
    const mary = '''
X:77
T:Mary
M:C
L:1/4
K:G
BAGA| BBB2|AAA2| Bdd2|
w:Mar- y had a lit- tle lamb, lit- tle lamb, lit- tle lamb,
BAGA| BBBB|AABA |G|]
w:Mar- y had a lit- tle lamb whose fleece was white as snow.
''';

    test('Money Lost imports with its bars, chords and endings', () {
      final s = scoreFromAbc(moneyLost);
      expect(s.keySignature.fifths, -1); // D minor
      expect(s.timeSignature, const TimeSignature(3, 4));
      expect(s.measures.length, greaterThan(10));
      expect(s.annotations, isNotEmpty); // "Dm" "A7" …
      expect(s.measures.any((m) => m.volta == 1), isTrue); // |1 …:|2
    });

    test('Pretty Little Liza imports with a mid-tune repeat', () {
      final s = scoreFromAbc(prettyLiza);
      expect(s.keySignature.fifths, 0); // A minor
      expect(s.measures.any((m) => m.startRepeat), isTrue);
    });

    test('Mary imports with its two lyric lines', () {
      final s = scoreFromAbc(mary);
      expect(s.keySignature.fifths, 1); // G
      expect(s.lyrics, isNotEmpty);
      expect(s.lyrics.map((l) => l.text), contains('Mar'));
    });
  });

  group('ABC round-trip (score → abc → score)', () {
    void roundTrips(String abc) {
      final src = scoreFromAbc(abc);
      final back = scoreFromAbc(scoreToAbc(src));
      expect(_pitches(back), _pitches(src), reason: 'pitches');
      expect(_durs(back), _durs(src), reason: 'durations');
      expect(back.keySignature.fifths, src.keySignature.fifths);
      expect(back.timeSignature, src.timeSignature);
      expect(back.measures.length, src.measures.length);
      expect(back.annotations.map((a) => a.text),
          src.annotations.map((a) => a.text));
    }

    test('melody with accidentals, rhythm, rests', () {
      roundTrips('X:1\nM:4/4\nL:1/8\nK:G\n'
          'GABc d2e2|f2 ^f2 g4|_B2 =B2 c2 z2|A3/2 B/2 c d|\n');
    });

    test('chords, ties, tuplets, repeats', () {
      roundTrips('X:1\nM:4/4\nL:1/4\nK:D\n'
          '|:[CEG] A-A z|(3ABc d:|E F G A|]\n');
    });

    test('a scale in a flat key', () {
      roundTrips('X:1\nM:4/4\nL:1/4\nK:Eb\nE F G A|B c d e|\n');
    });
  });

  group('multi-voice → StaffSystem', () {
    test('single-voice tune yields a one-staff system', () {
      final sys = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nCDEF|\n');
      expect(sys.staves, hasLength(1));
      expect(_pitches(sys.staves.first), ['c0/4', 'd0/4', 'e0/4', 'f0/4']);
    });

    test('field-line voices become separate staves with their own clefs', () {
      final sys = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\n'
          'V:1 clef=treble\n'
          'V:2 clef=bass\n'
          'K:C\n'
          'V:1\n'
          'CDEF|\n'
          'V:2\n'
          'C,D,E,F,|\n');
      expect(sys.staves, hasLength(2));
      expect(sys.staves[0].clef, Clef.treble);
      expect(sys.staves[1].clef, Clef.bass);
      expect(_pitches(sys.staves[0]), ['c0/4', 'd0/4', 'e0/4', 'f0/4']);
      expect(_pitches(sys.staves[1]), ['c0/3', 'd0/3', 'e0/3', 'f0/3']);
    });

    test('inline [V:n] prefixes split the body by voice', () {
      final sys = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\nK:C\n'
          '[V:1] CDEF|\n'
          '[V:2] G,A,B,C|\n'
          '[V:1] GABc|\n');
      expect(sys.staves, hasLength(2));
      expect(_pitches(sys.staves[0]),
          ['c0/4', 'd0/4', 'e0/4', 'f0/4', 'g0/4', 'a0/4', 'b0/4', 'c0/5']);
      expect(_pitches(sys.staves[1]), ['g0/3', 'a0/3', 'b0/3', 'c0/4']);
    });

    test('element ids are unique across voices', () {
      final sys = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\nK:C\n'
          'V:1\nCDEF|\n'
          'V:2\nGABc|\n');
      final ids = [
        for (final s in sys.staves)
          for (final m in s.measures)
            for (final e in m.elements) e.id,
      ];
      expect(ids.toSet(), hasLength(ids.length), reason: 'no id collisions');
    });

    test('scoreFromAbc still returns the first voice', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\n'
          'V:1\nCDEF|\n'
          'V:2\nGABc|\n');
      expect(_pitches(score), ['c0/4', 'd0/4', 'e0/4', 'f0/4']);
    });

    test('per-voice lyrics align to their own voice', () {
      final sys = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\nK:C\n'
          'V:1\nCDEF|\nw:one two three four\n'
          'V:2\nGABc|\nw:la la la la\n');
      expect(sys.staves[0].lyrics.map((l) => l.text),
          containsAll(['one', 'two', 'three', 'four']));
      expect(sys.staves[1].lyrics.map((l) => l.text), everyElement('la'));
    });
  });

  group('tempo, parts, continuation', () {
    test('Q: 1/4=120 becomes a metronome annotation on the first note', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nQ:1/4=120\nK:C\nCDEF|\n');
      final first = score.measures.first.elements.first;
      expect(score.annotations, contains(Annotation(first.id!, '♩ = 120')));
    });

    test('Q: with a quoted label combines label and mark', () {
      final score =
          scoreFromAbc('X:1\nM:4/4\nL:1/4\nQ:"Allegro" 1/4=120\nK:C\nCDEF|\n');
      expect(score.annotations.map((a) => a.text), contains('Allegro ♩ = 120'));
    });

    test('bare Q:120 assumes a quarter-note beat', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nQ:120\nK:C\nCDEF|\n');
      expect(score.annotations.map((a) => a.text), contains('♩ = 120'));
    });

    test('mid-tune P: part label becomes an annotation', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\n'
          'CDEF|\n'
          'P:B\n'
          'GABc|\n');
      expect(score.annotations.map((a) => a.text), contains('B'));
    });

    test('mid-tune Q: change becomes an annotation', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nQ:1/4=120\nK:C\n'
          'CDEF|\n'
          'Q:1/4=90\n'
          'GABc|\n');
      expect(score.annotations.map((a) => a.text),
          containsAll(['♩ = 120', '♩ = 90']));
    });

    test('a trailing backslash continues the line without a stray token', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nCD\\\nEF|\n');
      expect(_pitches(score), ['c0/4', 'd0/4', 'e0/4', 'f0/4']);
      expect(score.measures, hasLength(1));
    });

    test('a dotted barline ".|" reads and round-trips', () {
      final s = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nC D E F.|G A B c|\n');
      expect(s.measures[0].barline, BarlineStyle.dotted);
      final back = scoreFromAbc(scoreToAbc(s));
      expect(back.measures[0].barline, BarlineStyle.dotted);
    });

    test('a lone "." is still staccato, not a dotted bar', () {
      final s = scoreFromAbc('X:1\nL:1/4\nK:C\n.C D E F|\n');
      final n = s.measures.single.elements.cast<NoteElement>();
      expect(n[0].articulations, {Articulation.staccato});
      expect(s.measures[0].barline, BarlineStyle.normal);
    });

    test('in a multi-voice tune the tempo sits on the top staff only', () {
      final sys = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\nQ:1/4=100\nK:C\n'
          'V:1\nCDEF|\n'
          'V:2\nGABc|\n');
      expect(sys.staves[0].annotations.map((a) => a.text), contains('♩ = 100'));
      expect(sys.staves[1].annotations.map((a) => a.text),
          isNot(contains('♩ = 100')));
    });
  });
}
