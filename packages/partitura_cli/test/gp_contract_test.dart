import 'dart:io';

import 'package:partitura_cli/src/gp_container.dart';
import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Detailed **contract** snapshots of the Guitar Pro readers against the real
/// vendored binaries (alphaTab corpus, MPL-2.0 — see test/data/gp/README.md).
///
/// Unlike [gp_fixtures_test] (which locks element *counts*), these pin the
/// exact decoded musical content — string+fret → pitch, durations, chord
/// voicings, per-measure structure and time signatures — for every container
/// format. They are the behavioural safety net for a clean-room reimplementation
/// of the binary readers: the expected values state what the *format* decodes
/// to (a factual result), independent of how any particular reader is written.
void main() {
  const dir = 'test/data/gp';

  Score gp3(String n) => gp3ToScore(File('$dir/$n').readAsBytesSync());
  Score gp4(String n) => gp4ToScore(File('$dir/$n').readAsBytesSync());
  Score gp5(String n) => gp5ToScore(File('$dir/$n').readAsBytesSync());
  Score gpx(String n) =>
      scoreFromGpif(readGpifFromGpx(File('$dir/$n').readAsBytesSync()));
  Score gp(String n) =>
      scoreFromGpif(readGpifFromGp(File('$dir/$n').readAsBytesSync()));

  // A stable, human-readable transcription of a score's musical content.
  String snapshot(Score s) {
    String pitch(Pitch p) => '${p.step.name}${p.alter}/${p.octave}';
    final b = StringBuffer();
    b.writeln('time=${s.timeSignature} measures=${s.measures.length}');
    for (var mi = 0; mi < s.measures.length; mi++) {
      final m = s.measures[mi];
      final parts = <String>[];
      for (final e in m.elements) {
        if (e is NoteElement) {
          final dur = '${e.duration.base.name}${'.' * e.duration.dots}';
          parts.add('${e.pitches.map(pitch).join('+')}:$dur');
        } else if (e is RestElement) {
          parts.add('r:${e.duration.base.name}');
        }
      }
      b.writeln('m$mi: ${parts.join('  ')}');
    }
    return b.toString().trim();
  }

  group('note durations & tuning (string+fret → pitch)', () {
    // A one-bar exercise: for each of whole..64th, four fretted notes then a
    // rest. The pitches encode the standard tuning; .gp3 and .gp4 agree.
    const notes = 'time=4/4 measures=1\n'
        'm0: f0/2:whole  f1/2:whole  g0/2:whole  g1/2:whole  r:whole  '
        'f0/2:half  f1/2:half  g0/2:half  g1/2:half  r:half  '
        'f0/2:quarter  f1/2:quarter  g0/2:quarter  g1/2:quarter  r:quarter  '
        'f0/2:eighth  f1/2:eighth  g0/2:eighth  g1/2:eighth  r:eighth  '
        'f0/2:sixteenth  f1/2:sixteenth  g0/2:sixteenth  g1/2:sixteenth  r:sixteenth  '
        'f0/2:thirtySecond  f1/2:thirtySecond  g0/2:thirtySecond  g1/2:thirtySecond  r:thirtySecond  '
        'f0/2:sixtyFourth  f1/2:sixtyFourth  g0/2:sixtyFourth  g1/2:sixtyFourth  r:sixtyFourth';

    test('.gp3', () => expect(snapshot(gp3('notes.gp3')), notes));
    test('.gp4', () => expect(snapshot(gp4('notes.gp4')), notes));
  });

  group('chord voicings across formats', () {
    // .gp5 and .gp (v7) carry the same two-bar chord progression.
    const chords5 = 'time=4/4 measures=2\n'
        'm0: c0/3+e0/3+g0/3+c0/4+e0/4:quarter  c0/3+d1/3+g0/3:quarter  '
        'c0/3+g0/3+c0/4+e0/4+g0/4:quarter  c0/3+g0/3+c0/4+d1/4+g0/4:quarter\n'
        'm1: d0/3+a0/3+d0/4+f1/4:quarter  d0/3+a0/3+d0/4+f0/4:quarter  '
        'd0/3+a0/3+d0/4+f1/4+a0/4:quarter  d0/3+a0/3+d0/4+f0/4+a0/4:quarter';

    test('.gp5', () => expect(snapshot(gp5('chords.gp5')), chords5));

    test('.gp (v7)', () {
      final s = gp('chords.gp');
      // Same first two bars; the .gp file pads out to five measures.
      expect(s.measures, hasLength(5));
      expect(s.timeSignature, TimeSignature.fourFour);
      String bar(int i) =>
          snapshot(Score(clef: s.clef, measures: [s.measures[i]]))
              .split('\n')
              .last;
      expect(
          bar(0),
          'm0: c0/3+e0/3+g0/3+c0/4+e0/4:quarter  c0/3+d1/3+g0/3:quarter  '
          'c0/3+g0/3+c0/4+e0/4+g0/4:quarter  c0/3+g0/3+c0/4+d1/4+g0/4:quarter');
    });

    test('.gpx (v6)', () {
      final s = gpx('chords.gpx');
      expect(s.measures, hasLength(5));
      expect(s.timeSignature, TimeSignature.fourFour);
      // Its first bar opens on a low-E-string voicing.
      final firstNote = s.measures[0].elements.first as NoteElement;
      expect(firstNote.pitches.first, const Pitch(Step.e, octave: 2));
      expect(firstNote.pitches, hasLength(5));
    });
  });

  test('bends: two half-note bends then a whole note (.gp5)', () {
    expect(snapshot(gp5('bends.gp5')),
        'time=4/4 measures=2\nm0: a1/3:half  a1/3:half\nm1: f0/4:whole');
    expect(gp5('bends.gp5').bends, hasLength(3));
  });
}
