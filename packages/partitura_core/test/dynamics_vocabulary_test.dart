import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Score-model lacuna implemented: the `DynamicLevel` vocabulary now covers
/// `ppp/pppp/fff/ffff` and the sforzando family (`sf/sfz/sffz/fz/fp/rf`), not
/// just `pp…ff`. Each maps to a real SMuFL glyph and round-trips through
/// MusicXML (which names dynamics by element).
void main() {
  final base = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5',
  );
  final extended = const [
    DynamicLevel.ppp,
    DynamicLevel.pppp,
    DynamicLevel.fff,
    DynamicLevel.ffff,
    DynamicLevel.sf,
    DynamicLevel.sfz,
    DynamicLevel.sffz,
    DynamicLevel.fz,
  ];
  final withDynamics = Score(
    clef: base.clef,
    timeSignature: base.timeSignature,
    measures: base.measures,
    dynamics: [
      for (var i = 0; i < extended.length; i++)
        DynamicMarking('e$i', extended[i]),
    ],
  );

  test('MusicXML round-trips the extended dynamics vocabulary', () {
    final back = scoreFromMusicXml(scoreToMusicXml(withDynamics));
    expect(back.dynamics, withDynamics.dynamics);
  });

  test('every dynamic level maps to a SMuFL glyph', () {
    for (final level in DynamicLevel.values) {
      final glyph = SmuflGlyph.dynamicGlyph(level);
      expect(glyph, startsWith('dynamic'));
      expect(smuflCodepoints, contains(glyph));
    }
  });

  test('the original pp..ff still map to their glyphs (indices unchanged)', () {
    expect(DynamicLevel.pp.index, 0);
    expect(DynamicLevel.ff.index, 5);
    expect(SmuflGlyph.dynamicGlyph(DynamicLevel.pp), 'dynamicPP');
    expect(SmuflGlyph.dynamicGlyph(DynamicLevel.ff), 'dynamicFF');
  });
}
