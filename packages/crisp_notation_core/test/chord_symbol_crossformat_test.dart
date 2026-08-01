import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Chord symbols used to survive exactly ONE format.
///
/// Every codec here can express harmony — MusicXML `<harmony>`, MuseScore
/// `<Harmony>`, LilyPond `\chordmode`, ABC's bare `"C"`, MEI `<harm>`, kern's
/// `**mxhm` spine — but only MusicXML both read and wrote it. Three formats
/// READ chord symbols and dropped them again on write, which no round-trip
/// test could see, because the cross-format harness compared note content and
/// never looked at this channel at all.
void main() {
  Score scored(List<ChordSymbol> chords) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < 4; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ]),
        ],
        chordSymbols: chords,
      );

  final hops = <String, Score Function(Score)>{
    'musicxml': (s) => scoreFromMusicXml(scoreToMusicXml(s)),
    'mei': (s) => scoreFromMei(scoreToMei(s)),
    'kern': (s) => scoreFromKern(scoreToKern(s)),
    'abc': (s) => scoreFromAbc(scoreToAbc(s)),
    'lilypond': (s) => scoreFromLilyPond(scoreToLilyPond(s)),
    'musescore': (s) => scoreFromMscx(scoreToMscx(s)),
  };

  group('every format carries', () {
    final chords = [
      ChordSymbol('e0', const Pitch(Step.c, octave: 4), ChordSymbolKind.major),
      ChordSymbol(
          'e1', const Pitch(Step.a, octave: 4), ChordSymbolKind.minorSeventh),
      ChordSymbol('e2', const Pitch(Step.e, octave: 4, alter: -1),
          ChordSymbolKind.majorSeventh),
      ChordSymbol('e3', const Pitch(Step.g, octave: 4), ChordSymbolKind.major,
          bass: const Pitch(Step.b, octave: 3)),
    ];
    for (final e in hops.entries) {
      test('${e.key} keeps root, quality and bass', () {
        final back = e.value(scored(chords));
        expect(back.chordSymbols.map(chordName).toList(),
            ['C', 'Am7', 'Ebmaj7', 'G/B'],
            reason: e.key);
      });
    }
  });

  group('every quality survives', () {
    for (final e in hops.entries) {
      test(e.key, () {
        // Four at a time, since the fixture has four notes.
        final kinds = ChordSymbolKind.values;
        for (var i = 0; i < kinds.length; i += 4) {
          final batch = kinds.skip(i).take(4).toList();
          final chords = [
            for (var j = 0; j < batch.length; j++)
              ChordSymbol(
                  'e$j', const Pitch(Step.d, octave: 4, alter: 1), batch[j]),
          ];
          final back = e.value(scored(chords));
          expect(back.chordSymbols.map((c) => c.quality).toList(), batch,
              reason: '${e.key} batch $i');
          expect(back.chordSymbols.every((c) => c.root.step == Step.d), isTrue,
              reason: '${e.key} root batch $i');
          expect(back.chordSymbols.every((c) => c.root.alter == 1), isTrue,
              reason: '${e.key} accidental batch $i');
        }
      });
    }
  });

  test('a score with no harmony is unaffected', () {
    // The extra channels are emitted only when something uses them, so every
    // existing file stays byte-identical.
    final plain = scored(const []);
    expect(scoreToAbc(plain), isNot(contains('"')));
    expect(scoreToKern(plain), isNot(contains('**mxhm')));
    expect(scoreToLilyPond(plain), isNot(contains('ChordNames')));
    expect(scoreToMei(plain), isNot(contains('<harm')));
    expect(scoreToMscx(plain), isNot(contains('<Harmony>')));
  });
}
