import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Portamento and cue notes reached only MusicXML.
///
/// Both were DEAD channels until this arc: `<slide>` was being used for
/// glissandi (so `Score.portamentos` was never produced) and `<cue/>` was
/// neither written nor read.
///
/// ⚠️ LilyPond is absent on purpose. It spells both a glissando and a
/// portamento `\glissando`, and has no per-note cue flag — `\cueDuring` quotes
/// another VOICE, which is a different thing. Omitted rather than approximated.
void main() {
  Score scored({
    List<Glissando> gliss = const [],
    List<Portamento> port = const [],
    List<String> cues = const [],
  }) =>
      Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < 4; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ])
        ],
        glissandos: gliss,
        portamentos: port,
        cueNoteIds: cues,
      );

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  for (final e in hops.entries) {
    test('${e.key} carries a portamento', () {
      final back = e.value(scored(port: const [Portamento('e0', 'e1')]));
      expect(back.portamentos, hasLength(1), reason: e.key);
      expect(back.glissandos, isEmpty, reason: '${e.key}: not a glissando');
    });

    test('${e.key} keeps a glissando and a portamento APART', () {
      // MEI spells both `<gliss>` (split by `@lform`) and MuseScore both as a
      // Glissando spanner (split by `<subtype>`), so one concept collapsing
      // into the other is the obvious failure.
      final back = e.value(scored(
        gliss: const [Glissando('e0', 'e1')],
        port: const [Portamento('e2', 'e3')],
      ));
      expect(back.glissandos, hasLength(1), reason: e.key);
      expect(back.portamentos, hasLength(1), reason: e.key);
    });

    test('${e.key} carries a cue note', () {
      final back = e.value(scored(cues: const ['e0']));
      expect(back.cueNoteIds, hasLength(1), reason: e.key);
      final ids = back.measures.single.elements
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toList();
      expect(back.cueNoteIds.single, ids.first, reason: e.key);
    });

    test('${e.key} invents neither', () {
      final back = e.value(scored());
      expect(back.portamentos, isEmpty, reason: e.key);
      expect(back.cueNoteIds, isEmpty, reason: e.key);
    });
  }
}
