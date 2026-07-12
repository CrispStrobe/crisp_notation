import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';
import 'package:partitura_example/gallery.dart';
import 'package:partitura_example/interactive.dart';
import 'package:partitura_example/main.dart';

/// Widget-level smoke tests of the example app (the deeper end-to-end run
/// lives in integration_test/ and drives a real device).
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Assets live in the partitura package one directory up.
    final metadataSource =
        File('../assets/smufl/bravura_metadata.json').readAsStringSync();
    Bravura.debugOverrideMetadata(
      SmuflMetadata.fromJson(
        jsonDecode(metadataSource) as Map<String, Object?>,
      ),
    );
    final fontBytes = File('../assets/fonts/Bravura.otf').readAsBytesSync();
    final loader = FontLoader('packages/partitura/Bravura')
      ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
    await loader.load();
  });

  testWidgets('home screen shows the gallery and switches tabs',
      (tester) async {
    await tester.pumpWidget(const PartituraExampleApp());
    await tester.pumpAndSettle();

    expect(find.byType(GalleryScreen), findsOneWidget);
    expect(find.text('C major scale (treble)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Interactive'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveScreen), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interactive screen places and selects a note (widget level)',
      (tester) async {
    await tester.pumpWidget(const PartituraExampleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interactive'));
    await tester.pumpAndSettle();

    final staffFinder = find.bySubtype<StaffView>().first;
    final staff = tester.renderObject<RenderStaffView>(staffFinder);
    expect(staff.scoreLayout!.regions, isEmpty);

    final topLeft = tester.getTopLeft(staffFinder);
    final layout = staff.scoreLayout!;
    final x = (layout.measureRegions.first.startX + layout.width) / 2;
    final local = staff.staffToLocal(math.Point(x, 4.0));
    await tester.tapAt(topLeft + local);
    await tester.pumpAndSettle();
    // Regression guard: the score is rebuilt with copied element lists;
    // in-place list mutation would defeat the value-equality relayout
    // check (this exact bug shipped in an earlier example revision).
    expect(staff.scoreLayout!.regions, hasLength(1));

    // Tap the placed note: it becomes highlighted.
    final region = staff.scoreLayout!.regions.single;
    final center = (region.bounds.topLeft + region.bounds.bottomRight) * 0.5;
    await tester.tapAt(
      tester.getTopLeft(staffFinder) + staff.staffToLocal(center),
    );
    await tester.pumpAndSettle();
    expect(staff.highlightedIds, hasLength(1));
  });

  testWidgets('the gallery corpus scrolls to the end without exceptions',
      (tester) async {
    await tester.pumpWidget(const PartituraExampleApp());
    await tester.pumpAndSettle();

    final lastTitle = galleryItems.last.title;
    await tester.scrollUntilVisible(
      find.text(lastTitle),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(lastTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duration picker controls the placed note value', (tester) async {
    await tester.pumpWidget(const PartituraExampleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interactive'));
    await tester.pumpAndSettle();

    final staffFinder = find.bySubtype<StaffView>().first;
    final staff = tester.renderObject<RenderStaffView>(staffFinder);

    Future<void> place(double y) async {
      final layout = staff.scoreLayout!;
      final x = (layout.measureRegions.first.startX + layout.width) / 2;
      await tester.tapAt(
        tester.getTopLeft(staffFinder) + staff.staffToLocal(math.Point(x, y)),
      );
      await tester.pumpAndSettle();
    }

    // Default quarter note.
    await place(4.0);
    // Switch to half note (second segment of the duration picker; the
    // musical-symbol labels are decomposed Unicode, so find structurally).
    final durationTexts = find.descendant(
      of: find.byType(SegmentedButton<NoteDuration>),
      matching: find.byType(Text),
    );
    await tester.tap(durationTexts.at(1));
    await tester.pumpAndSettle();
    await place(3.0);

    final glyphs = staff.scoreLayout!.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName.startsWith('notehead'))
        .map((g) => g.smuflName)
        .toList();
    expect(glyphs, contains('noteheadBlack'));
    expect(glyphs, contains('noteheadHalf'));
  });

  testWidgets('clef switch redraws in bass; Clear empties the board',
      (tester) async {
    await tester.pumpWidget(const PartituraExampleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interactive'));
    await tester.pumpAndSettle();

    final staffFinder = find.bySubtype<StaffView>().first;
    final staff = tester.renderObject<RenderStaffView>(staffFinder);

    GlyphPrimitive clefGlyph() =>
        staff.scoreLayout!.primitives.whereType<GlyphPrimitive>().first;
    expect(clefGlyph().smuflName, 'gClef');

    await tester.tap(find.text('Bass'));
    await tester.pumpAndSettle();
    expect(clefGlyph().smuflName, 'fClef');

    // Place a note, then Clear removes it.
    final layout = staff.scoreLayout!;
    final x = (layout.measureRegions.first.startX + layout.width) / 2;
    await tester.tapAt(
      tester.getTopLeft(staffFinder) + staff.staffToLocal(math.Point(x, 4.0)),
    );
    await tester.pumpAndSettle();
    expect(staff.scoreLayout!.regions, hasLength(1));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(staff.scoreLayout!.regions, isEmpty);
  });
}
