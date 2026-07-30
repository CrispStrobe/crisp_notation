import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

const _song = r'''
akkorde = \chordmode { \germanChords f4 c:7 f4. c8 g:m7 bes:maj7 c:7/e }
melodie = \relative c' { f4 g a bes c d e f }
\score { << \new ChordNames { \akkorde } \new Staff { \melodie } >> }
''';

void main() {
  group(r'\chordmode chord tracks', () {
    test('chord symbols are read, with quality and slash bass', () {
      final s = scoreFromLilyPond(_song);
      expect(
        s.chordSymbols.map((c) => c.text).toList(),
        ['F', 'C7', 'F', 'C', 'Gm7', 'Bbmaj7', 'C7/E'],
      );
    });

    test('chord-track notes do NOT leak into the melody', () {
      // The property the block-consuming behaviour exists to protect. Losing it
      // would silently inflate note counts across every .ly file with a chord
      // track — 285 in the corpus — and would look like nothing was wrong.
      final s = scoreFromLilyPond(_song);
      final notes =
          s.measures.expand((m) => m.elements).whereType<NoteElement>();
      expect(notes.length, 8);
    });

    test('a denser chord track shifts rather than dropping chords', () {
      // Chord tracks are often denser than the melody under them. An earlier
      // version anchored one symbol per note and DISCARDED collisions, silently
      // losing 2 of these 7 including a real Gm7. A missing chord is a hole in
      // the chart; a shifted one is a small timing error.
      final s = scoreFromLilyPond(_song);
      expect(s.chordSymbols, hasLength(7));
      expect(s.chordSymbols.map((c) => c.elementId).toSet(), hasLength(7));
    });

    test('every symbol anchors to a real note element', () {
      final s = scoreFromLilyPond(_song);
      final ids = s.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toSet();
      for (final c in s.chordSymbols) {
        expect(ids, contains(c.elementId));
      }
    });

    test('a score with no chord track has no chord symbols', () {
      expect(
        scoreFromLilyPond(r"\relative c' { c4 d e f }").chordSymbols,
        isEmpty,
      );
    });

    test('an unreadable quality degrades to major rather than vanishing', () {
      // The root is what a player most needs; dropping a whole chord because its
      // extension is unfamiliar would be the worse failure.
      final s = scoreFromLilyPond(r'''
ch = \chordmode { c:13.11+ }
m = \relative c' { c4 }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols, hasLength(1));
      expect(s.chordSymbols.single.root.step, Step.c);
    });
  });
}
