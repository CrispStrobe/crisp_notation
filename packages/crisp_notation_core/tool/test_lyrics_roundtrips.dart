import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  test('ABC -> Ly -> ABC lyrics roundtrip', () {
    final abcSource = "X: 1\nK: D\nB B B B B\nw: Al-le * Jah-re";
    
    // 1. Parse ABC
    final scoreAbc = scoreFromAbc(abcSource);
    expect(scoreAbc.lyrics.length, 4); // "Al", "le", "Jah", "re"
    expect(scoreAbc.lyrics[0].text, "Al");
    expect(scoreAbc.lyrics[0].hyphenToNext, true);
    expect(scoreAbc.lyrics[1].text, "le");
    // Third note is skipped because of *
    expect(scoreAbc.lyrics[2].text, "Jah");
    expect(scoreAbc.lyrics[2].hyphenToNext, true);
    expect(scoreAbc.lyrics[3].text, "re");

    // 2. Export to LilyPond
    final lySource = scoreToLilyPond(scoreAbc);
    
    // 3. Import from LilyPond
    final scoreLy = scoreFromLilyPond(lySource);
    expect(scoreLy.lyrics.length, 4);
    expect(scoreLy.lyrics[0].text, "Al");
    expect(scoreLy.lyrics[0].hyphenToNext, true);
    expect(scoreLy.lyrics[1].text, "le");
    expect(scoreLy.lyrics[2].text, "Jah");
    expect(scoreLy.lyrics[2].hyphenToNext, true);
    expect(scoreLy.lyrics[3].text, "re");

    // 4. Export to ABC
    final abcExport = scoreToAbc(scoreLy);
    
    // 5. Import from ABC
    final scoreAbcFinal = scoreFromAbc(abcExport);
    expect(scoreAbcFinal.lyrics.length, 4);
    expect(scoreAbcFinal.lyrics[0].text, "Al");
    expect(scoreAbcFinal.lyrics[0].hyphenToNext, true);
    expect(scoreAbcFinal.lyrics[1].text, "le");
    expect(scoreAbcFinal.lyrics[2].text, "Jah");
    expect(scoreAbcFinal.lyrics[2].hyphenToNext, true);
    expect(scoreAbcFinal.lyrics[3].text, "re");
  });

  test('Ly -> XML -> Ly lyrics roundtrip', () {
    final lySource = r"""
\score {
  <<
    \new Staff { c'4 d'4 e'4 }
    \addlyrics { Al -- le __ }
  >>
}""";
    
    // 1. Parse Ly
    final scoreLy = scoreFromLilyPond(lySource);
    expect(scoreLy.lyrics.length, 2);
    expect(scoreLy.lyrics[0].text, "Al");
    expect(scoreLy.lyrics[0].hyphenToNext, true);
    expect(scoreLy.lyrics[1].text, "le");
    expect(scoreLy.lyrics[1].extender, true);

    // 2. Export to MusicXML
    final xmlSource = scoreToMusicXml(scoreLy);
    
    // 3. Import from MusicXML
    final scoreXml = scoreFromMusicXml(xmlSource);
    expect(scoreXml.lyrics.length, 2);
    expect(scoreXml.lyrics[0].text, "Al");
    expect(scoreXml.lyrics[0].hyphenToNext, true);
    expect(scoreXml.lyrics[1].text, "le");
    expect(scoreXml.lyrics[1].extender, true);

    // 4. Export back to LilyPond
    final finalLySource = scoreToLilyPond(scoreXml);
    final scoreFinal = scoreFromLilyPond(finalLySource);
    expect(scoreFinal.lyrics.length, 2);
    expect(scoreFinal.lyrics[0].text, "Al");
    expect(scoreFinal.lyrics[0].hyphenToNext, true);
    expect(scoreFinal.lyrics[1].text, "le");
    expect(scoreFinal.lyrics[1].extender, true);
  });
}
