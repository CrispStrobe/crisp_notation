import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  test('MusicFont.bravura is the default and carries its asset info', () {
    expect(MusicFont.bravura.family, 'Bravura');
    expect(MusicFont.bravura.package, 'partitura');
    expect(MusicFont.bravura.metadataAsset, contains('bravura_metadata.json'));
    expect(const PartituraTheme().musicFont, MusicFont.bravura);
  });

  test('MusicFont value equality', () {
    const same = MusicFont(
      family: 'Bravura',
      package: 'partitura',
      metadataAsset: 'packages/partitura/assets/smufl/bravura_metadata.json',
    );
    expect(same, MusicFont.bravura);
    expect(const MusicFont(family: 'Petaluma', metadataAsset: 'p.json'),
        isNot(MusicFont.bravura));
  });

  test('MusicFonts caches metadata per font (Bravura preloaded for tests)', () {
    expect(MusicFonts.metadataOrNull(MusicFont.bravura), isNotNull);
    expect(Bravura.metadataOrNull,
        same(MusicFonts.metadataOrNull(MusicFont.bravura)));
  });

  test('the optional OFL faces are distinct, well-formed descriptors', () {
    for (final font in [
      MusicFont.petaluma,
      MusicFont.leland,
      MusicFont.leipzig,
    ]) {
      expect(font.package, 'partitura');
      expect(font.metadataAsset, contains(font.family.toLowerCase()));
      expect(font.metadataAsset, endsWith('_metadata.json'));
      expect(font, isNot(MusicFont.bravura));
    }
    // All four are mutually distinct.
    final all = {
      MusicFont.bravura,
      MusicFont.petaluma,
      MusicFont.leland,
      MusicFont.leipzig,
    };
    expect(all, hasLength(4));
  });

  test('the theme carries a swappable music font', () {
    const jazz = MusicFont(
      family: 'Petaluma',
      package: 'my_app',
      metadataAsset: 'assets/petaluma_metadata.json',
    );
    final theme = const PartituraTheme().copyWith(musicFont: jazz);
    expect(theme.musicFont, jazz);
    expect(theme, isNot(const PartituraTheme()));
  });

  testWidgets('the theme music font drives the layout metrics end to end',
      (tester) async {
    // A second font, identical to Bravura but with much heavier staff lines.
    final json = jsonDecode(
            File('assets/smufl/bravura_metadata.json').readAsStringSync())
        as Map<String, Object?>;
    (json['engravingDefaults'] as Map<String, Object?>)['staffLineThickness'] =
        0.5;
    final heavy = SmuflMetadata.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>);
    const heavyFont = MusicFont(
        family: 'HeavyTest', package: 'partitura', metadataAsset: 'n/a');
    MusicFonts.debugRegister(heavyFont, heavy);

    double staffLineThickness(RenderStaffView r) => r.scoreLayout!.primitives
        .whereType<LinePrimitive>()
        .firstWhere((l) => l.from.y == l.to.y)
        .thickness;

    Widget view(MusicFont font) => MaterialApp(
          home: Scaffold(
            body: StaffView(
              score: Score.simple(notes: 'c5:q d5 e5 f5'),
              staffSpace: 12,
              theme: PartituraTheme(musicFont: font),
            ),
          ),
        );

    // Default Bravura.
    await tester.pumpWidget(view(MusicFont.bravura));
    final render = tester.renderObject<RenderStaffView>(find.byType(StaffView));
    final defaultThickness = staffLineThickness(render);

    // Switching the theme's music font relayouts with the new font's metrics.
    await tester.pumpWidget(view(heavyFont));
    final heavyThickness = staffLineThickness(render);

    expect(heavyThickness, 0.5);
    expect(defaultThickness, lessThan(0.5));
  });
}
