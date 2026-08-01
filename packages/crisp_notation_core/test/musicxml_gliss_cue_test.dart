import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `<glissando>` and `<slide>` are DIFFERENT MusicXML elements — a glissando
/// steps, a slide is continuous — and the model has both concepts.
///
/// A glissando used to be written as `<slide>` and `<slide>` read back as a
/// glissando, which is self-consistent and therefore invisible to a round trip
/// of our own output. Against real files it meant every third-party
/// `<glissando>` was dropped and every real `<slide>` came back mis-modelled.
void main() {
  Score scored({
    List<Glissando> gliss = const [],
    List<Portamento> port = const [],
    List<String> cues = const [],
  }) =>
      Score(
        clef: Clef.treble,
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < 4; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ]),
        ],
        glissandos: gliss,
        portamentos: port,
        cueNoteIds: cues,
      );

  test('a glissando is written as <glissando>, not <slide>', () {
    final xml = scoreToMusicXml(scored(gliss: const [Glissando('e0', 'e1')]));
    expect(xml, contains('<glissando type="start"'));
    expect(xml, isNot(contains('<slide')));
  });

  test('a portamento is written as <slide>', () {
    final xml = scoreToMusicXml(scored(port: const [Portamento('e0', 'e1')]));
    expect(xml, contains('<slide type="start"'));
    expect(xml, isNot(contains('<glissando')));
  });

  test('each reads back as its own concept, not the other', () {
    final g = scoreFromMusicXml(
        scoreToMusicXml(scored(gliss: const [Glissando('e0', 'e1')])));
    expect(g.glissandos, hasLength(1));
    expect(g.portamentos, isEmpty);

    final p = scoreFromMusicXml(
        scoreToMusicXml(scored(port: const [Portamento('e0', 'e1')])));
    expect(p.portamentos, hasLength(1));
    expect(p.glissandos, isEmpty);
  });

  test('both at once stay apart', () {
    final back = scoreFromMusicXml(scoreToMusicXml(scored(
      gliss: const [Glissando('e0', 'e1')],
      port: const [Portamento('e2', 'e3')],
    )));
    expect(back.glissandos.single.startId, 'e0');
    expect(back.portamentos.single.startId, 'e2');
  });

  test('a third-party <glissando> is readable at all', () {
    // The reader only ever looked for <slide>, so a file written by anything
    // else lost its glissandi silently.
    final xml = scoreToMusicXml(scored(gliss: const [Glissando('e0', 'e1')]))
        .replaceAll('line-type="wavy" ', '');
    expect(scoreFromMusicXml(xml).glissandos, hasLength(1));
  });

  group('cue notes', () {
    test('survive a round trip', () {
      final back =
          scoreFromMusicXml(scoreToMusicXml(scored(cues: const ['e0'])));
      expect(back.cueNoteIds, hasLength(1));
    });

    test('only the marked note is a cue', () {
      final back =
          scoreFromMusicXml(scoreToMusicXml(scored(cues: const ['e2'])));
      final ids = back.measures.single.elements
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toList();
      expect(back.cueNoteIds.single, ids[2]);
    });

    test('a score with no cues writes no <cue/>', () {
      expect(scoreToMusicXml(scored()), isNot(contains('<cue/>')));
    });
  });
}
