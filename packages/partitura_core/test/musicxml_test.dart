import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:partitura_core/src/musicxml/xml_reader.dart';
import 'package:test/test.dart';

/// Wraps measures into a minimal score-partwise document.
String doc(String measures, {String partAttrs = ''}) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="4.0">
  <part-list>
    <score-part id="P1"><part-name>Music</part-name></score-part>
  </part-list>
  <part id="P1"$partAttrs>
$measures
  </part>
</score-partwise>
''';

const attrs44 = '''
<attributes>
  <divisions>2</divisions>
  <key><fifths>0</fifths></key>
  <time><beats>4</beats><beat-type>4</beat-type></time>
  <clef><sign>G</sign><line>2</line></clef>
</attributes>
''';

String note(String step, int octave, String type,
        {int duration = 2, String extra = '', int? alter}) =>
    '<note><pitch><step>$step</step>'
    '${alter == null ? '' : '<alter>$alter</alter>'}'
    '<octave>$octave</octave></pitch>'
    '<duration>$duration</duration><type>$type</type>$extra</note>';

void main() {
  group('xml reader', () {
    test('parses elements, attributes, text, entities', () {
      final root =
          parseXml('<?xml version="1.0"?><a x="1&amp;2"><b>T&#65;</b><c/></a>');
      expect(root.name, 'a');
      expect(root.attributes['x'], '1&2');
      expect(root.childText('b'), 'TA');
      expect(root.child('c'), isNotNull);
    });

    test('skips comments, CDATA, DOCTYPE', () {
      final root = parseXml('<!DOCTYPE x [<!ENTITY y "z">]>'
          '<a><!-- hi --><b><![CDATA[<raw>]]></b></a>');
      expect(root.childText('b'), '<raw>');
    });

    test('throws on mismatched tags', () {
      expect(() => parseXml('<a><b></a></b>'), throwsFormatException);
    });
  });

  group('basics', () {
    test('notes, rests, chords, durations, signatures, clef', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('C', 4, 'quarter')}
  <note><rest/><duration>2</duration><type>quarter</type></note>
  ${note('E', 4, 'half', duration: 4, extra: '<dot/>')}
</measure>
<measure number="2">
  ${note('G', 4, 'whole', duration: 8)}
  ${note('B', 4, 'whole', duration: 8)}
  <note><chord/><pitch><step>D</step><octave>5</octave></pitch>
    <duration>8</duration><type>whole</type></note>
</measure>
'''));
      expect(score.clef, Clef.treble);
      expect(score.keySignature, const KeySignature(0));
      expect(score.timeSignature, TimeSignature.fourFour);
      expect(score.measures, hasLength(2));
      final m1 = score.measures[0].elements;
      expect(m1, hasLength(3));
      expect((m1[0] as NoteElement).pitches.single, const Pitch(Step.c));
      expect(m1[1], isA<RestElement>());
      expect((m1[2] as NoteElement).duration,
          const NoteDuration(DurationBase.half, dots: 1));
      final m2 = score.measures[1].elements;
      expect(m2, hasLength(2));
      final chord = m2[1] as NoteElement;
      expect(chord.pitches, hasLength(2)); // B4 + D5 via <chord/>
      // Ids in reading order.
      expect(m1.map((e) => e.id), ['e0', 'e1', 'e2']);
      expect(m2.map((e) => e.id), ['e3', 'e4']);
    });

    test('alter maps to accidentals; <accidental> forces display', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('F', 4, 'quarter', alter: 1)}
  ${note('B', 4, 'quarter', alter: -1, extra: '<accidental>flat</accidental>')}
</measure>
'''));
      final notes = score.measures.single.elements.cast<NoteElement>();
      expect(notes[0].pitches.single, const Pitch(Step.f, alter: 1));
      expect(notes[0].showAccidental, isNull);
      expect(notes[1].showAccidental, isTrue);
    });

    test('bass and C clefs', () {
      Clef clefOf(String sign, int line) => scoreFromMusicXml(doc('''
<measure number="1">
  <attributes><divisions>1</divisions>
    <clef><sign>$sign</sign><line>$line</line></clef></attributes>
  ${note('C', 3, 'whole', duration: 4)}
