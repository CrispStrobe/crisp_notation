import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Score-model lacuna implemented: a structured metronome mark (`Tempo` — bpm +
/// beat unit + dots) is now a first-class `Score` field. A quarter-note tempo
/// round-trips through every reader; the beat unit/dots survive where the
/// format encodes them (MusicXML/MEI/LilyPond). kern (`*MM`) and MuseScore
/// (`<tempo>`) store a quarter-note-per-minute equivalent, so only quarter-beat
/// tempi round-trip through them exactly (documented).
void main() {
  group('MusicXML <sound tempo>', _soundTempoTests);

  final plain = Score.simple(notes: 'c4:q d4', tempo: const Tempo(120));
  final dotted = Score.simple(
    notes: 'c4:q d4',
    tempo: const Tempo(80, dots: 1),
  );

  test('quarter-note tempo round-trips through every reader', () {
    const t = Tempo(120);
    expect(scoreFromMusicXml(scoreToMusicXml(plain)).tempo, t);
    expect(scoreFromMei(scoreToMei(plain)).tempo, t);
    expect(scoreFromMscx(scoreToMscx(plain)).tempo, t);
    expect(scoreFromKern(scoreToKern(plain)).tempo, t);
  });

  test('MusicXML and MEI keep a dotted-quarter beat unit', () {
    const t = Tempo(80, dots: 1);
    expect(scoreFromMusicXml(scoreToMusicXml(dotted)).tempo, t);
    expect(scoreFromMei(scoreToMei(dotted)).tempo, t);
  });

  test('LilyPond emits a tempo mark', () {
    expect(scoreToLilyPond(plain), contains('\\tempo 4 = 120'));
    expect(scoreToLilyPond(dotted), contains('\\tempo 4. = 80'));
  });

  test('no tempo round-trips as null through every reader', () {
    final none = Score.simple(notes: 'c4:q');
    for (final back in [
      scoreFromMusicXml(scoreToMusicXml(none)),
      scoreFromMei(scoreToMei(none)),
      scoreFromMscx(scoreToMscx(none)),
      scoreFromKern(scoreToKern(none)),
    ]) {
      expect(back.tempo, isNull);
    }
  });
}

/// MusicXML states a tempo two independent ways: `<metronome>` is the mark the
/// score PRINTS, `<sound tempo="…">` is what a player should do. The reader used
/// to look only at `<metronome>`, so a file carrying just the playback attribute
/// — which plenty of exporters write, with no printed mark — imported with no
/// tempo at all.
///
/// Round-trip tests could never catch it: our own writer emits BOTH, so our own
/// files always read back fine. Only other tools' files were affected.
void _soundTempoTests() {
  /// A one-note part whose single `<direction>` is [direction].
  String docWith(String direction, {String extraMeasures = ''}) => '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions>
        <key><fifths>0</fifths></key>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      $direction
      <note><pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration><type>whole</type></note>
    </measure>$extraMeasures
  </part>
</score-partwise>
''';

  test('<sound tempo> alone is read as the initial tempo', () {
    final score = scoreFromMusicXml(
      docWith('<direction><sound tempo="132"/></direction>'),
    );
    expect(score.tempo, isNotNull, reason: '<sound tempo> was ignored');
    expect(score.tempo!.quarterBpm, closeTo(132, 1e-9));
  });

  test('a printed <metronome> wins when a file carries both', () {
    // They can legitimately disagree — a swing mark printed as quarter=120 while
    // playback is told 96 — and the score should read as what it PRINTS.
    final score = scoreFromMusicXml(
      docWith('''
      <direction placement="above">
        <direction-type><metronome>
          <beat-unit>quarter</beat-unit><per-minute>120</per-minute>
        </metronome></direction-type>
        <sound tempo="96"/>
      </direction>'''),
    );
    expect(score.tempo!.quarterBpm, closeTo(120, 1e-9));
  });

  test('a <sound> with no tempo attribute is not a tempo', () {
    // <sound> also carries dynamics, coda jumps, damper pedal…
    final score = scoreFromMusicXml(
      docWith('<direction><sound dynamics="70"/></direction>'),
    );
    expect(score.tempo, isNull);
  });

  test('a nonsense or non-positive tempo is ignored, not imported as 0', () {
    for (final bad in ['0', '-40', 'presto']) {
      final score = scoreFromMusicXml(
        docWith('<direction><sound tempo="$bad"/></direction>'),
      );
      expect(score.tempo, isNull, reason: 'tempo="$bad"');
    }
  });

  test(
    '<sound tempo> in a later measure is a tempo CHANGE, not the initial',
    () {
      // Same rule the metronome path already follows: measure 0 sets the score
      // tempo, anything later is that measure's change.
      final score = scoreFromMusicXml(
        docWith(
          '<direction><sound tempo="100"/></direction>',
          extraMeasures: '''
    <measure number="2">
      <direction><sound tempo="60"/></direction>
      <note><pitch><step>D</step><octave>4</octave></pitch>
        <duration>4</duration><type>whole</type></note>
    </measure>''',
        ),
      );
      expect(score.tempo!.quarterBpm, closeTo(100, 1e-9));
      expect(score.measures.length, 2);
      expect(score.measures[1].tempoChange, isNotNull);
      expect(score.measures[1].tempoChange!.quarterBpm, closeTo(60, 1e-9));
    },
  );

  test('a score with only a later <sound tempo> keeps it as a change', () {
    // The bug the metronome path had already been fixed for: a change in a
    // score with no initial tempo must not be relocated to bar 1.
    final score = scoreFromMusicXml(
      docWith(
        '',
        extraMeasures: '''
    <measure number="2">
      <direction><sound tempo="60"/></direction>
      <note><pitch><step>D</step><octave>4</octave></pitch>
        <duration>4</duration><type>whole</type></note>
    </measure>''',
      ),
    );
    expect(score.tempo, isNull, reason: 'relocated a change to bar 1');
    expect(score.measures[1].tempoChange!.quarterBpm, closeTo(60, 1e-9));
  });

  test('our own writer still round-trips (it emits both)', () {
    final s = Score.simple(notes: 'c4:q d4', tempo: const Tempo(96));
    expect(scoreFromMusicXml(scoreToMusicXml(s)).tempo, const Tempo(96));
  });
}
