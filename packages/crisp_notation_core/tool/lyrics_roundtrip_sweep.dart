import 'dart:io';
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main() {
  int lyFiles = 0;
  int lySuccess = 0;
  int lyFailed = 0;

  final lyDir = Directory('test/data/ly_corpus');
  for (final file in lyDir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.ly')) continue;
    try {
      final scoreOrig = scoreFromLilyPond(file.readAsStringSync());
      if (scoreOrig.lyrics.isEmpty) continue;
      lyFiles++;
      
      final xmlString = scoreToMusicXml(scoreOrig);
      final scoreXml = scoreFromMusicXml(xmlString);
      
      final lyString = scoreToLilyPond(scoreXml);
      final scoreFinal = scoreFromLilyPond(lyString);
      
      if (scoreOrig.lyrics.length == scoreFinal.lyrics.length) {
        lySuccess++;
      } else {
        lyFailed++;
        print("LY -> XML -> LY failed for ${file.path.split('/').last}: expected ${scoreOrig.lyrics.length}, got ${scoreFinal.lyrics.length}");
      }
    } catch (e) {
      lyFailed++;
      print("LY -> XML -> LY crashed for ${file.path.split('/').last}: $e");
    }
  }

  int xmlFiles = 0;
  int xmlSuccess = 0;
  int xmlFailed = 0;
  
  final xmlDir = Directory('test/data/xml_real_world');
  for (final file in xmlDir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.xml') && !file.path.endsWith('.mxl')) continue;
    try {
      Score scoreOrig;
      if (file.path.endsWith('.mxl')) {
        scoreOrig = scoreFromMusicXml(readMusicXmlFromMxl(file.readAsBytesSync()));
      } else {
        scoreOrig = scoreFromMusicXml(file.readAsStringSync());
      }
      if (scoreOrig.lyrics.isEmpty) continue;
      xmlFiles++;
      
      final lyString = scoreToLilyPond(scoreOrig);
      final scoreLy = scoreFromLilyPond(lyString);
      
      final xmlString = scoreToMusicXml(scoreLy);
      final scoreFinal = scoreFromMusicXml(xmlString);
      
      if (scoreOrig.lyrics.length == scoreFinal.lyrics.length) {
        xmlSuccess++;
      } else {
        xmlFailed++;
        print("XML -> LY -> XML failed for ${file.path.split('/').last}: expected ${scoreOrig.lyrics.length}, got ${scoreFinal.lyrics.length}");
      }
    } catch (e) {
      xmlFailed++;
      print("XML -> LY -> XML crashed for ${file.path.split('/').last}: $e");
    }
  }

  print('\nLyrics Roundtrip Metrics:');
  print('-------------------------');
  print('LilyPond -> XML -> LilyPond:');
  print('  Files with lyrics: $lyFiles');
  print('  100% Roundtrip:    $lySuccess (${lyFiles > 0 ? (lySuccess / lyFiles * 100).toStringAsFixed(1) : 0}%)');
  print('  Failed/Lossy:      $lyFailed');
  print('');
  print('MusicXML -> LilyPond -> MusicXML:');
  print('  Files with lyrics: $xmlFiles');
  print('  100% Roundtrip:    $xmlSuccess (${xmlFiles > 0 ? (xmlSuccess / xmlFiles * 100).toStringAsFixed(1) : 0}%)');
  print('  Failed/Lossy:      $xmlFailed');
}
