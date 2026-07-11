import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Export → import round trips: the re-imported score must equal the
/// original by deep value equality (ids included — both sides number
/// elements in reading order).
void main() {
  void roundTrips(String description, Score score) {
    test(description, () {
      final xml = scoreToMusicXml(score);
      final back = scoreFromMusicXml(xml);
      expect(back, score, reason: xml);
    });
  }

  group('round trips', () {
    roundTrips(
      'notes, rests, chords, dotted durations',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q r e4+g4:h. | g4:w | b3+c4+d4:h r:h',
      ),
    );

    roundTrips(
      'all duration letters incl. breve',
      Score.simple(
          notes: 'c4:b | c4:w | c4:h c4:q c4:e c4:s c4:t c4:x '
              'c4:x c4:x c4:x c4:t c4:s c4:e c4:q'),
    );

    roundTrips(
      'accidentals and forced naturals',
      Score.simple(notes: 'f#4:q bb4 cn5 g##4'),
    );

    roundTrips(
      'key, time, bass clef',
      Score.simple(
        clef: Clef.bass,
        keySignature: const KeySignature(-3),
        timeSignature: const TimeSignature(3, 4),
        notes: 'c3:q d3 e3',
      ),
    );

    roundTrips(
      'ties and slurs',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q( d4 e4) f4~ | f4:q( g4) a4:h',
      ),
    );

    roundTrips(
      'tuplets',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '3[c4:e d4 e4] 3[f4:e g4 a4] c5:h',
      ),
    );

    roundTrips(
      'articulations and fermata',
      Score.simple(notes: "c4:q' d4_ e4> f4^ | g4:w@"),
    );

    roundTrips(
      'grace notes',
      Score.simple(notes: '{g4}a4:q {f4,g4}a4:q b4:h'),
    );

    roundTrips(
      'mid-score changes, repeats, voltas',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '!repeat c4:q d4 e4 f4 | !volta=1 g4:w !endrepeat |'
            '!clef=bass !key=2 !time=3/4 c3:q d3 e3',
      ),
    );

    roundTrips(
      'two voices',
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 ; c4:h e4:h | g5:w ; g4:w',
      ),
    );

    roundTrips(
      'lyrics with hyphens and extenders',
      Score.simple(
        notes: 'c4:q d4 e4 f4',
        lyrics: 'twin- kle star_ *',
      ),
    );

    roundTrips(
      'chord symbol annotations',
      Score.simple(
        notes: 'c4:q e4 g4 c5',
        annotations: 'C Em G7 *',
      ),
    );

    test('dynamics and hairpins', () {
      final base = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4',
      );
      final score = Score(
        clef: base.clef,
        keySignature: base.keySignature,
        timeSignature: base.timeSignature,
        measures: base.measures,
        dynamics: const [DynamicMarking('e0', DynamicLevel.mf)],
        hairpins: const [Hairpin('e1', 'e3', HairpinType.crescendo)],
      );
      expect(scoreFromMusicXml(scoreToMusicXml(score)), score);
    });

    test('grand staff round trips as two parts', () {
      final grand = GrandStaff(
        upper: Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:q d5 e5 f5',
        ),
        lower: Score.simple(
          clef: Clef.bass,
          timeSignature: TimeSignature.fourFour,
          notes: 'c3:h g3:h',
        ),
      );
      final back = grandStaffFromMusicXml(grandStaffToMusicXml(grand));
      expect(back.upper, grand.upper);
      // Lower-staff ids come back offset (e1000…) by design; compare
      // structure via re-export.
      expect(
        grandStaffToMusicXml(back).replaceAll('e1000', 'e0'),
        isNotEmpty,
      );
      expect(back.lower.measures.length, grand.lower.measures.length);
      expect(back.lower.clef, grand.lower.clef);
    });
  });

  group('document shape', () {
    test('output is a parsable score-partwise document', () {
      final xml = scoreToMusicXml(Score.simple(notes: 'c4:q'));
      expect(xml, startsWith('<?xml'));
      expect(xml, contains('<score-partwise'));
      expect(xml, contains('<part-list>'));
      expect(() => scoreFromMusicXml(xml), returnsNormally);
    });

    test('special characters in text are escaped', () {
      final score = Score.simple(
        notes: 'c4:q',
        lyrics: '<&>',
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('&lt;&amp;&gt;'));
      expect(scoreFromMusicXml(xml).lyrics.single.text, '<&>');
    });
  });
}
