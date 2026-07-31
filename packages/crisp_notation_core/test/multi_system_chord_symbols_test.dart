import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Chord symbols must survive system slicing.
///
/// `_slice` rebuilds a per-system `Score` by forwarding ~40 span/attachment
/// lists, each filtered to the ids in that slice. `chordSymbols` was missing
/// from that list, so every multi-system, grand-staff, multi-part and paged
/// render dropped them — which is every score view an app puts in front of a
/// reader. Only the single-system `StaffView` path ever showed them.
///
/// `annotation_test.dart` has had the exact analogous test ("each system keeps
/// exactly its own annotations") all along; chord symbols simply never got one,
/// which is why the omission survived. The assertions run through to the
/// laid-out PRIMITIVES rather than stopping at the sliced model, because a
/// model-level check would also pass if the list were forwarded with its ids
/// left unfiltered — and an unresolvable id makes `_layoutAnnotations` throw.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  /// Four bars, with a chord symbol on the first note of each.
  Score charted() {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | c4:w',
    );
    final firstOfBar = [
      for (final m in score.measures)
        m.elements.whereType<NoteElement>().first.id!,
    ];
    const roots = [Step.c, Step.f, Step.g, Step.c];
    return score.copyWith(chordSymbols: [
      for (var i = 0; i < firstOfBar.length; i++)
        ChordSymbol(firstOfBar[i], Pitch(roots[i]), ChordSymbolKind.major),
    ]);
  }

  List<String> chordTextsOf(ScoreLayout layout) => layout.primitives
      .whereType<TextPrimitive>()
      .map((p) => p.text)
      .where((t) => RegExp(r'^[A-G]').hasMatch(t))
      .toList();

  test('a single system shows its chord symbols (the path that always worked)',
      () {
    final layout = const LayoutEngine().layout(charted(), settings);
    expect(chordTextsOf(layout), ['C', 'F', 'G', 'C']);
  });

  test('a multi-system layout keeps every chord symbol', () {
    final multi = layoutSystems(charted(), settings, maxWidth: 35);
    // The premise: this really did split. Without it the test proves nothing.
    expect(multi.systems.length, greaterThan(1),
        reason: 'maxWidth too generous — slicing was never exercised');

    final all = multi.systems.expand((s) => chordTextsOf(s.layout)).toList();
    expect(all, ['C', 'F', 'G', 'C']);
  });

  test('each system keeps exactly its own symbols, none duplicated', () {
    final multi = layoutSystems(charted(), settings, maxWidth: 35);
    final total = multi.systems
        .map((s) => chordTextsOf(s.layout).length)
        .reduce((a, b) => a + b);
    expect(total, 4, reason: 'each chord belongs to exactly one system');
  });

  test('a symbol on a note in a later system does not throw', () {
    // The failure mode a naive "just forward the list" fix would produce:
    // system 1 receives a symbol whose note it never lays out.
    expect(
      () => layoutSystems(charted(), settings, maxWidth: 35),
      returnsNormally,
    );
  });

  test('a score with no chord symbols is unaffected', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5',
    );
    final multi = layoutSystems(score, settings, maxWidth: 35);
    expect(multi.systems.expand((s) => chordTextsOf(s.layout)), isEmpty);
  });
}
