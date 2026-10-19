import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A chord symbol's own time, length and voicing octave.
///
/// A chord track keeps its own rhythm. Bound to a note id with nothing else,
/// a chord between two melody notes had to move onto one of them, a rest in
/// the track sounded as the previous chord held on, and a track written low
/// (`c,`) played from middle C. [ChordSymbol.offset], [ChordSymbol.duration]
/// and [ChordSymbol.voicingOctave] carry what the track states.
void main() {
  const c4 = Pitch(Step.c, octave: 4);
  const g4 = Pitch(Step.g, octave: 4);
  const f4 = Pitch(Step.f, octave: 4);

  /// One bar of two half notes, h0 and h1.
  Score halves(List<ChordSymbol> chords) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < 2; i++)
              NoteElement(
                id: 'h$i',
                pitches: const [c4],
                duration: const NoteDuration(DurationBase.half),
              ),
          ]),
        ],
        chordSymbols: chords,
      );

  List<PlaybackNote> chordsOf(Score s) => [
        for (final n in playbackTimeline(s, voiceChordSymbols: true))
          if (n.chordPitches != null) n,
      ];

  group('model', () {
    test('defaults keep a symbol what it always was', () {
      const c = ChordSymbol('h0', c4, ChordSymbolKind.major);
      expect(c.offset, Fraction.zero);
      expect(c.duration, isNull);
      expect(c.voicingOctave, isNull);
      expect(c, const ChordSymbol('h0', Pitch(Step.c), ChordSymbolKind.major));
    });

    test('equality and hashing see offset, duration and voicing octave', () {
      const base = ChordSymbol('h0', c4, ChordSymbolKind.major);
      final variants = [
        base.copyWith(offset: Fraction(1, 4)),
        base.copyWith(duration: Fraction(1, 4)),
        base.copyWith(voicingOctave: 3),
      ];
      for (final v in variants) {
        expect(v, isNot(base));
        expect(
            v,
            base.copyWith(
                offset: v.offset,
                duration: v.duration,
                voicingOctave: v.voicingOctave));
        expect(
            v.hashCode,
            base
                .copyWith(
                    offset: v.offset,
                    duration: v.duration,
                    voicingOctave: v.voicingOctave)
                .hashCode);
      }
      expect(
          variants[1].copyWith(clearDuration: true, clearVoicingOctave: true),
          base);
    });

    test('transposing moves a stated voicing octave with its root', () {
      final s = halves([
        const ChordSymbol('h0', Pitch(Step.b, octave: 3), ChordSymbolKind.major,
            voicingOctave: 3),
        const ChordSymbol('h1', g4, ChordSymbolKind.major),
      ]).transposedBy(const Interval(IntervalQuality.major, 2));
      // B3 up a major second is C#4: into the next octave.
      expect(s.chordSymbols[0].text, 'C#');
      expect(s.chordSymbols[0].voicingOctave, 4);
      expect(s.chordSymbols[1].voicingOctave, isNull);
    });
  });

  group('playback', () {
    test('an offset sounds the chord at its own time', () {
      final s = halves([
        const ChordSymbol('h0', c4, ChordSymbolKind.major),
        ChordSymbol('h0', g4, ChordSymbolKind.major, offset: Fraction(1, 4)),
        const ChordSymbol('h1', f4, ChordSymbolKind.major),
      ]);
      final chords = chordsOf(s);
      expect([for (final n in chords) n.start],
          [Fraction.zero, Fraction(1, 4), Fraction(1, 2)]);
      expect([for (final n in chords) n.duration],
          [Fraction(1, 4), Fraction(1, 4), Fraction(1, 2)]);
      expect(chords[1].chordPitches!.first.midiNumber, 67);
    });

    test('a duration ends the chord before the next one', () {
      final s = halves([
        ChordSymbol('h0', c4, ChordSymbolKind.major, duration: Fraction(1, 4)),
        ChordSymbol('h1', f4, ChordSymbolKind.major, duration: Fraction(1, 8)),
      ]);
      final chords = chordsOf(s);
      expect([for (final n in chords) n.duration],
          [Fraction(1, 4), Fraction(1, 8)]);
    });

    test('a duration never runs past the next chord', () {
      final s = halves([
        ChordSymbol('h0', c4, ChordSymbolKind.major, duration: Fraction(1, 1)),
        const ChordSymbol('h1', f4, ChordSymbolKind.major),
      ]);
      expect(chordsOf(s).first.duration, Fraction(1, 2));
    });

    test('a voicing octave voices the root there', () {
      final s = halves([
        const ChordSymbol('h0', c4, ChordSymbolKind.major, voicingOctave: 3),
        const ChordSymbol('h1', Pitch(Step.b, alter: -1), ChordSymbolKind.major,
            voicingOctave: 3),
      ]);
      final chords = chordsOf(s);
      expect([for (final p in chords[0].chordPitches!) p.midiNumber],
          [48, 52, 55]);
      expect([for (final p in chords[1].chordPitches!) p.midiNumber],
          [58, 62, 65]);
    });

    test('without one, a root still sounds from middle C up', () {
      final s = halves([
        const ChordSymbol('h0', Pitch(Step.b, octave: 1), ChordSymbolKind.major)
      ]);
      expect([for (final p in chordsOf(s).single.chordPitches!) p.midiNumber],
          [71, 75, 78]);
    });
  });

  group('slash bass', () {
    test('a bass that is a chord tone inverts the chord', () {
      // LilyPond plays `g/b` as B under G and D: the B moves down rather than
      // sounding twice.
      final s = halves([
        const ChordSymbol('h0', g4, ChordSymbolKind.major,
            bass: Pitch(Step.b, octave: 3)),
      ]);
      expect([for (final p in chordsOf(s).single.chordPitches!) p.midiNumber],
          [59, 67, 74]);
    });

    test('an added bass sounds under the whole chord', () {
      final s = halves([
        const ChordSymbol('h0', g4, ChordSymbolKind.major,
            bass: Pitch(Step.b, octave: 3), addedBass: true),
      ]);
      expect([for (final p in chordsOf(s).single.chordPitches!) p.midiNumber],
          [59, 67, 71, 74]);
    });

    test('a bass outside the chord is added either way', () {
      final s = halves([
        const ChordSymbol('h0', c4, ChordSymbolKind.major,
            bass: Pitch(Step.b, alter: -1, octave: 3)),
      ]);
      expect([for (final p in chordsOf(s).single.chordPitches!) p.midiNumber],
          [58, 60, 64, 67]);
    });

    test('addedBass takes part in equality', () {
      const a = ChordSymbol('h0', g4, ChordSymbolKind.major,
          bass: Pitch(Step.b, octave: 3));
      expect(a.copyWith(addedBass: true), isNot(a));
      expect(a.copyWith(addedBass: true).copyWith(addedBass: false), a);
    });

    test(r'LilyPond reads /+ as an added bass and / as an inversion', () {
      final s = scoreFromLilyPond(r'''
ch = \chordmode { g2/b g2/+b }
m = \relative c'' { g2 g }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols.map((c) => c.addedBass), [false, true]);
      final back = scoreFromLilyPond(scoreToLilyPond(s));
      expect(back.chordSymbols, s.chordSymbols);
    });
  });

  group('LilyPond chord track', () {
    test('a rest in the track gives the chord before it a duration', () {
      final s = scoreFromLilyPond(r'''
ch = \chordmode { c2 r4 g4 }
m = \relative c' { c4 d e f }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols[0].duration, Fraction(1, 2));
      // The last chord reaches the end of the music: no duration needed.
      expect(s.chordSymbols[1].duration, isNull);
      final chords = chordsOf(s);
      expect([
        for (final n in chords) (n.start, n.duration)
      ], [
        (Fraction.zero, Fraction(1, 2)),
        (Fraction(3, 4), Fraction(1, 4)),
      ]);
    });

    test('a contiguous track states no durations', () {
      final s = scoreFromLilyPond(r'''
ch = \chordmode { c2 g2 }
m = \relative c' { c4 d e f }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols.map((c) => c.duration), [null, null]);
    });

    test('the written octave is the voicing octave', () {
      final s = scoreFromLilyPond(r'''
ch = \chordmode { c,4 c4 c'4 b4 }
m = \relative c' { c4 d e f }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      // A bare root is the default voicing (from middle C up): no octave.
      expect(s.chordSymbols.map((c) => c.voicingOctave), [3, null, 5, null]);
      expect([for (final n in chordsOf(s)) n.chordPitches!.first.midiNumber],
          [48, 60, 72, 71]);
    });

    test(r'a \transpose down moves the voicing below middle C', () {
      final s = scoreFromLilyPond(r'''
ch = \transpose c' bes \chordmode { c1 }
m = \transpose c' bes \relative c' { c1 }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols.single.text, 'Bb');
      expect(s.chordSymbols.single.voicingOctave, 3);
      expect(chordsOf(s).single.chordPitches!.first.midiNumber, 58);
    });

    test('a duration multiplier is exact and does not carry on', () {
      final s = scoreFromLilyPond(r'''
ch = \chordmode { c1*3/8 g8 f2 }
m = \relative c' { c2 e2 }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols.map((c) => c.text), ['C', 'G', 'F']);
      expect(s.chordSymbols[1].elementId, s.chordSymbols[0].elementId);
      expect(s.chordSymbols[1].offset, Fraction(3, 8));
      expect(s.chordSymbols[2].offset, Fraction.zero);
    });

    test('a chord over a rest stands over the note before it', () {
      final s = scoreFromLilyPond(r'''
ch = \chordmode { c2 g2 }
m = \relative c' { c4 r4 r2 }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols.map((c) => c.elementId).toSet(), hasLength(1));
      expect(s.chordSymbols[1].offset, Fraction(1, 2));
    });
  });

  group('round trips', () {
    final timed = [
      const ChordSymbol('h0', c4, ChordSymbolKind.major),
      ChordSymbol('h0', g4, ChordSymbolKind.dominantSeventh,
          offset: Fraction(1, 4)),
      ChordSymbol('h1', f4, ChordSymbolKind.major,
          bass: const Pitch(Step.a, octave: 3), offset: Fraction(1, 8)),
    ];

    /// Each symbol's absolute onset and text.
    List<(Fraction, String)> placed(Score s) {
      final onset = <String, Fraction>{};
      var t = Fraction.zero;
      for (final e in s.measures.expand((m) => m.elements)) {
        if (e.id != null) onset[e.id!] = t;
        t += e.duration.toFraction();
      }
      return [
        for (final c in s.chordSymbols)
          (onset[c.elementId]! + c.offset, c.text),
      ];
    }

    final want = [
      (Fraction.zero, 'C'),
      (Fraction(1, 4), 'G7'),
      (Fraction(5, 8), 'F/A'),
    ];

    test('MusicXML keeps offsets as <offset>', () {
      final xml = scoreToMusicXml(halves(timed));
      expect(xml, contains('<offset sound="yes">'));
      expect(placed(scoreFromMusicXml(xml)), want);
    });

    test('MuseScore keeps offsets with <location>', () {
      final mscx = scoreToMscx(halves(timed));
      expect(mscx, contains('<location><fractions>1/4</fractions>'));
      expect(placed(scoreFromMscx(mscx)), want);
    });

    test('LilyPond keeps offsets, durations and voicing octaves', () {
      final s = halves([
        ChordSymbol('h0', c4, ChordSymbolKind.major,
            duration: Fraction(1, 8), voicingOctave: 3),
        ChordSymbol('h0', g4, ChordSymbolKind.dominantSeventh,
            offset: Fraction(1, 4)),
        ChordSymbol('h1', f4, ChordSymbolKind.major,
            bass: const Pitch(Step.a, octave: 3), offset: Fraction(1, 8)),
      ]);
      final ly = scoreToLilyPond(s);
      expect(ly, contains('c,8 s8'));
      final back = scoreFromLilyPond(ly);
      expect(placed(back), want);
      expect(back.chordSymbols.map((c) => c.duration),
          [Fraction(1, 8), null, null]);
      expect(back.chordSymbols.map((c) => c.voicingOctave), [3, null, null]);
    });

    test('LilyPond writes a bare root for the default voicing', () {
      // A root pitch's own octave is not a voicing: written as `c''`, LilyPond
      // played it two octaves above the model's chord.
      final ly = scoreToLilyPond(halves([
        const ChordSymbol(
            'h0', Pitch(Step.c, octave: 5), ChordSymbolKind.major),
      ]));
      expect(ly, contains(r'\chordmode {' '\n    c1'));
    });
  });

  group('layout', () {
    late LayoutSettings settings;
    setUpAll(() {
      final source =
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync();
      settings = LayoutSettings(
          metadata: SmuflMetadata.fromJson(
              jsonDecode(source) as Map<String, Object?>));
    });

    double xOf(ScoreLayout layout, String text) => layout.primitives
        .whereType<TextPrimitive>()
        .firstWhere((p) => p.text == text)
        .position
        .x;

    test('a chord with an offset is drawn at its time between the notes', () {
      final layout = const LayoutEngine().layout(
          halves([
            const ChordSymbol('h0', c4, ChordSymbolKind.major),
            ChordSymbol('h0', g4, ChordSymbolKind.major,
                offset: Fraction(1, 4)),
            const ChordSymbol('h1', f4, ChordSymbolKind.major),
          ]),
          settings);
      final c = xOf(layout, 'C'), g = xOf(layout, 'G'), f = xOf(layout, 'F');
      expect(g, greaterThan(c));
      expect(g, lessThan(f));
    });
  });
}
