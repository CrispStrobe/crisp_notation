// A `<direction>` with several `<direction-type>` children — GitHub issue #4.
//
// Exporters routinely split one direction across sibling `<direction-type>`
// blocks (tempo text in one, its `<metronome>` in the next), in an order that
// varies by tool. The reader looked only inside the FIRST block, so whichever
// half came second was silently dropped.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A one-part score: [directions] sits before the first of two quarter notes
/// in measure 1, then a second measure of two quarters.
String doc(String directions) => '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Music</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions><time><beats>2</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef></attributes>
      $directions
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
    </measure>
    <measure number="2">
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
      <note><pitch><step>F</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
    </measure>
  </part>
</score-partwise>''';

const words = '<direction-type><words font-weight="bold">Adagio</words>'
    '</direction-type>';
const metronome = '<direction-type><metronome><beat-unit>eighth</beat-unit>'
    '<per-minute>63</per-minute></metronome></direction-type>';

String direction(List<String> types, {String extra = ''}) =>
    '<direction placement="above">${types.join()}$extra</direction>';

void main() {
  group('words + metronome in separate direction-types (the issue)', () {
    for (final (name, order) in [
      ('words first', [words, metronome]),
      ('metronome first', [metronome, words]),
    ]) {
      test('$name: both the text and the tempo survive', () {
        final score = scoreFromMusicXml(
            doc(direction(order, extra: '<sound tempo="31.5"/>')));
        expect(score.annotations.map((a) => a.text), ['Adagio']);
        expect(score.tempo, const Tempo(63, beatUnit: DurationBase.eighth));
      });
    }
  });

  test('a <metronome> in the second block beats <sound tempo>', () {
    final score = scoreFromMusicXml(
        doc(direction([words, metronome], extra: '<sound tempo="99"/>')));
    expect(score.tempo!.bpm, 63);
  });

  test('a dynamic in the second block is read', () {
    final score = scoreFromMusicXml(doc(direction([
      words,
      '<direction-type><dynamics><pp/></dynamics></direction-type>',
    ])));
    expect(score.dynamics.map((d) => d.level), [DynamicLevel.pp]);
  });

  test('a wedge in the second block is read', () {
    // The wedge starts at the first note; its stop sits before the second.
    final xml = doc(direction([
      words,
      '<direction-type><wedge type="crescendo"/></direction-type>',
    ])).replaceFirst(
        '<note><pitch><step>D</step>',
        '<direction><direction-type><wedge type="stop"/></direction-type>'
            '</direction><note><pitch><step>D</step>');
    final score = scoreFromMusicXml(xml);
    expect(score.hairpins, hasLength(1));
    expect(score.hairpins.single.type, HairpinType.crescendo);
  });

  test('an octave-shift in the second block is read', () {
    final xml = doc(direction([
      words,
      '<direction-type><octave-shift type="down" size="8"/></direction-type>',
    ])).replaceFirst(
        '<note><pitch><step>E</step>',
        '<direction><direction-type><octave-shift type="stop" size="8"/>'
            '</direction-type></direction><note><pitch><step>E</step>');
    final score = scoreFromMusicXml(xml);
    expect(score.ottavas, hasLength(1));
  });

  test('a pedal in the second block is read', () {
    final xml = doc(direction([
      words,
      '<direction-type><pedal type="start"/></direction-type>',
    ])).replaceFirst(
        '<note><pitch><step>E</step>',
        '<direction><direction-type><pedal type="stop"/></direction-type>'
            '</direction><note><pitch><step>E</step>');
    final score = scoreFromMusicXml(xml);
    expect(score.pedals, hasLength(1));
  });

  test('a segno in the second block is a navigation mark, not lost', () {
    final score = scoreFromMusicXml(
        doc(direction([words, '<direction-type><segno/></direction-type>'])));
    expect(score.measures.first.navigation, NavigationMark.segno);
  });

  test('a navigation label in the second block is not an annotation', () {
    final label = SmuflGlyph.navigationLabel(NavigationMark.daCapo);
    final score = scoreFromMusicXml(doc(direction([
      metronome,
      '<direction-type><words>$label</words></direction-type>',
    ])));
    expect(score.measures.first.navigation, NavigationMark.daCapo);
    expect(score.annotations, isEmpty);
    expect(score.tempo!.bpm, 63);
  });

  test('"Andante. (" ♩=63 ".)": the bracket around the metronome is dropped',
      () {
    // A real exporter shape (seen in the CometBeat corpus): the metronome is
    // parenthesised by words on either side of it.
    final score = scoreFromMusicXml(doc(direction([
      '<direction-type><words>Andante. (</words></direction-type>',
      metronome,
      '<direction-type><words>.)</words></direction-type>',
    ])));
    expect(score.annotations.map((a) => a.text), ['Andante.']);
    expect(score.tempo!.bpm, 63);
  });

  test('a lone "(" around a metronome leaves no empty annotation', () {
    final score = scoreFromMusicXml(doc(direction([
      '<direction-type><words>(</words></direction-type>',
      metronome,
      '<direction-type><words>)</words></direction-type>',
    ])));
    expect(score.annotations, isEmpty);
    expect(score.tempo!.bpm, 63);
  });

  test('a bracket in plain words (no metronome) is kept verbatim', () {
    final score = scoreFromMusicXml(doc(
        direction(['<direction-type><words>(dolce</words></direction-type>'])));
    expect(score.annotations.single.text, '(dolce');
  });

  group('several text runs and directions', () {
    test('styled runs in one direction-type join into one marking', () {
      // Finale writes each style change as its own <words>.
      final score = scoreFromMusicXml(doc(direction([
        '<direction-type><words font-weight="bold">Allegro</words>'
            '<words font-style="italic"> con brio</words></direction-type>',
      ])));
      expect(score.annotations.map((a) => a.text), ['Allegro con brio']);
    });

    test('runs across direction-types join too', () {
      final score = scoreFromMusicXml(doc(direction([
        '<direction-type><words>poco</words></direction-type>',
        '<direction-type><words>rit.</words></direction-type>',
      ])));
      expect(score.annotations.map((a) => a.text), ['poco rit.']);
    });

    test('a run starting with punctuation joins without a space', () {
      final score = scoreFromMusicXml(doc(direction([
        '<direction-type><words>cresc</words><words>.</words>'
            '</direction-type>',
      ])));
      expect(score.annotations.single.text, 'cresc.');
    });

    test('two directions before one note keep both, each on its own side', () {
      final score = scoreFromMusicXml(
          doc('<direction placement="above"><direction-type><words>Allegro'
              '</words></direction-type></direction>'
              '<direction placement="below"><direction-type><words>dolce'
              '</words></direction-type></direction>'));
      expect(score.annotations.map((a) => (a.text, a.placement)), [
        ('Allegro', AnnotationPlacement.above),
        ('dolce', AnnotationPlacement.below),
      ]);
      // Both anchor on the first note.
      expect(score.annotations.map((a) => a.elementId).toSet(), hasLength(1));
    });

    test('both annotations survive a MusicXML round trip', () {
      final score = scoreFromMusicXml(
          doc('<direction placement="above"><direction-type><words>Allegro'
              '</words></direction-type></direction>'
              '<direction placement="below"><direction-type><words>dolce'
              '</words></direction-type></direction>'));
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      // Order between annotations on one note carries no meaning.
      expect(back.annotations.map((a) => (a.text, a.placement)),
          unorderedEquals(score.annotations.map((a) => (a.text, a.placement))));
    });
  });

  test('a single combined direction-type still works (no regression)', () {
    final score =
        scoreFromMusicXml(doc('<direction placement="below"><direction-type>'
            '<words>dolce</words></direction-type></direction>'));
    expect(score.annotations.single.text, 'dolce');
    expect(score.annotations.single.placement, AnnotationPlacement.below);
  });

  test('the split direction survives a MusicXML round trip', () {
    final score = scoreFromMusicXml(doc(direction([metronome, words])));
    final back = scoreFromMusicXml(scoreToMusicXml(score));
    expect(back.annotations.map((a) => a.text), ['Adagio']);
    expect(back.tempo, score.tempo);
  });
}
