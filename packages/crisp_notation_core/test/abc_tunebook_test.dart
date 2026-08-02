import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// An ABC file is a TUNEBOOK: `X:` opens a tune and the next `X:` opens the
/// following one. Nothing stopped at the second, so every later tune's header
/// and body were read as the FIRST tune's body.
///
/// Real corpus file `id_2-17_Koenigs_Quadrille.abc` holds 13 tunes; it read
/// back with six annotations containing raw tune text and every tune's notes
/// concatenated into one.
void main() {
  const book = 'X:1\n'
      'T:First\n'
      'M:4/4\n'
      'L:1/4\n'
      'K:C\n'
      'CDEF|\n'
      '\n'
      'X:2\n'
      'T:Second\n'
      'M:4/4\n'
      'L:1/4\n'
      'K:G\n'
      'GABc|\n';

  int notes(Score s) => s.measures
      .fold(0, (a, m) => a + m.elements.whereType<NoteElement>().length);

  test('only the FIRST tune is read', () {
    final s = scoreFromAbc(book);
    expect(notes(s), 4);
    expect(s.metadata.title, 'First');
  });

  test("the second tune's key does not leak into the first", () {
    expect(scoreFromAbc(book).keySignature.fifths, 0);
  });

  test("the second tune's header is not parsed as music", () {
    // This is the damaging case: a header line carrying a LaTeX umlaut —
    // `K\"onigs`, which the German corpora are full of — reaches the body
    // parser, where `"` opens a quoted string that runs on until the next one
    // several tunes away and swallows the music in between.
    const withUmlaut = 'X:1\n'
        'T:First\n'
        'L:1/4\n'
        'K:C\n'
        'CDEF|\n'
        '\n'
        'X:2\n'
        'T:K\\"onigs Quadrille\n'
        'L:1/4\n'
        'K:C\n'
        'GABc|\n';
    final s = scoreFromAbc(withUmlaut);
    expect(notes(s), 4);
    expect(s.annotations, isEmpty,
        reason: 'no quoted string should have opened at all');
  });

  test('a single-tune file is unaffected', () {
    final s = scoreFromAbc('X:1\nT:Only\nL:1/4\nK:C\nCDEF|GABc|\n');
    expect(notes(s), 8);
    expect(s.metadata.title, 'Only');
  });

  group('the other tunes are addressable', () {
    // The fix makes the READ correct; without a way to reach tunes 2..N they
    // would simply be unreachable, and an ingest splitting a book into rows
    // needs them.
    test('abcTuneCount counts the X: headers', () {
      expect(abcTuneCount(book), 2);
      expect(abcTuneCount('X:1\nL:1/4\nK:C\nCDEF|\n'), 1);
    });

    test('a file with no X: counts as one tune, not zero', () {
      expect(abcTuneCount('L:1/4\nK:C\nCDEF|\n'), 1);
    });

    test('each tune reads with its OWN header', () {
      final second = scoreFromAbc(book, tune: 1);
      expect(second.metadata.title, 'Second');
      expect(second.keySignature.fifths, 1, reason: 'K:G');
      expect(notes(second), 4);
    });

    test('tune 0 is the default', () {
      expect(scoreFromAbc(book, tune: 0).metadata.title,
          scoreFromAbc(book).metadata.title);
    });

    test('every tune of a book is reachable and none bleeds into the next', () {
      const three = 'X:1\nT:A\nL:1/4\nK:C\nCDEF|\n'
          'X:2\nT:B\nL:1/4\nK:C\nGABc|GABc|\n'
          'X:3\nT:C\nL:1/4\nK:C\ncdef|\n';
      expect(abcTuneCount(three), 3);
      expect([
        for (var i = 0; i < 3; i++) notes(scoreFromAbc(three, tune: i)),
      ], [
        4,
        8,
        4
      ]);
      expect([
        for (var i = 0; i < 3; i++) scoreFromAbc(three, tune: i).metadata.title,
      ], [
        'A',
        'B',
        'C'
      ]);
    });
  });

  test('a file with no X: at all still reads', () {
    // Not legal ABC, but real corpora contain it and it used to work.
    expect(notes(scoreFromAbc('L:1/4\nK:C\nCDEF|\n')), 4);
  });
}
