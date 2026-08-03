import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A hairpin that starts AND ends on the same note.
///
/// ⚠️ Close-before-open is the right rule for two DIFFERENT spans meeting on a
/// note, and it is exactly backwards for ONE span on one note: LilyPond wrote
/// `\!\>`, which closes nothing and then leaves a hairpin open forever, so the
/// span was dropped — and the reader independently rejected a same-note pair.
/// The ordering is what tells the two cases apart: in the ordinary chain the
/// `\!` belongs to a span that opened on an EARLIER note.
///
/// It is not a hypothetical: MusicXML, MEI and MuseScore all carry one, and a
/// real corpus file (`13078-Viola-xml.xml`) has one.
void main() {
  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  Score scored(List<Hairpin> hairpins) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure([
            for (var i = 0; i < 4; i++)
              NoteElement(
                id: 'a$i',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ])
        ],
        hairpins: hairpins,
      );

  for (final e in hops.entries) {
    test('${e.key} keeps a hairpin that starts and ends on one note', () {
      final back = e
          .value(scored(const [
            Hairpin('a1', 'a1', HairpinType.diminuendo),
          ]))
          .hairpins;
      expect(back, hasLength(1), reason: e.key);
      expect(back.single.startId, back.single.endId, reason: e.key);
      expect(back.single.type, HairpinType.diminuendo, reason: e.key);
    });

    test('${e.key} still chains two hairpins on a shared note', () {
      final back = e.value(scored(const [
        Hairpin('a0', 'a1', HairpinType.crescendo),
        Hairpin('a1', 'a3', HairpinType.diminuendo),
      ]));
      // ⚠️ By POSITION, never by id: every reader regenerates ids, so
      // comparing them reports a perfect round trip as total corruption.
      final at = {
        for (var i = 0; i < back.measures.single.elements.length; i++)
          back.measures.single.elements[i].id: i
      };
      expect(
        (back.hairpins.map((h) => '${at[h.startId]}-${at[h.endId]}').toList()
              ..sort())
            .join(','),
        '0-1,1-3',
        reason: e.key,
      );
    });
  }

  test('LilyPond orders the degenerate case open-then-close', () {
    final ly = scoreToLilyPond(
        scored(const [Hairpin('a1', 'a1', HairpinType.diminuendo)]));
    expect(ly, contains(r'\>\!'));
    expect(ly, isNot(contains(r'\!\>')));
  });
}