</measure>
''')).clef;
      expect(clefOf('F', 4), Clef.bass);
      expect(clefOf('C', 3), Clef.alto);
      expect(clefOf('C', 4), Clef.tenor);
    });

    test('whole-measure rest without <type> derives from divisions', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  <note><rest/><duration>8</duration></note>
</measure>
'''));
      expect(
          score.measures.single.elements.single.duration, NoteDuration.whole);
    });
  });

  group('notations and spans', () {
    test('ties, slurs, articulations, fermata', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('C', 4, 'quarter', extra: '<tie type="start"/>'
              '<notations><slur type="start" number="1"/>'
              '<articulations><staccato/><accent/></articulations>'
              '</notations>')}
  ${note('C', 4, 'quarter')}
  ${note('D', 4, 'quarter', extra: '<notations>'
              '<slur type="stop" number="1"/><fermata/></notations>')}
  ${note('E', 4, 'quarter', extra: '<notations><articulations>'
              '<strong-accent/><tenuto/></articulations></notations>')}
</measure>
'''));
      final notes = score.measures.single.elements.cast<NoteElement>();
      expect(notes[0].tieToNext, isTrue);
      expect(
          notes[0].articulations, {Articulation.staccato, Articulation.accent});
      expect(notes[2].articulations, {Articulation.fermata});
      expect(
          notes[3].articulations, {Articulation.marcato, Articulation.tenuto});
      expect(score.slurs, const [Slur('e0', 'e2')]);
    });

    test('unclosed slur throws', () {
      expect(
        () => scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('C', 4, 'whole', duration: 8, extra: '<notations><slur type="start"/></notations>')}
</measure>
''')),
        throwsFormatException,
      );
    });

    test('tuplet from time-modification', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('C', 4, 'eighth', duration: 1, extra: '<time-modification>'
              '<actual-notes>3</actual-notes><normal-notes>2</normal-notes>'
              '</time-modification><notations><tuplet type="start"/></notations>')}
  ${note('D', 4, 'eighth', duration: 1, extra: '<time-modification>'
              '<actual-notes>3</actual-notes><normal-notes>2</normal-notes>'
              '</time-modification>')}
  ${note('E', 4, 'eighth', duration: 1, extra: '<time-modification>'
              '<actual-notes>3</actual-notes><normal-notes>2</normal-notes>'
              '</time-modification><notations><tuplet type="stop"/></notations>')}
</measure>
'''));
      final tuplet = score.measures.single.tuplets.single;
      expect((tuplet.startIndex, tuplet.endIndex), (0, 2));
      expect((tuplet.actual, tuplet.normal), (3, 2));
    });

    test('grace notes attach to the following note', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  <note><grace/><pitch><step>G</step><octave>4</octave></pitch>
    <type>eighth</type></note>
  ${note('A', 4, 'quarter')}
</measure>
'''));
      final target = score.measures.single.elements.single as NoteElement;
      expect(target.graceNotes, [const Pitch(Step.g)]);
    });
  });

  group('directions', () {
    test('dynamics attach to the next note', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  <direction><direction-type><dynamics><p/></dynamics></direction-type></direction>
  ${note('C', 4, 'half', duration: 4)}
  <direction><direction-type><dynamics><ff/></dynamics></direction-type></direction>
  ${note('G', 4, 'half', duration: 4)}
</measure>
'''));
      expect(score.dynamics, const [
        DynamicMarking('e0', DynamicLevel.p),
        DynamicMarking('e1', DynamicLevel.ff),
      ]);
    });

    test('wedges become hairpins spanning start to stop', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  <direction><direction-type><wedge type="crescendo"/></direction-type></direction>
  ${note('C', 4, 'quarter')}
  ${note('D', 4, 'quarter')}
  ${note('E', 4, 'half', duration: 4)}
  <direction><direction-type><wedge type="stop"/></direction-type></direction>
</measure>
'''));
      expect(
          score.hairpins, const [Hairpin('e0', 'e2', HairpinType.crescendo)]);
    });

    test('lyrics with syllabic and extend', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('C', 4, 'quarter', extra: '<lyric><syllabic>begin</syllabic>'
              '<text>Twin</text></lyric>')}
  ${note('C', 4, 'quarter', extra: '<lyric><syllabic>end</syllabic>'
              '<text>kle</text></lyric>')}
  ${note('G', 4, 'half', duration: 4, extra: '<lyric><syllabic>single</syllabic>'
              '<text>star</text><extend/></lyric>')}
