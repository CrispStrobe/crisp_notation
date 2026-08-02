import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A `<direction>` span — wedge, pedal, octave-shift — used to be anchored by
/// PREDICTING the id of the next element, and closed on "the last note read".
///
/// Both are wrong in the same two ways. The next element may be a REST, so the
/// span anchored to something the note index does not contain. And "the last
/// note read" jumps voices across a `<backup>` — i.e. in every piano score —
/// producing a span running from one voice into another, which our own writer
/// then cannot re-emit at all.
///
/// Measured on a real two-staff piano file before the fix: 12 hairpins read,
/// 7 of them crossing voices, and a musicxml -> musicxml round trip returned 9.
void main() {
  /// Two voices in one measure, the way `<backup>` writes them.
  String twoVoices(String directions) => '''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>P</part-name></score-part></part-list><part id="P1">
<measure number="1">
<attributes><divisions>1</divisions><key><fifths>0</fifths></key>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
$directions
<note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration>
<voice>1</voice><type>quarter</type></note>
<note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration>
<voice>1</voice><type>quarter</type></note>
<backup><duration>2</duration></backup>
<note><pitch><step>G</step><octave>3</octave></pitch><duration>1</duration>
<voice>2</voice><type>quarter</type></note>
<note><pitch><step>A</step><octave>3</octave></pitch><duration>1</duration>
<voice>2</voice><type>quarter</type></note>
</measure></part></score-partwise>''';

  int voiceOf(Score s, String id) {
    for (var v = 0; v < 4; v++) {
      if (s.measures.single
          .voiceAt(v)
          .any((e) => e is NoteElement && e.id == id)) {
        return v;
      }
    }
    return -1;
  }

  test('a hairpin stays inside the voice it started in', () {
    // The stop sits after the <backup>, so "the last note read" is a voice-2
    // note while the start is in voice 1.
    final s = scoreFromMusicXml(twoVoices(
      '<direction><direction-type><wedge type="crescendo" number="1"/>'
      '</direction-type></direction>',
    ).replaceFirst(
        '<backup>',
        '<direction><direction-type><wedge type="stop" number="1"/>'
            '</direction-type></direction><backup>'));
    expect(s.hairpins, hasLength(1));
    final h = s.hairpins.single;
    expect(voiceOf(s, h.startId), 0);
    expect(voiceOf(s, h.endId), 0, reason: 'must not jump to voice 2');
  });

  test('a hairpin does not anchor to a REST', () {
    final s = scoreFromMusicXml(twoVoices('').replaceFirst(
      '<note><pitch><step>C</step>',
      '<direction><direction-type><wedge type="crescendo" number="1"/>'
          '</direction-type></direction>'
          '<note><rest/><duration>1</duration><voice>1</voice>'
          '<type>quarter</type></note>'
          '<note><pitch><step>C</step>',
    ));
    expect(s.hairpins, hasLength(0),
        reason: 'no stop, so nothing is emitted — but nothing crashes either');
  });

  for (final (name, start, stop) in [
    ('pedal', '<pedal type="start"/>', '<pedal type="stop"/>'),
    (
      'octave-shift',
      '<octave-shift type="down" size="8"/>',
      '<octave-shift type="stop" size="8"/>'
    ),
  ]) {
    test('a $name span stays inside its own voice too', () {
      final s = scoreFromMusicXml(twoVoices(
        '<direction><direction-type>$start</direction-type></direction>',
      ).replaceFirst(
          '<backup>',
          '<direction><direction-type>$stop</direction-type></direction>'
              '<backup>'));
      final spans = name == 'pedal'
          ? s.pedals.map((p) => (p.startId, p.endId)).toList()
          : s.ottavas.map((o) => (o.startId, o.endId)).toList();
      expect(spans, hasLength(1), reason: name);
      expect(voiceOf(s, spans.single.$1), 0, reason: name);
      expect(voiceOf(s, spans.single.$2), 0,
          reason: '$name must not jump to voice 2');
    });
  }
}
