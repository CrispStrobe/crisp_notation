import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Cross-format transparency: because every codec funnels through the one
/// `Score` model, converting A -> B -> A (or a longer chain) preserves the
/// data both formats share — here pitches and rhythm for a fretted-guitar
/// melody. Anything a format cannot represent is lost at that hop; this
/// exercises the common subset.
List<String> pitches(Score s) => s.measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .expand((n) => n.pitches)
    .map((p) => p.toString())
    .toList();

List<NoteDuration> durations(Score s) => s.measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .map((n) => n.duration)
    .toList();

void main() {
  // Guitar-range so it frets on standard tuning; whole-tone durations so the
  // sixteenth-grid MIDI quantizer is exact.
  final source = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: 'e3:q g3 b3 e4 | c4:q e4 g4 c5',
  );

  test('MusicXML round-trip is exact (it is the reference format)', () {
    final back = scoreFromMusicXml(scoreToMusicXml(source));
    expect(pitches(back), pitches(source));
    expect(durations(back), durations(source));
  });

  test('GPIF (.gp) round-trip preserves pitches and rhythm', () {
    final back = scoreFromGpif(scoreToGpif(source));
    expect(pitches(back), pitches(source));
    expect(durations(back), durations(source));
  });

  test('MuseScore (.mscx) round-trip preserves pitches and rhythm', () {
    final back = scoreFromMscx(scoreToMscx(source));
    expect(pitches(back), pitches(source));
    expect(durations(back), durations(source));
  });

  test('MIDI round-trip preserves pitches and (quantized) rhythm', () {
    final back = scoreFromMidi(scoreToMidi(source));
    expect(pitches(back), pitches(source));
    expect(durations(back), durations(source));
  });

  test('a chain across every format keeps the shared data (± the same)', () {
    // MusicXML -> Score -> GPIF -> Score -> MIDI -> Score.
    final viaXml = scoreFromMusicXml(scoreToMusicXml(source));
    final viaGp = scoreFromGpif(scoreToGpif(viaXml));
    final viaMidi = scoreFromMidi(scoreToMidi(viaGp));
    expect(pitches(viaMidi), pitches(source));
    expect(durations(viaMidi), durations(source));
  });

  test('.gp <-> MIDI is transparent in both directions', () {
    final gpThenMidi =
        scoreFromMidi(scoreToMidi(scoreFromGpif(scoreToGpif(source))));
    final midiThenGp =
        scoreFromGpif(scoreToGpif(scoreFromMidi(scoreToMidi(source))));
    expect(pitches(gpThenMidi), pitches(midiThenGp));
    expect(pitches(gpThenMidi), pitches(source));
  });
}
