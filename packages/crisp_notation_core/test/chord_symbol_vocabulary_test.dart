import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:crisp_notation_core/src/lilypond/lilypond_chordmode.dart';
import 'package:test/test.dart';

/// The chord-symbol vocabulary beyond the first fifteen kinds: MusicXML's
/// full `<kind>` list and `<degree>` alterations, how they print, how they
/// sound, and that every format with chord symbols carries them.
void main() {
  const c = Pitch(Step.c);
  ChordSymbol sym(ChordSymbolKind kind,
          [List<ChordDegree> degrees = const [], Pitch root = c]) =>
      ChordSymbol('e0', root, kind, degrees: degrees);

  group('the model', () {
    test('the original fifteen kinds keep their place and meaning', () {
      expect(ChordSymbolKind.values.take(15).map((k) => k.name), [
        'major', 'minor', 'diminished', 'augmented', 'dominantSeventh', //
        'majorSeventh', 'minorSeventh', 'halfDiminishedSeventh',
        'diminishedSeventh', 'minorMajorSeventh', 'sixth', 'minorSixth',
        'dominantNinth', 'suspendedFourth', 'suspendedSecond',
      ]);
      expect(ChordSymbolKind.dominantNinth.tones,
          {1: 0, 3: 4, 5: 7, 7: 10, 9: 14});
    });

    test('every MusicXML kind is there, once', () {
      final xml = ChordSymbolKind.values.map((k) => k.musicXmlKind).toList();
      expect(xml.toSet(), hasLength(xml.length));
      expect(
          xml,
          containsAll([
            'major-ninth', 'minor-ninth', 'dominant-11th', 'major-11th', //
            'minor-11th', 'dominant-13th', 'major-13th', 'minor-13th',
            'augmented-seventh', 'Neapolitan', 'Italian', 'French', 'German',
            'pedal', 'power', 'Tristan', 'other', 'none',
          ]));
    });

    test('degrees apply to the kind\'s tones', () {
      expect(
          sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)])
              .tones,
          {1: 0, 3: 4, 5: 7, 7: 10, 9: 13});
      expect(
          sym(ChordSymbolKind.minorSeventh, [ChordDegree.alter(5, -1)]).tones,
          {1: 0, 3: 3, 5: 6, 7: 10});
      expect(sym(ChordSymbolKind.major, [ChordDegree.subtract(3)]).tones,
          {1: 0, 5: 7});
      // An added seventh is a minor one, as MusicXML counts it.
      expect(sym(ChordSymbolKind.suspendedFourth, [ChordDegree.add(7)]).tones,
          {1: 0, 4: 5, 5: 7, 7: 10});
    });

    test('equality, hashing and copyWith see the degrees', () {
      final a =
          sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)]);
      final b =
          sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(sym(ChordSymbolKind.dominantSeventh)));
      expect(
          a.copyWith(degrees: const []), sym(ChordSymbolKind.dominantSeventh));
      expect(a.copyWith(elementId: 'e1').degrees, a.degrees);
      expect(const ChordDegree.alter(5, 1),
          const ChordDegree(5, alter: 1, type: ChordDegreeType.alter));
    });

    test('transposition keeps the degrees', () {
      final s = Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(const <MusicElement>[
            NoteElement(
                id: 'e0',
                pitches: [Pitch(Step.c)],
                duration: NoteDuration(DurationBase.whole)),
          ]),
        ],
        chordSymbols: [
          sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)]),
        ],
      );
      final up = s.transposedBy(const Interval(IntervalQuality.major, 2));
      expect(up.chordSymbols.single.text, 'D7(b9)');
    });
  });

  group('text', () {
    void prints(ChordSymbol s, String text) =>
        test(text, () => expect(s.text, text));
    prints(sym(ChordSymbolKind.majorNinth), 'Cmaj9');
    prints(sym(ChordSymbolKind.minorEleventh), 'Cm11');
    prints(sym(ChordSymbolKind.dominantThirteenth), 'C13');
    prints(sym(ChordSymbolKind.augmentedSeventh), 'Caug7');
    prints(sym(ChordSymbolKind.power), 'C5');
    prints(sym(ChordSymbolKind.none), 'N.C.');
    prints(
        sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)],
            const Pitch(Step.g)),
        'G7(b9)');
    prints(
        sym(ChordSymbolKind.dominantSeventh,
            [ChordDegree.add(9, alter: -1), ChordDegree.add(11, alter: 1)]),
        'C7(b9,#11)');
    prints(sym(ChordSymbolKind.sixth, [ChordDegree.add(9)]), 'C6/9');
    prints(sym(ChordSymbolKind.minorSixth, [ChordDegree.add(9)]), 'Cm6/9');
    prints(sym(ChordSymbolKind.suspendedFourth, [ChordDegree.add(9)]),
        'Csus4(add9)');
    prints(
        sym(ChordSymbolKind.suspendedFourth, [ChordDegree.add(7)]), 'C7sus4');
    prints(
        sym(ChordSymbolKind.suspendedFourth,
            [ChordDegree.add(7), ChordDegree.add(9)]),
        'C9sus4');
    prints(sym(ChordSymbolKind.major, [ChordDegree.add(9)]), 'Cadd9');
    prints(sym(ChordSymbolKind.minor, [ChordDegree.add(9)]), 'Cm(add9)');
    prints(sym(ChordSymbolKind.major, [ChordDegree.subtract(3)]), 'C(omit3)');
    prints(sym(ChordSymbolKind.minorSeventh, [ChordDegree.alter(5, -1)]),
        'Cm7(b5)');
  });

  group('parseChordName reads', () {
    void reads(String text, ChordSymbolKind kind,
        [List<ChordDegree> degrees = const [], String? back]) {
      test(text, () {
        final p = parseChordName(text);
        expect(p, isNotNull, reason: text);
        expect(p!.kind, kind, reason: text);
        expect(p.degrees, degrees, reason: text);
        final s =
            ChordSymbol('e0', p.root, p.kind, bass: p.bass, degrees: p.degrees);
        expect(s.text, back ?? text, reason: 'printed back');
      });
    }

    reads('Cmaj9', ChordSymbolKind.majorNinth);
    reads('CM9', ChordSymbolKind.majorNinth, const [], 'Cmaj9');
    reads('Dm9', ChordSymbolKind.minorNinth);
    reads('Dmin11', ChordSymbolKind.minorEleventh, const [], 'Dm11');
    reads('G11', ChordSymbolKind.dominantEleventh);
    reads('Ebmaj13', ChordSymbolKind.majorThirteenth);
    reads('Bb13', ChordSymbolKind.dominantThirteenth);
    reads('F-13', ChordSymbolKind.minorThirteenth, const [], 'Fm13');
    reads('C+7', ChordSymbolKind.augmentedSeventh, const [], 'Caug7');
    reads('C7#5', ChordSymbolKind.augmentedSeventh, const [], 'Caug7');
    reads('A5', ChordSymbolKind.power);
    reads('N.C.', ChordSymbolKind.none);
    reads('G7b9', ChordSymbolKind.dominantSeventh,
        const [ChordDegree.add(9, alter: -1)], 'G7(b9)');
    reads('G7(b9)', ChordSymbolKind.dominantSeventh,
        const [ChordDegree.add(9, alter: -1)]);
    reads('G7(b9,#11)', ChordSymbolKind.dominantSeventh,
        const [ChordDegree.add(9, alter: -1), ChordDegree.add(11, alter: 1)]);
    reads(
        'G7#11b9',
        ChordSymbolKind.dominantSeventh,
        const [ChordDegree.add(9, alter: -1), ChordDegree.add(11, alter: 1)],
        'G7(b9,#11)');
    reads('C7(9)', ChordSymbolKind.dominantSeventh, const [ChordDegree.add(9)],
        'C7(add9)');
    reads('C7b5', ChordSymbolKind.dominantSeventh,
        const [ChordDegree.alter(5, -1)], 'C7(b5)');
    reads('Cmaj7#11', ChordSymbolKind.majorSeventh,
        const [ChordDegree.add(11, alter: 1)], 'Cmaj7(#11)');
    reads('C13b9', ChordSymbolKind.dominantThirteenth,
        const [ChordDegree.alter(9, -1)], 'C13(b9)');
    reads('C6/9', ChordSymbolKind.sixth, const [ChordDegree.add(9)]);
    reads('C69', ChordSymbolKind.sixth, const [ChordDegree.add(9)], 'C6/9');
    reads('Am6/9', ChordSymbolKind.minorSixth, const [ChordDegree.add(9)]);
    reads('Csus4(add9)', ChordSymbolKind.suspendedFourth,
        const [ChordDegree.add(9)]);
    reads('Csus2add9', ChordSymbolKind.suspendedSecond,
        const [ChordDegree.add(9)], 'Csus2(add9)');
    reads(
        'C7sus4', ChordSymbolKind.suspendedFourth, const [ChordDegree.add(7)]);
    reads('C7sus', ChordSymbolKind.suspendedFourth, const [ChordDegree.add(7)],
        'C7sus4');
    reads('Bb9sus4', ChordSymbolKind.suspendedFourth,
        const [ChordDegree.add(7), ChordDegree.add(9)]);
    reads('C7sus4(b9)', ChordSymbolKind.suspendedFourth,
        const [ChordDegree.add(7), ChordDegree.add(9, alter: -1)]);
    reads('Cadd9', ChordSymbolKind.major, const [ChordDegree.add(9)]);
    reads(
        'C(add9)', ChordSymbolKind.major, const [ChordDegree.add(9)], 'Cadd9');
    reads('Cm(add9)', ChordSymbolKind.minor, const [ChordDegree.add(9)]);
    reads('C(no3)', ChordSymbolKind.major, const [ChordDegree.subtract(3)],
        'C(omit3)');
    reads('C7(omit3)', ChordSymbolKind.dominantSeventh,
        const [ChordDegree.subtract(3)]);

    test('a six-nine over a bass', () {
      final p = parseChordName('C6/9/E')!;
      expect(p.kind, ChordSymbolKind.sixth);
      expect(p.degrees, const [ChordDegree.add(9)]);
      expect(p.bass!.step, Step.e);
    });

    test('the functional kinds read back from their own suffix', () {
      for (final kind in [
        ChordSymbolKind.neapolitan,
        ChordSymbolKind.italian,
        ChordSymbolKind.french,
        ChordSymbolKind.german,
        ChordSymbolKind.tristan,
        ChordSymbolKind.pedal,
      ]) {
        final text = sym(kind, const [], const Pitch(Step.a, alter: -1)).text;
        expect(parseChordName(text)?.kind, kind, reason: text);
      }
    });
  });

  group('chordSpellingOf', () {
    void spells(String mods, ChordSymbolKind kind, List<ChordDegree> degrees) {
      test(mods, () {
        final s = chordSpellingOf(lilyChordModeSteps(mods));
        expect(s.kind, kind, reason: mods);
        expect(s.degrees, degrees, reason: mods);
      });
    }

    spells('7.9-', ChordSymbolKind.dominantSeventh,
        const [ChordDegree.add(9, alter: -1)]);
    spells('9^7', ChordSymbolKind.major, const [ChordDegree.add(9)]);
    // A tie (one degree either way) goes to the kind listed first.
    spells(
        '13.11', ChordSymbolKind.dominantEleventh, const [ChordDegree.add(13)]);
    spells(
        '7sus4', ChordSymbolKind.suspendedFourth, const [ChordDegree.add(7)]);
    spells('9sus4', ChordSymbolKind.suspendedFourth,
        const [ChordDegree.add(7), ChordDegree.add(9)]);
    spells('6.9', ChordSymbolKind.sixth, const [ChordDegree.add(9)]);
    spells('m7.5-', ChordSymbolKind.halfDiminishedSeventh, const []);
    spells('maj9', ChordSymbolKind.majorNinth, const []);
    spells('m13', ChordSymbolKind.minorThirteenth, const []);
    spells('aug7', ChordSymbolKind.augmentedSeventh, const []);
    spells('5', ChordSymbolKind.power, const []);
    spells('6^5', ChordSymbolKind.sixth, const [ChordDegree.subtract(5)]);
  });

  // Each row was played by LilyPond 2.24 (`\chordmode` on a staff, to MIDI):
  // the semitones above the root it sounded.
  group('LilyPond chord mode builds what LilyPond 2.24 plays', () {
    const measured = {
      'maj9': [0, 4, 7, 11, 14],
      'm9': [0, 3, 7, 10, 14],
      '11': [0, 4, 7, 10, 14, 17],
      'maj11': [0, 4, 7, 11, 14, 17],
      'm11': [0, 3, 7, 10, 14, 17],
      '13': [0, 4, 7, 10, 14, 21],
      'maj13': [0, 4, 7, 11, 14, 21],
      'm13': [0, 3, 7, 10, 14, 17, 21],
      '13sus4': [0, 5, 7, 10, 14, 17, 21],
      'm13^11': [0, 3, 7, 10, 14, 21],
      '13.11': [0, 4, 7, 10, 14, 17, 21],
      '13.11-': [0, 4, 7, 10, 14, 16, 21],
      'aug7': [0, 4, 8, 10],
      '5': [0, 7],
      '1': [0],
      '2': [0, 2],
      '3': [0, 4],
      '4': [0, 4, 5],
      '6.9': [0, 4, 7, 9, 14],
      '7.9-': [0, 4, 7, 10, 13],
      '9^7': [0, 4, 7, 14],
      '9.9-': [0, 4, 7, 10, 13],
      '7sus4': [0, 5, 7, 10],
      '9sus4': [0, 5, 7, 10, 14],
      'sus4.9': [0, 5, 7, 14],
      'sus4.7': [0, 5, 7, 10],
      '6+^5': [0, 4, 10],
      '6+.4+^5': [0, 4, 6, 10],
      '1.4+.6+.9+': [0, 6, 10, 15],
      'maj7.11+': [0, 4, 7, 11, 18],
      'dim9': [0, 3, 6, 9, 14],
      '9^3.4': [0, 7, 10, 14],
      'm6.9': [0, 3, 7, 9, 14],
    };
    for (final e in measured.entries) {
      test('c:${e.key}', () {
        expect(lilyChordModeSteps(e.key).values.toList()..sort(), e.value);
      });
    }

    test('every kind and degree is written as modifiers that build it', () {
      final chords = [
        for (final k in ChordSymbolKind.values)
          if (k != ChordSymbolKind.none) sym(k),
        sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)]),
        sym(ChordSymbolKind.majorSeventh, [ChordDegree.add(11, alter: 1)]),
        sym(ChordSymbolKind.majorNinth, [ChordDegree.alter(7, -1)]),
        sym(ChordSymbolKind.diminishedSeventh, [ChordDegree.alter(5, 1)]),
        sym(ChordSymbolKind.major, [ChordDegree.add(9)]),
        sym(ChordSymbolKind.major, [ChordDegree.subtract(5)]),
        sym(ChordSymbolKind.suspendedFourth,
            [ChordDegree.add(7), ChordDegree.add(9)]),
      ];
      for (final s in chords) {
        final mods = lilyChordMods(s);
        expect(lilyChordModeSteps(mods), s.tones, reason: '${s.text}: $mods');
      }
    });
  });

  group('playback voices the full chord', () {
    List<List<int>> played(List<ChordSymbol> chords) {
      final s = Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < chords.length; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.c)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ]),
        ],
        chordSymbols: [
          for (var i = 0; i < chords.length; i++)
            chords[i].copyWith(elementId: 'e$i'),
        ],
      );
      return [
        for (final n in playbackTimeline(s, voiceChordSymbols: true))
          if (n.chordPitches case final p?) [for (final x in p) x.midiNumber],
      ];
    }

    test('extensions and degrees, from middle C up', () {
      expect(
          played([
            sym(ChordSymbolKind.dominantThirteenth),
            sym(ChordSymbolKind.minorThirteenth),
            sym(ChordSymbolKind.dominantSeventh,
                [ChordDegree.add(9, alter: -1)], const Pitch(Step.g)),
            sym(ChordSymbolKind.sixth, [ChordDegree.add(9)]),
          ]),
          [
            [60, 64, 67, 70, 74, 81],
            [60, 63, 67, 70, 74, 77, 81],
            [67, 71, 74, 77, 80],
            [60, 64, 67, 69, 74],
          ]);
    });

    // LilyPond 2.24's MIDI for each: the bass goes below the root, and the
    // tones above it follow only while they land below the lowest tone that
    // stayed.
    test('a slash bass inverts an extended chord as LilyPond does', () {
      expect(
          played([
            sym(ChordSymbolKind.dominantNinth)
                .copyWith(bass: const Pitch(Step.e)), // c:9/e
            sym(ChordSymbolKind.dominantNinth)
                .copyWith(bass: const Pitch(Step.d)), // c:9/d
            sym(ChordSymbolKind.dominantThirteenth)
                .copyWith(bass: const Pitch(Step.d)), // c:13/d
            sym(ChordSymbolKind.major, [ChordDegree.add(9)])
                .copyWith(bass: const Pitch(Step.e)), // c:9^7/e
          ]),
          [
            [52, 55, 58, 60, 74],
            [50, 60, 64, 67, 70],
            [50, 57, 60, 64, 67, 70],
            [52, 55, 60, 74],
          ]);
    });

    test('a triad inverts as before', () {
      expect(
          played([
            sym(ChordSymbolKind.major, const [], const Pitch(Step.g))
                .copyWith(bass: const Pitch(Step.b)), // g/b
            sym(ChordSymbolKind.major).copyWith(bass: const Pitch(Step.e)),
          ]),
          [
            [59, 62, 67],
            [52, 55, 60],
          ]);
    });

    test('N.C. ends the chord before it and sounds nothing', () {
      expect(played([sym(ChordSymbolKind.major), sym(ChordSymbolKind.none)]), [
        [60, 64, 67],
      ]);
      final s = Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(2, 4),
        measures: [
          Measure(const <MusicElement>[
            NoteElement(
                id: 'e0',
                pitches: [Pitch(Step.c)],
                duration: NoteDuration(DurationBase.quarter)),
            NoteElement(
                id: 'e1',
                pitches: [Pitch(Step.c)],
                duration: NoteDuration(DurationBase.quarter)),
          ]),
        ],
        chordSymbols: [
          sym(ChordSymbolKind.major),
          sym(ChordSymbolKind.none).copyWith(elementId: 'e1'),
        ],
      );
      final chord = playbackTimeline(s, voiceChordSymbols: true)
          .where((n) => n.chordPitches != null)
          .single;
      expect(chord.duration, Fraction(1, 4));
    });
  });

  group('every format carries degrees', () {
    Score scored(List<ChordSymbol> chords) => Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [
            Measure(<MusicElement>[
              for (var i = 0; i < 4; i++)
                NoteElement(
                  id: 'e$i',
                  pitches: const [Pitch(Step.c)],
                  duration: const NoteDuration(DurationBase.quarter),
                ),
            ]),
          ],
          chordSymbols: [
            for (var i = 0; i < chords.length; i++)
              chords[i].copyWith(elementId: 'e$i'),
          ],
        );

    final hops = <String, Score Function(Score)>{
      'musicxml': (s) => scoreFromMusicXml(scoreToMusicXml(s)),
      'mei': (s) => scoreFromMei(scoreToMei(s)),
      'kern': (s) => scoreFromKern(scoreToKern(s)),
      'abc': (s) => scoreFromAbc(scoreToAbc(s)),
      'lilypond': (s) => scoreFromLilyPond(scoreToLilyPond(s)),
      'musescore': (s) => scoreFromMscx(scoreToMscx(s)),
    };
    // Spelled as every reader spells them back: degrees sorted, an altered
    // degree the kind lacks added, the kind that needs fewest degrees.
    final batches = [
      [
        sym(ChordSymbolKind.majorNinth, const [],
            const Pitch(Step.e, alter: -1)),
        sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)],
            const Pitch(Step.g)),
        sym(ChordSymbolKind.sixth, [ChordDegree.add(9)], const Pitch(Step.f)),
        sym(ChordSymbolKind.suspendedFourth, [ChordDegree.add(9)],
            const Pitch(Step.d)),
      ],
      [
        sym(
            ChordSymbolKind.suspendedFourth,
            [ChordDegree.add(7), ChordDegree.add(9)],
            const Pitch(Step.b, alter: -1)),
        sym(ChordSymbolKind.dominantSeventh,
            [ChordDegree.add(9, alter: -1), ChordDegree.add(11, alter: 1)]),
        sym(ChordSymbolKind.minorEleventh, const [], const Pitch(Step.a)),
        sym(ChordSymbolKind.majorSeventh, [ChordDegree.add(11, alter: 1)],
                const Pitch(Step.f, alter: 1))
            .copyWith(bass: const Pitch(Step.a, alter: 1)),
      ],
      [
        sym(ChordSymbolKind.minor, [ChordDegree.add(9)], const Pitch(Step.e)),
        sym(ChordSymbolKind.dominantThirteenth, const [],
            const Pitch(Step.b, alter: -1)),
        sym(ChordSymbolKind.power, const [], const Pitch(Step.a)),
        sym(ChordSymbolKind.dominantSeventh, [ChordDegree.alter(5, -1)]),
      ],
    ];
    for (final e in hops.entries) {
      test(e.key, () {
        for (final batch in batches) {
          final back = e.value(scored(batch)).chordSymbols;
          expect(
              [for (final c in back) c.text], [for (final c in batch) c.text],
              reason: e.key);
          expect([
            for (final c in back) [c.quality, ...c.degrees]
          ], [
            for (final c in batch) [c.quality, ...c.degrees]
          ], reason: e.key);
        }
      });
    }

    test('MusicXML writes <degree> after the bass, as the schema orders it',
        () {
      final xml = scoreToMusicXml(scored([
        sym(ChordSymbolKind.dominantSeventh, [ChordDegree.add(9, alter: -1)])
            .copyWith(bass: const Pitch(Step.e)),
      ]));
      expect(
          xml,
          contains('<kind>dominant</kind><bass><bass-step>E</bass-step></bass>'
              '<degree><degree-value>9</degree-value>'
              '<degree-alter>-1</degree-alter>'
              '<degree-type>add</degree-type></degree>'));
    });

    test('MusicXML keeps every kind and a degree the reader has not seen', () {
      final chords = [
        for (final k in ChordSymbolKind.values)
          sym(k, [const ChordDegree.alter(9, 2)]),
      ];
      for (var i = 0; i < chords.length; i += 4) {
        final batch = chords.skip(i).take(4).toList();
        final back = scoreFromMusicXml(scoreToMusicXml(scored(batch)));
        expect([
          for (final c in back.chordSymbols) [c.quality, ...c.degrees]
        ], [
          for (final c in batch) [c.quality, ...c.degrees]
        ]);
      }
    });

    test('a MuseScore name with degrees reads as one', () {
      final s = scoreFromMscx(scoreToMscx(scored(const [])).replaceFirst(
          '<Chord>',
          '<Harmony><root>15</root><name>7(b9)</name></Harmony><Chord>'));
      expect(s.chordSymbols.map((c) => c.text), ['G7(b9)']);
    });

    test('N.C. survives every format that names it', () {
      for (final hop in ['musicxml', 'mei', 'kern', 'abc', 'musescore']) {
        final back = hops[hop]!(scored([
          sym(ChordSymbolKind.major),
          sym(ChordSymbolKind.none),
        ]));
        expect(back.chordSymbols.map((c) => c.text), ['C', 'N.C.'],
            reason: hop);
      }
    });
  });

  test('a LilyPond chord track reads the full vocabulary', () {
    final s = scoreFromLilyPond(r'''
ch = \chordmode { c4:7.9- c:9^7 c:13.11 c:m13 c:7sus4 c:maj9 c:6.9 c:sus4.9 }
m = \relative c' { c4 c c c c c c c }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
    expect(s.chordSymbols.map((c) => c.text), [
      'C7(b9)',
      'Cadd9',
      'C11(add13)',
      'Cm13',
      'C7sus4',
      'Cmaj9',
      'C6/9',
      'Csus4(add9)',
    ]);
  });
}
