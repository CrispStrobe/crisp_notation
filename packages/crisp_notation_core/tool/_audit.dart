import 'dart:io';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Which score-level channels survive which codec.
///
/// The chord-symbol gap was invisible because the cross-format signature never
/// looked at that channel. `Score` has 44 of them and the signature checks 6,
/// so the same blindness could hide any of the rest.
void main() {
  List<MusicElement> notes() => [
        for (var i = 0; i < 4; i++)
          NoteElement(
              id: 'e$i',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter)),
      ];

  final cases = <String, (Score, int Function(Score))>{
    'ottavas': (
      Score(
          clef: Clef.treble,
          measures: [Measure(notes())],
          ottavas: const [Ottava('e0', 'e2')]),
      (s) => s.ottavas.length
    ),
    'pedals': (
      Score(
          clef: Clef.treble,
          measures: [Measure(notes())],
          pedals: const [Pedal('e0', 'e2')]),
      (s) => s.pedals.length
    ),
    'trillExtensions': (
      Score(
          clef: Clef.treble,
          measures: [Measure(notes())],
          trillExtensions: const [TrillExtension('e0', 'e2')]),
      (s) => s.trillExtensions.length
    ),
    'glissandos': (
      Score(
          clef: Clef.treble,
          measures: [Measure(notes())],
          glissandos: const [Glissando('e0', 'e1')]),
      (s) => s.glissandos.length
    ),
    'portamentos': (
      Score(
          clef: Clef.treble,
          measures: [Measure(notes())],
          portamentos: const [Portamento('e0', 'e1')]),
      (s) => s.portamentos.length
    ),
    'laissezVibrer': (
      Score(
          clef: Clef.treble,
          measures: [Measure(notes())],
          laissezVibrer: const [LaissezVibrer('e0')]),
      (s) => s.laissezVibrer.length
    ),
    'figuredBass': (
      Score(
          clef: Clef.bass,
          measures: [Measure(notes())],
          figuredBass: const [FiguredBass('e0', ['6', '4'])]),
      (s) => s.figuredBass.length
    ),
    'cueNoteIds': (
      Score(
          clef: Clef.treble,
          measures: [Measure(notes())],
          cueNoteIds: const ['e0']),
      (s) => s.cueNoteIds.length
    ),
    'tempo': (
      Score(clef: Clef.treble, measures: [Measure(notes())], tempo: Tempo(96)),
      (s) => s.tempo == null ? 0 : 1
    ),
  };

  final hops = <String, Score Function(Score)>{
    'musicxml': (s) => scoreFromMusicXml(scoreToMusicXml(s)),
    'mei': (s) => scoreFromMei(scoreToMei(s)),
    'kern': (s) => scoreFromKern(scoreToKern(s)),
    'abc': (s) => scoreFromAbc(scoreToAbc(s)),
    'lilypond': (s) => scoreFromLilyPond(scoreToLilyPond(s)),
    'musescore': (s) => scoreFromMscx(scoreToMscx(s)),
  };

  final w = cases.keys.map((k) => k.length).reduce((a, b) => a > b ? a : b);
  stdout.write(''.padRight(w + 2));
  for (final f in hops.keys) stdout.write((f.length > 4 ? f.substring(0, 4) : f).padRight(6));
  print('');
  for (final c in cases.entries) {
    stdout.write(c.key.padRight(w + 2));
    for (final h in hops.entries) {
      var mark = ' ok  ';
      try {
        if (c.value.$2(h.value(c.value.$1)) == 0) mark = ' --  ';
      } catch (_) {
        mark = 'THRW ';
      }
      stdout.write(mark.padRight(6));
    }
    print('');
  }
}
