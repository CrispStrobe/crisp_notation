import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A MuseScore 1.x fragment: harmony precedes the note it sits over, the root is
/// a tonal pitch class, and the quality is an integer chord id.
String _mscx(String harmonies) => '''
<museScore version="1.14">
  <Score>
    <Staff id="1">
      <Measure number="1">
        <nom1>4</nom1><den>4</den>
        $harmonies
        <Chord><durationType>quarter</durationType>
          <Note><pitch>60</pitch><tpc>14</tpc></Note></Chord>
        <Chord><durationType>quarter</durationType>
          <Note><pitch>62</pitch><tpc>16</tpc></Note></Chord>
      </Measure>
    </Staff>
  </Score>
</museScore>
''';

void main() {
  group('MuseScore <Harmony>', () {
    test('tonal pitch class decodes to the right spelled root', () {
      // TPC walks the line of fifths from F. Getting this wrong yields chords
      // that still LOOK like chords, which is why it is pinned explicitly.
      final cases = {
        13: ('F', 0),
        14: ('C', 0),
        15: ('G', 0),
        20: ('F', 1), // F#
        6: ('F', -1), // Fb
        12: ('B', -1), // Bb
        19: ('B', 0),
      };
      cases.forEach((tpc, want) {
        final s = scoreFromMscx(
          _mscx('<Harmony><root>$tpc</root><extension>1</extension></Harmony>'),
        );
        expect(s.chordSymbols, hasLength(1), reason: 'tpc $tpc');
        final root = s.chordSymbols.single.root;
        expect(root.step.name.toUpperCase(), want.$1, reason: 'tpc $tpc');
        expect(root.alter, want.$2, reason: 'tpc $tpc');
      });
    });

    test('extension 1 is the plain triad', () {
      final s = scoreFromMscx(
        _mscx('<Harmony><root>14</root><extension>1</extension></Harmony>'),
      );
      expect(s.chordSymbols.single.text, 'C');
    });

    test('the inferred 1.x extension mapping: 1 major, 16 minor, 64 dominant',
        () {
      // Inferred from the music itself, not documentation: over 132 corpus files
      // the melody above ext 1 plays a major third (25.4%) and never a flat
      // third in its top six; above ext 16 a flat third (23.2%) and never a
      // major third; above ext 64 a flat seventh (17.4%). Recorded here so the
      // basis travels with the mapping.
      final cases = {1: 'C', 16: 'Cm', 64: 'C7'};
      cases.forEach((ext, want) {
        final s = scoreFromMscx(
          _mscx(
              '<Harmony><root>14</root><extension>$ext</extension></Harmony>'),
        );
        expect(s.chordSymbols.single.text, want, reason: 'extension $ext');
      });
    });

    test('🔴 an UNKNOWN integer extension emits NOTHING, never a guess', () {
      // Three values were inferred from the music (see above); everything else
      // still says nothing. Mapping a value on a hunch would emit confident,
      // wrong chords, while omitting it leaves a gap a caller can see.
      for (final ext in [177, 5, 999]) {
        final s = scoreFromMscx(
          _mscx(
              '<Harmony><root>14</root><extension>$ext</extension></Harmony>'),
        );
        expect(s.chordSymbols, isEmpty, reason: 'extension $ext');
      }
    });

    test('a <name> string IS read, as newer files write', () {
      final s = scoreFromMscx(
        _mscx('<Harmony><root>14</root><name>m7</name></Harmony>'),
      );
      expect(s.chordSymbols.single.text, 'Cm7');
    });

    test('a <base> gives a slash chord', () {
      final s = scoreFromMscx(
        _mscx('<Harmony><root>14</root><extension>1</extension>'
            '<base>18</base></Harmony>'),
      );
      expect(s.chordSymbols.single.text, 'C/E');
    });

    test('several harmonies before one chord spread over the notes', () {
      final s = scoreFromMscx(
        _mscx('<Harmony><root>14</root><extension>1</extension></Harmony>'
            '<Harmony><root>15</root><extension>1</extension></Harmony>'),
      );
      expect(s.chordSymbols.map((c) => c.text).toList(), ['C', 'G']);
    });

    test('a score with no harmony has no chord symbols', () {
      expect(scoreFromMscx(_mscx('')).chordSymbols, isEmpty);
    });

    test('harmony does not add notes to the melody', () {
      final s = scoreFromMscx(
        _mscx('<Harmony><root>14</root><extension>1</extension></Harmony>'),
      );
      final notes =
          s.measures.expand((m) => m.elements).whereType<NoteElement>();
      expect(notes.length, 2);
    });
  });
}
