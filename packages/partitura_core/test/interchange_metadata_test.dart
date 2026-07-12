import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Score-model lacuna implemented: bibliographic / part metadata (title,
/// composer, lyricist, copyright, instrument) is now a first-class `Score`
/// field, carried through the interchange headers (MusicXML `<work>`/
/// `<identification>`, MEI `<meiHead>`, MuseScore `<metaTag>`, Humdrum `!!!`
/// records, LilyPond `\header`). Empty metadata (the default) round-trips as
/// empty — no phantom instrument from a mandatory header field.
void main() {
  const meta = ScoreMetadata(
    title: 'Invention No. 1',
    composer: 'J.S. Bach',
    lyricist: 'Anon.',
    copyright: '© 2026 Public Domain',
    instrument: 'Harpsichord',
  );
  final source = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: 'c4:q d4 e4 f4',
    metadata: meta,
  );

  test('MusicXML round-trips score metadata', () {
    expect(scoreFromMusicXml(scoreToMusicXml(source)).metadata, meta);
  });

  test('MEI round-trips score metadata', () {
    expect(scoreFromMei(scoreToMei(source)).metadata, meta);
  });

  test('MuseScore round-trips score metadata', () {
    expect(scoreFromMscx(scoreToMscx(source)).metadata, meta);
  });

  test('Humdrum kern round-trips score metadata', () {
    expect(scoreFromKern(scoreToKern(source)).metadata, meta);
  });

  test('LilyPond emits a \\header and instrumentName', () {
    final ly = scoreToLilyPond(source);
    expect(ly, contains('\\header {'));
    expect(ly, contains('title = "Invention No. 1"'));
    expect(ly, contains('composer = "J.S. Bach"'));
    expect(ly, contains('instrumentName = "Harpsichord"'));
  });

  test('empty metadata round-trips as empty (no phantom instrument)', () {
    final plain = Score.simple(notes: 'c4:q d4');
    for (final back in [
      scoreFromMusicXml(scoreToMusicXml(plain)),
      scoreFromMei(scoreToMei(plain)),
      scoreFromMscx(scoreToMscx(plain)),
      scoreFromKern(scoreToKern(plain)),
    ]) {
      expect(back.metadata, const ScoreMetadata());
      expect(back.metadata.isEmpty, isTrue);
    }
  });

  test('a title-only score round-trips through every reader', () {
    final titled = Score.simple(
      notes: 'c4:q',
      metadata: const ScoreMetadata(title: 'Untitled'),
    );
    const expected = ScoreMetadata(title: 'Untitled');
    expect(scoreFromMusicXml(scoreToMusicXml(titled)).metadata, expected);
    expect(scoreFromMei(scoreToMei(titled)).metadata, expected);
    expect(scoreFromMscx(scoreToMscx(titled)).metadata, expected);
    expect(scoreFromKern(scoreToKern(titled)).metadata, expected);
  });
}
