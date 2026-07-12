import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Enrichment parity: articulations (staccato/tenuto/accent/marcato/fermata)
/// now survive the MEI, MuseScore and kern round-trips, and LilyPond emits the
/// corresponding scripts — bringing these codecs level with MusicXML for the
/// articulation set the `Score` model carries.
void main() {
  final source = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: "c4:q' d4> e4^ f4_ | g4:q@ a4>' b4 c5",
  );

  test('MusicXML round-trips articulations (reference)', () {
    expect(scoreFromMusicXml(scoreToMusicXml(source)), source);
  });

  test('MEI round-trips articulations', () {
    expect(scoreFromMei(scoreToMei(source)), source);
  });

  test('MuseScore round-trips articulations', () {
    expect(scoreFromMscx(scoreToMscx(source)), source);
  });

  test('Humdrum kern round-trips articulations', () {
    expect(scoreFromKern(scoreToKern(source)), source);
  });

  test('LilyPond emits the articulation scripts', () {
    final ly = scoreToLilyPond(source);
    expect(ly, contains('-.')); // staccato
    expect(ly, contains('--')); // tenuto
    expect(ly, contains('->')); // accent
    expect(ly, contains('-^')); // marcato
    expect(ly, contains('\\fermata'));
  });

  test('chords carry element-level articulations too', () {
    final chord = Score.simple(notes: 'c4+e4+g4:q> r:q');
    expect(scoreFromMei(scoreToMei(chord)), chord);
    expect(scoreFromMscx(scoreToMscx(chord)), chord);
    expect(scoreFromKern(scoreToKern(chord)), chord);
  });
}
