import 'package:crisp_notation_core/crisp_notation_core.dart';

List<String> shape(Score s) {
  final out = <String>[];
  for (final m in s.measures) {
    final sc = <int, Fraction>{};
    for (final t in m.tuplets) {
      if (t.voice != 0) continue;
      for (var i = t.startIndex; i <= t.endIndex; i++) {
        sc[i] = Fraction(t.normal, t.actual);
      }
    }
    for (var i = 0; i < m.elements.length; i++) {
      final e = m.elements[i];
      final d = e.duration.toFraction() * (sc[i] ?? Fraction(1, 1));
      out.add(e is NoteElement
          ? '${e.pitches.first.midiNumber}@$d'
          : 'r@$d');
    }
  }
  return out;
}

NoteElement n(int midi, String id, DurationBase d) => NoteElement(
    pitches: [Pitch.fromMidi(midi)], duration: NoteDuration(d), id: id);

void main() {
  // A free rest, then a triplet that OPENS on a rest, then a full triplet.
  final s = Score(clef: Clef.treble, timeSignature: const TimeSignature(4, 4), measures: [
    Measure([
      const RestElement(NoteDuration(DurationBase.eighth), id: 'r0'),
      const RestElement(NoteDuration(DurationBase.eighth), id: 'r1'),
      n(69, 'a', DurationBase.eighth),
      n(71, 'b', DurationBase.eighth),
      n(72, 'c', DurationBase.eighth),
      n(71, 'd', DurationBase.eighth),
      n(69, 'e', DurationBase.eighth),
    ], tuplets: [
      const TupletSpan(1, 3, actual: 3, normal: 2),
      const TupletSpan(4, 6, actual: 3, normal: 2),
    ]),
  ]);
  final want = shape(s);
  for (final fmt in ['musicxml', 'mei', 'kern', 'abc', 'lilypond', 'musescore']) {
    Score back;
    try {
      back = switch (fmt) {
        'musicxml' => scoreFromMusicXml(scoreToMusicXml(s)),
        'mei' => scoreFromMei(scoreToMei(s)),
        'kern' => scoreFromKern(scoreToKern(s)),
        'abc' => scoreFromAbc(scoreToAbc(s)),
        'musescore' => scoreFromMscx(scoreToMscx(s)),
        _ => scoreFromLilyPond(scoreToLilyPond(s)),
      };
    } catch (e) { print('$fmt THREW $e'); continue; }
    final g = shape(back);
    print('${fmt.padRight(10)} ${'$want' == '$g' ? "OK" : "BAD"}');
    if ('$want' != '$g') {
      print('   want $want');
      print('   got  $g');
    }
  }
}
