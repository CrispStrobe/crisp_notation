import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A MID-BAR clef change reached only MusicXML.
///
/// It is not a cosmetic detail: a clef placed at the barline instead of its
/// real onset re-clefs every note before it, so the notes before the change
/// read at the wrong pitch on the page.
/// ⚠️ LilyPond is absent, and the attempt is recorded so it is not repeated
/// blind. Its WRITER emits both `clefChange` and `inlineClefs` correctly; its
/// READER still records neither, because `scoreFromLilyPond` walks nodes across
/// STAFF boundaries — a multi-staff file's other staves' `\clef` commands reach
/// the same measure builder. Recording them produced 510 clef changes and 277
/// mid-bar ones across 250 choral files that have one clef each, and cost 477
/// corpus round trips. Doing it properly needs the clefs scoped to the staff
/// being read.
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
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
    // MEI writes measure-level changes as a layer PREFIX, so a mid-bar one
    // needs its own pass INSIDE the element loop; the reader tells them apart
    // by whether any element has been read yet.
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    // LilyPond reads clefs only from the FIRST staff leaf — `scoreFromLilyPond`
    // walks the whole file, so a SATB score's four `\clef` commands would
    // otherwise all land in this one measure stream.
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
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
      // ⚠️ The score clef must stay the OPENING one. A reader that tracks a
      // running clef reports whatever the last change set unless it captures
      // the initial value — `_initialTime` already existed in the LilyPond
      // reader for exactly this reason; clef and key were its missing siblings.
      expect(back.clef, Clef.treble, reason: '${e.key}: opening clef intact');
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

  // ⚠️ THE REGRESSION THAT CAUSED THE FIRST REVERT. `scoreFromLilyPond` walks
  // the WHOLE file, so every staff's `\clef` reached the same measure builder:
  // a SATB score read as four clef changes and took its score clef from the
  // BASS staff. 510 phantom changes across 250 one-clef choral files, and 477
  // corpus round trips.
  test('lilypond reads clefs from the FIRST staff only', () {
    final back = scoreFromLilyPond(r'''
      \score { <<
        \new Staff { \clef treble c'4 d'4 e'4 f'4 }
        \new Staff { \clef bass c4 d4 e4 f4 }
      >> }
    ''');
    expect(back.clef, Clef.treble, reason: 'not the LAST staff\'s clef');
    for (final m in back.measures) {
      expect(m.clefChange, isNull, reason: 'no phantom change per staff');
      expect(m.inlineClefs, isEmpty);
    }
  });

  // ⚠️ A clef at the bar's END onset sits PAST the last element, so a loop
  // that only emits clefs BEFORE each element never reaches it. That is
  // precisely where kern puts a `*clef` change announced at the end of a
  // measure — and it read back at that onset, so the model was right and every
  // writer was dropping it. 22 of 37 clef changes in one corpus piano score,
  // identically in all four capable formats.
  //
  // The writers now also flush on REACHED-OR-PASSED rather than an exact
  // match, since an onset is a position in the BAR and need not land on a
  // boundary in the voice being written.
  test('a clef at the END of a bar survives', () {
    final source = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(2, 4),
      measures: [
        Measure(ns('e'),
            inlineClefs: [InlineClefChange(Fraction(1, 2), Clef.bass)]),
        Measure(ns('f')),
      ],
    );
    for (final e in hops.entries) {
      final back = e.value(source);
      final ic = back.measures.first.inlineClefs;
      expect(ic, hasLength(1), reason: e.key);
      expect(ic.single.onset, Fraction(1, 2), reason: e.key);
      expect(ic.single.clef, Clef.bass, reason: e.key);
    }
  });

  // ⚠️ kern has TWO writer paths and only the single-voice one emitted inline
  // clefs — so every piano score, which is always multi-voice, lost all of
  // them. A mid-bar clef is an INTERPRETATION record and a Humdrum
  // interpretation must span every spine, so it is its own row with one
  // `*clef…` per sub-spine, never a token inside a data row.
  test('kern keeps a mid-bar clef in a MULTI-VOICE measure', () {
    final source = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(
          ns('e'),
          voice2: ns('g'),
          inlineClefs: [InlineClefChange(Fraction(1, 2), Clef.bass)],
        ),
        Measure(ns('f'), voice2: ns('h')),
      ],
    );
    final kern = scoreToKern(source);
    expect(kern, contains('*clef'));
    final back = scoreFromKern(kern);
    final ic = back.measures.first.inlineClefs;
    expect(ic, hasLength(1));
    expect(ic.single.onset, Fraction(1, 2));
    expect(ic.single.clef, Clef.bass);
    // The inner voice must survive alongside it.
    expect(back.measures.first.voice2, hasLength(4));
  });
}
