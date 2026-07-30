import 'dart:io';
import 'package:crisp_notation_core/crisp_notation_core.dart';

String desc(Measure m) {
  String v(List<MusicElement> es) => es.map((e) => e is NoteElement
      ? '${e.pitches.map((p) => p.midiNumber).join(".")}@${e.duration.toFraction()}'
      : e is RestElement ? 'r${e.duration.toFraction()}' : '?').join(' ');
  final t = m.tuplets.map((x) => '[${x.startIndex}..${x.endIndex}]${x.actual}:${x.normal}v${x.voice}').join(',');
  return 'v1[${v(m.elements)}] v2[${v(m.voice2)}]${t.isEmpty ? "" : " T{$t}"}';
}

void main(List<String> a) {
  final src = a[0].endsWith('.mxl')
      ? scoreFromMusicXml(readMusicXmlFromMxl(File(a[0]).readAsBytesSync()))
      : scoreFromMusicXml(File(a[0]).readAsStringSync());
  final fmt = a[1];
  final back = switch (fmt) {
    'kern' => scoreFromKern(scoreToKern(src)),
    'abc' => scoreFromAbc(scoreToAbc(src)),
    'mei' => scoreFromMei(scoreToMei(src)),
    'musescore' => scoreFromMscx(scoreToMscx(src)),
    'musicxml' => scoreFromMusicXml(scoreToMusicXml(src)),
    _ => scoreFromLilyPond(scoreToLilyPond(src)),
  };
  print('measures ${src.measures.length} -> ${back.measures.length}');
  var shown = 0;
  for (var i = 0; i < src.measures.length && i < back.measures.length; i++) {
    final s = desc(src.measures[i]), b = desc(back.measures[i]);
    if (s != b) {
      print('measure $i');
      print('  src : $s');
      print('  back: $b');
      if (++shown >= 2) return;
    }
  }
  if (shown == 0) print('all measures identical');
}
