import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A MID-BAR clef change reached only MusicXML.
///
/// It is not a cosmetic detail: a clef placed at the barline instead of its
/// real onset re-clefs every note before it, so the notes before the change
/// read at the wrong pitch on the page.
void main() {
  List<MusicElement> ns(String p) => [
        for (var i = 0; i < 4; i++)
          NoteElement(
            id: '$p$i',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
          ),
      ];

  Score scored({List<InlineClefChange> inline = const [], Clef? change}) =>
      Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(ns('e'), inlineClefs: inline),
          Measure(ns('f'), clefChange: change),
        ],
      );

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'kern': (x) => scoreFromKern(scoreToKern(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  for (final e in hops.entries) {
    test('${e.key} keeps a mid-bar clef at its ONSET', () {
      final back = e
          .value(scored(inline: [InlineClefChange(Fraction(1, 2), Clef.bass)]));
      final ic = back.measures.first.inlineClefs;
      expect(ic, hasLength(1), reason: e.key);
      expect(ic.single.onset, Fraction(1, 2), reason: e.key);
      expect(ic.single.clef, Clef.bass, reason: e.key);
      expect(back.measures.first.clefChange, isNull,
          reason: '${e.key}: not folded to the barline');
    });

    test('${e.key} still keeps a clef change AT the barline', () {
      final back = e.value(scored(change: Clef.bass));
      expect(back.measures[1].clefChange, Clef.bass, reason: e.key);
      expect(back.measures[1].inlineClefs, isEmpty, reason: e.key);
    });

    test('${e.key} invents neither', () {
      final back = e.value(scored());
      expect(back.measures.first.inlineClefs, isEmpty, reason: e.key);
      expect(back.measures[1].clefChange, isNull, reason: e.key);
    });
  }

  test('a mid-bar clef in the FIRST measure is not the score clef', () {
    // MuseScore's `_leadingSet` stays false for the whole of measure 0, so
    // testing it before position swallowed a mid-bar clef there as the
    // score's opening clef.
    final back = scoreFromMscx(scoreToMscx(
        scored(inline: [InlineClefChange(Fraction(1, 2), Clef.bass)])));
    expect(back.clef, Clef.treble);
    expect(back.measures.first.inlineClefs, hasLength(1));
  });
}
