import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

/// Live tests of the asset-loading path: `Bravura.load()` served by a
/// mocked asset bundle backed by the real metadata file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assetKey = 'packages/partitura/assets/smufl/bravura_metadata.json';
  var bundleHits = 0;

  setUp(() {
    Bravura.debugReset();
    // rootBundle caches strings across tests; force a real bundle read.
    rootBundle.evict(assetKey);
    bundleHits = 0;
    final bytes = File('assets/smufl/bravura_metadata.json').readAsBytesSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (key == assetKey) {
        bundleHits++;
        return ByteData.view(bytes.buffer);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    Bravura.debugReset();
  });

  test('load() parses the bundled metadata from the asset bundle', () async {
    expect(Bravura.metadataOrNull, isNull);
    final metadata = await Bravura.load();
    expect(Bravura.metadataOrNull, same(metadata));
    // Real engraving values arrived, not fallbacks.
    expect(metadata.engravingDefault('staffLineThickness', orElse: -1), 0.13);
    expect(metadata.bBoxOf(SmuflGlyph.gClef).height, greaterThan(6));
    expect(metadata.anchorsOf(SmuflGlyph.noteheadBlack).stemUpSE, isNotNull);
  });

  test('load() caches: one bundle read, later calls return the instance',
      () async {
    final first = await Bravura.load();
    final second = await Bravura.load();
    final third = Bravura.metadataOrNull;
    expect(identical(first, second), isTrue);
    expect(identical(first, third), isTrue);
    expect(bundleHits, 1);
  });

  test('a failed load is not cached: the next call retries', () async {
    // First attempt: the bundle "misses" the asset.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async => null);
    await expectLater(Bravura.load(), throwsA(isA<FlutterError>()));
    expect(Bravura.metadataOrNull, isNull);

    // Bundle recovers: the retry succeeds instead of replaying the failure.
    final bytes = File('assets/smufl/bravura_metadata.json').readAsBytesSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      return key == assetKey ? ByteData.view(bytes.buffer) : null;
    });
    rootBundle.evict(assetKey);
    final metadata = await Bravura.load();
    expect(metadata.engravingDefault('staffLineThickness', orElse: -1), 0.13);
  });

  test('concurrent loads share one in-flight request', () async {
    final results = await Future.wait([
      Bravura.load(),
      Bravura.load(),
      Bravura.load(),
    ]);
    expect(identical(results[0], results[1]), isTrue);
    expect(identical(results[1], results[2]), isTrue);
    expect(bundleHits, 1);
  });

  testWidgets('StaffView self-heals: empty first frame, painted after load',
      (tester) async {
    // No metadata yet: the widget lays out with fallback size and kicks
    // off the load.
    // The whole sequence runs inside runAsync: the widget's first layout
    // kicks off Bravura.load(), and rootBundle decodes large assets on a
    // background isolate — which never completes under the test's
    // fake-async clock.
    late RenderStaffView renderObject;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: StaffView(
              score: Score.simple(notes: 'c4:q d4'),
              staffSpace: 12,
            ),
          ),
        ),
      );
      renderObject =
          tester.renderObject<RenderStaffView>(find.byType(StaffView));
      // First frame: metadata still loading, nothing laid out.
      expect(renderObject.scoreLayout, isNull);
      await Bravura.load();
    });
    await tester.pump();
    expect(renderObject.scoreLayout, isNotNull);
    expect(renderObject.scoreLayout!.regions, hasLength(2));
  });
}
