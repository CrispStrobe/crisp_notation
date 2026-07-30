import 'dart:io';
import 'package:crisp_notation_core/crisp_notation_core.dart';
void main(List<String> a) {
  final src = scoreFromMusicXml(readMusicXmlFromMxl(File(a[0]).readAsBytesSync()));
  final mei = scoreToMei(src);
  final want = 'n="${int.parse(a[1]) + 1}"';
  final lines = mei.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains('<measure') && lines[i].contains(want)) {
      for (var k = i; k < i + 24 && k < lines.length; k++) {
        print(lines[k].trim());
      }
      return;
    }
  }
  print('measure not found; sample:');
  print(lines.where((l) => l.contains('<measure')).take(3).join('\n'));
}
