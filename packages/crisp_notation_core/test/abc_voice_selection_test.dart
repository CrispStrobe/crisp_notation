import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `scoreFromAbc` must return the first voice that has MUSIC.
///
/// A body field before the first `V:` — a `Q:` tempo, say — makes the reader
/// open an implicit voice to attach it to, and that voice never receives a
/// note. Taking `order.first` then returned an EMPTY score from a file full of
/// music.
///
/// Found in the 10,000-file held ABC control: 17 files read as 0 notes while
/// `staffSystemFromAbc` showed the music sitting in the voices behind the
/// empty one (90 and 82 notes in the example below).
void main() {
  // `K:` ends the header, so the `Q:` after it is a BODY field and opens the
  // implicit voice. Shape taken from a real file, not invented.
  const multiVoice = '''
X: 6
T: Azul Cielo
M: 3/4
L: 1/8
K: F
Q: 1/4=240
V:1
"C7" g3a b2| e2 f2 g2|
V:2
z6         |z6       |
''';

  int notes(Score s) =>
      s.measures.expand((m) => m.elements).whereType<NoteElement>().length;

  test('the empty implicit voice is skipped', () {
    expect(notes(scoreFromAbc(multiVoice)), greaterThan(0));
  });

  test('it returns the FIRST voice with music, not merely any', () {
    final sys = staffSystemFromAbc(multiVoice);
    final firstSounding = sys.staves
        .firstWhere((s) => notes(s) > 0, orElse: () => sys.staves.first);
    expect(notes(scoreFromAbc(multiVoice)), notes(firstSounding));
  });

  test('an ordinary single-voice tune is unaffected', () {
    const plain = '''
X:1
T:Plain
M:4/4
L:1/4
K:C
CDEF|GABc|
''';
    expect(notes(scoreFromAbc(plain)), 8);
  });

  test('a tune with no notes at all still returns a score', () {
    // The fallback must not throw or return null for a genuinely empty tune.
    const empty = '''
X:1
T:Empty
M:4/4
K:C
''';
    expect(() => scoreFromAbc(empty), returnsNormally);
  });
}