</measure>
'''));
      expect(score.lyrics, const [
        Lyric('e0', 'Twin', hyphenToNext: true),
        Lyric('e1', 'kle'),
        Lyric('e2', 'star', extender: true),
      ]);
    });

    test('harmony becomes a structured chord symbol on the next note', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  <harmony><root><root-step>C</root-step></root><kind>major</kind></harmony>
  ${note('C', 4, 'half', duration: 4)}
  <harmony><root><root-step>A</root-step></root><kind>minor</kind></harmony>
  ${note('A', 4, 'half', duration: 4)}
</measure>
'''));
      expect(score.chordSymbols, const [
        ChordSymbol('e0', Pitch(Step.c), ChordSymbolKind.major),
        ChordSymbol('e1', Pitch(Step.a), ChordSymbolKind.minor),
      ]);
      expect(score.chordSymbols.map((c) => c.text), ['C', 'Am']);
    });
  });

  group('structure', () {
    test('two voices split into elements and voice2', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('C', 5, 'half', duration: 4, extra: '<voice>1</voice>')}
  ${note('D', 5, 'half', duration: 4, extra: '<voice>1</voice>')}
  <backup><duration>8</duration></backup>
  ${note('C', 4, 'whole', duration: 8, extra: '<voice>2</voice>')}
</measure>
'''));
      final measure = score.measures.single;
      expect(measure.elements, hasLength(2));
      expect(measure.voice2, hasLength(1));
      expect((measure.voice2.single as NoteElement).pitches.single,
          const Pitch(Step.c));
    });

    test('mid-score clef/key/time changes and repeats/voltas', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  <barline location="left"><repeat direction="forward"/></barline>
  ${note('C', 4, 'whole', duration: 8)}
</measure>
<measure number="2">
  <attributes>
    <key><fifths>2</fifths></key>
    <time><beats>3</beats><beat-type>4</beat-type></time>
    <clef><sign>F</sign><line>4</line></clef>
  </attributes>
  <barline location="left"><ending number="1" type="start"/></barline>
  ${note('D', 3, 'half', duration: 4, extra: '<dot/>')}
  <barline location="right"><repeat direction="backward"/></barline>
</measure>
'''));
      final m1 = score.measures[0];
      final m2 = score.measures[1];
      expect(m1.startRepeat, isTrue);
      expect(m2.endRepeat, isTrue);
      expect(m2.volta, 1);
      expect(m2.clefChange, Clef.bass);
      expect(m2.keyChange, const KeySignature(2));
      expect(m2.timeChange, const TimeSignature(3, 4));
    });

    test('breath marks and caesura round-trip through MusicXML', () {
      final base = Score.simple(notes: 'c5:q d5 e5 f5');
      final score = Score(
        clef: base.clef,
        measures: base.measures,
        breathMarks: const [
          BreathMark('e1', BreathSymbol.comma),
          BreathMark('e3', BreathSymbol.caesura),
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<breath-mark/>'));
      expect(xml, contains('<caesura/>'));
      expect(scoreFromMusicXml(xml).breathMarks, score.breathMarks);
    });

    test('figured bass round-trips through MusicXML', () {
      final base = Score.simple(clef: Clef.bass, notes: 'c3:q g2 a2 f2');
      final score = Score(
        clef: base.clef,
        measures: base.measures,
        figuredBass: const [
          FiguredBass('e1', ['6']),
          FiguredBass('e2', ['6', '5']),
          FiguredBass('e3', ['#6', '4']),
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<figured-bass>'));
      expect(xml, contains('<figure-number>6</figure-number>'));
      expect(xml, contains('<prefix>sharp</prefix>'));
      final back = scoreFromMusicXml(xml);
      expect(back.figuredBass, score.figuredBass);
    });

    test('slashed figures and continuation lines round-trip', () {
      final base = Score.simple(clef: Clef.bass, notes: 'c3:q g2 a2 f2');
      final score = Score(
        clef: base.clef,
        measures: base.measures,
        figuredBass: const [
          FiguredBass('e0', [r'6\']),
          FiguredBass('e1', ['_']),
          FiguredBass('e2', [r'5\', '3']),
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<suffix>slash</suffix>'));
      expect(xml, contains('<extend/>'));
      final back = scoreFromMusicXml(xml);
      expect(back.figuredBass, score.figuredBass);
    });

    test('jazz articulations round-trip through MusicXML', () {
      final base = Score.simple(notes: 'c4:q d4 e4 f4');
      final score = Score(
        clef: base.clef,
        measures: base.measures,
        jazzMarks: const [
          JazzMark('e0', JazzArticulation.scoop),
          JazzMark('e1', JazzArticulation.doit),
          JazzMark('e2', JazzArticulation.fall),
          JazzMark('e3', JazzArticulation.plop),
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<scoop/>'));
      expect(xml, contains('<doit/>'));
      expect(xml, contains('<falloff/>'));
      expect(xml, contains('<plop/>'));
      final back = scoreFromMusicXml(xml);
      expect(back.jazzMarks, score.jazzMarks);
    });

    test('multi-verse lyrics round-trip through MusicXML', () {
      final base = Score.simple(notes: 'c4:q d4 e4 f4');
      final score = Score(
        clef: base.clef,
        measures: base.measures,
        lyrics: const [
          Lyric('e0', 'One', verse: 1),
          Lyric('e1', 'two', verse: 1),
          Lyric('e0', 'A', verse: 2),
          Lyric('e1', 'B', verse: 2),
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<lyric number="1">'));
      expect(xml, contains('<lyric number="2">'));
      final back = scoreFromMusicXml(xml);
      final v2 = back.lyrics.where((l) => l.verse == 2).toList();
      expect(v2.map((l) => l.text), ['A', 'B']);
      expect(back.lyrics.where((l) => l.verse == 1).map((l) => l.text),
          ['One', 'two']);
    });

    test('notehead shapes round-trip through MusicXML', () {
      NoteElement head(NoteheadShape shape, String id) =>
          NoteElement.note(const Pitch(Step.b, octave: 4), NoteDuration.quarter,
              notehead: shape, id: id);
      final score = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            head(NoteheadShape.x, 'e0'),
            head(NoteheadShape.diamond, 'e1'),
            head(NoteheadShape.triangleUp, 'e2'),
            head(NoteheadShape.slash, 'e3'),
          ]),
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<notehead>x</notehead>'));
      expect(xml, contains('<notehead>diamond</notehead>'));
      expect(xml, contains('<notehead>triangle</notehead>'));
      expect(xml, contains('<notehead>slash</notehead>'));
      final back = scoreFromMusicXml(xml);
      expect(
        back.measures.single.elements
            .cast<NoteElement>()
            .map((n) => n.notehead),
        [
          NoteheadShape.x,
          NoteheadShape.diamond,
          NoteheadShape.triangleUp,
          NoteheadShape.slash,
        ],
      );
    });

    test('barline styles round-trip through MusicXML', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:w !barline=doubleBar | d4:w !barline=dashed |'
            ' e4:w !barline=finalBar',
      );
      expect(score.measures.map((m) => m.barline), [
        BarlineStyle.doubleBar,
        BarlineStyle.dashed,
        BarlineStyle.finalBar,
      ]);
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<bar-style>light-light</bar-style>'));
      expect(xml, contains('<bar-style>dashed</bar-style>'));
      expect(xml, contains('<bar-style>light-heavy</bar-style>'));
      final back = scoreFromMusicXml(xml);
      expect(back.measures.map((m) => m.barline),
          score.measures.map((m) => m.barline));
    });

    test('grand staff from a two-staff part', () {
      final grand = grandStaffFromMusicXml(doc('''
<measure number="1">
  <attributes>
    <divisions>2</divisions>
    <key><fifths>0</fifths></key>
    <time><beats>4</beats><beat-type>4</beat-type></time>
    <staves>2</staves>
    <clef number="1"><sign>G</sign><line>2</line></clef>
    <clef number="2"><sign>F</sign><line>4</line></clef>
  </attributes>
  ${note('C', 5, 'whole', duration: 8, extra: '<staff>1</staff>')}
  <backup><duration>8</duration></backup>
  ${note('C', 3, 'whole', duration: 8, extra: '<staff>2</staff>')}
</measure>
'''));
      expect(grand.upper.clef, Clef.treble);
      expect(grand.lower.clef, Clef.bass);
      expect(grand.upper.measures.single.elements.single.id, 'e0');
      expect(grand.lower.measures.single.elements.single.id, 'e1000');
    });

    test('imported score lays out without errors', () {
      final score = scoreFromMusicXml(doc('''
<measure number="1">
  $attrs44
  ${note('C', 4, 'quarter')}
  ${note('D', 4, 'quarter')}
  ${note('E', 4, 'quarter')}
  ${note('F', 4, 'quarter')}
</measure>
'''));
      // Round through the DSL-built equivalent: same layout inputs.
      final dsl = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4',
      );
      expect(score, dsl);
    });

    test('errors: wrong root, missing part', () {
      expect(() => scoreFromMusicXml('<opus/>'), throwsFormatException);
      expect(
        () => scoreFromMusicXml(doc('<measure number="1"/>'), partIndex: 3),
        throwsFormatException,
      );
    });
  });

  group('staff system (multi-part)', () {
    // A score-partwise document with an arbitrary part-list and parts.
    String multi(String partList, String parts) => '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list>$partList</part-list>
  $parts
</score-partwise>
''';

    String simplePart(String id, String step, int octave, String sign) => '''
<part id="$id">
  <measure number="1">
    <attributes><divisions>2</divisions><key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>$sign</sign><line>${sign == 'F' ? 4 : 2}</line></clef>
    </attributes>
    ${note(step, octave, 'whole', duration: 8)}
  </measure>
</part>''';

    test('two parts become two staves with disjoint id spaces', () {
      final sys = staffSystemFromMusicXml(multi(
        '<score-part id="P1"/><score-part id="P2"/>',
        '${simplePart('P1', 'C', 5, 'G')}${simplePart('P2', 'C', 3, 'F')}',
      ));
      expect(sys.staves, hasLength(2));
      expect(sys.staves[0].clef, Clef.treble);
      expect(sys.staves[1].clef, Clef.bass);
      expect(sys.staves[0].measures.single.elements.single.id, 'e0');
      expect(sys.staves[1].measures.single.elements.single.id, 'e1000');
    });

    test('a two-staff part is braced', () {
      final sys = staffSystemFromMusicXml(multi(
        '<score-part id="P1"/>',
        '''
<part id="P1">
  <measure number="1">
    <attributes><divisions>2</divisions><key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <staves>2</staves>
      <clef number="1"><sign>G</sign><line>2</line></clef>
      <clef number="2"><sign>F</sign><line>4</line></clef>
    </attributes>
    ${note('C', 5, 'whole', duration: 8, extra: '<staff>1</staff>')}
    <backup><duration>8</duration></backup>
    ${note('C', 3, 'whole', duration: 8, extra: '<staff>2</staff>')}
  </measure>
</part>''',
      ));
      expect(sys.staves, hasLength(2));
      expect(sys.brackets,
          contains(const StaffBracket(0, 1, kind: StaffBracketKind.brace)));
    });

    test('a part-group bracket wraps its parts', () {
      final sys = staffSystemFromMusicXml(multi(
        '<part-group type="start" number="1">'
            '<group-symbol>bracket</group-symbol></part-group>'
            '<score-part id="P1"/><score-part id="P2"/>'
            '<part-group type="stop" number="1"/>'
            '<score-part id="P3"/>',
        '${simplePart('P1', 'C', 5, 'G')}'
            '${simplePart('P2', 'E', 4, 'G')}'
            '${simplePart('P3', 'C', 3, 'F')}',
      ));
      expect(sys.staves, hasLength(3));
      expect(sys.brackets,
          contains(const StaffBracket(0, 1, kind: StaffBracketKind.bracket)));
    });

    test('lays out as an aligned system', () {
      final meta = SmuflMetadata.fromJson(jsonDecode(
          File('../partitura/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>);
      final sys = staffSystemFromMusicXml(multi(
        '<score-part id="P1"/><score-part id="P2"/>',
        '${simplePart('P1', 'C', 5, 'G')}${simplePart('P2', 'C', 3, 'F')}',
      ));
      final layout = layoutStaffSystem(sys, LayoutSettings(metadata: meta));
      expect(layout.staves, hasLength(2));
      expect(layout.width, greaterThan(0));
    });
  });
}
