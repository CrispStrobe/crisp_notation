import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The writer names itself, so a file it produced can be told from a
/// third-party export — 121 stale conversions in a real library passed for
/// OpenScore's own MusicXML until this was checked by hand.
void main() {
  final score = Score(
    clef: Clef.treble,
    timeSignature: const TimeSignature(4, 4),
    measures: [
      Measure([RestElement(NoteDuration.whole, id: 'r')])
    ],
  );

  test('every document carries <software>crisp_notation</software>', () {
    final xml = scoreToMusicXml(score);
    expect(xml, contains('<software>crisp_notation</software>'));
    // Inside <identification><encoding>, where MusicXML puts it.
    final id = xml.substring(
        xml.indexOf('<identification>'), xml.indexOf('</identification>'));
    expect(id, contains('<encoding>'));
  });

  test('it sits after creator and rights, as the schema orders them', () {
    final xml = scoreToMusicXml(score.copyWith(
        metadata: const ScoreMetadata(composer: 'C', copyright: 'R')));
    expect(xml.indexOf('<creator'), lessThan(xml.indexOf('<rights>')));
    expect(xml.indexOf('<rights>'), lessThan(xml.indexOf('<encoding>')));
    final back = scoreFromMusicXml(xml);
    expect(back.metadata.composer, 'C');
    expect(back.metadata.copyright, 'R');
  });
}
