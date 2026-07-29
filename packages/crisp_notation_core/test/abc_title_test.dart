// ABC `T:` (title) and `C:` (composer) headers.
//
// They were parsed as unknown fields and dropped, so every ABC tune imported
// NAMELESS — a library listing showed a blank row. Caught by importing the
// Pete Mac tunebook, where "Marjorie's Milestone" came back with title == null.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

const _tune = '''
X:1
T:Marjorie's Milestone
C:Pete Mac 2000
M:4/4
L:1/8
K:G
G2 A2 B2 c2 | d4 z4 |]
''';

void main() {
  group('ABC info fields', () {
    test('T: becomes the score title', () {
      expect(scoreFromAbc(_tune).metadata.title, "Marjorie's Milestone");
    });

    test('C: becomes the composer', () {
      expect(scoreFromAbc(_tune).metadata.composer, 'Pete Mac 2000');
    });

    test('the first T: wins — later ones are subtitles', () {
      // ABC allows several T: lines; the first is the title.
      const multi =
          'X:1\nT:Main Title\nT:A Subtitle\nM:4/4\nL:1/8\nK:C\nc4 z4 |]\n';
      expect(scoreFromAbc(multi).metadata.title, 'Main Title');
    });

    test('a tune without T:/C: still reads, with null metadata', () {
      const bare = 'X:1\nM:4/4\nL:1/8\nK:C\nc4 z4 |]\n';
      final s = scoreFromAbc(bare);
      expect(s.metadata.title, isNull);
      expect(s.metadata.composer, isNull);
      expect(s.measures, isNotEmpty);
    });

    test('the title reaches the multi-part reader too', () {
      expect(multiPartScoreFromAbc(_tune).parts.first.metadata.title,
          "Marjorie's Milestone");
    });

    test('only the FIRST voice carries the tune-level title', () {
      // Repeating it per staff would print the title on every part.
      const twoVoices = 'X:1\nT:Duet\nM:4/4\nL:1/8\nV:1\nV:2\nK:C\n'
          '[V:1] c4 z4 |]\n[V:2] G4 z4 |]\n';
      final mp = multiPartScoreFromAbc(twoVoices);
      expect(mp.parts.first.metadata.title, 'Duet');
      if (mp.parts.length > 1) {
        expect(mp.parts[1].metadata.title, isNull);
      }
    });
  });
}
