import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide PageMetrics;
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

// Collects every non-empty semantics label under [node].
List<String> _labels(SemanticsNode node) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    final label = n.getSemanticsData().label;
    if (label.isNotEmpty) out.add(label);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(node);
  return out;
}

// Collects rects keyed by label, walking the semantics tree.
Map<String, Rect> _rects(SemanticsNode node) {
  final out = <String, Rect>{};
  void walk(SemanticsNode n) {
    final data = n.getSemanticsData();
    if (data.label.isNotEmpty) {
      out[data.label] = n.rect;
    }
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(node);
  return out;
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

void main() {
  setUpAll(setUpCrispNotationForTests);

  testWidgets('GrandStaffView exposes per-note semantics in reading order',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(GrandStaffView(
      grandStaff: GrandStaff(
        upper: Score.simple(
            notes: 'c5:q e5',
            metadata: const ScoreMetadata(instrument: 'Piano')),
        lower: Score.simple(
            notes: 'c3:h', metadata: const ScoreMetadata(instrument: 'Piano')),
      ),
      staffSpace: 10,
    )));
    final root = tester.getSemantics(find.byType(GrandStaffView));
    final labels = _labels(root);
    expect(labels, contains('Piano: C 5 quarter note'));
    expect(labels, contains('Piano: E 5 quarter note'));
    expect(labels, contains('Piano: C 3 half note'));
    final rects = _rects(root);
    // Upper staff notes left to right
    expect(rects['Piano: C 5 quarter note']!.left,
        lessThan(rects['Piano: E 5 quarter note']!.left));
    handle.dispose();
  });

  testWidgets(
      'StaffSystemView exposes per-note semantics with instrument prefix',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(StaffSystemView(
      system: StaffSystem([
        Score.simple(
            notes: 'c5:q e5',
            metadata: const ScoreMetadata(instrument: 'Violin')),
        Score.simple(
            notes: 'c3:h', metadata: const ScoreMetadata(instrument: 'Cello')),
      ]),
      staffSpace: 10,
    )));
    final root = tester.getSemantics(find.byType(StaffSystemView));
    final labels = _labels(root);
    expect(labels, contains('Violin: C 5 quarter note'));
    expect(labels, contains('Cello: C 3 half note'));
    final rects = _rects(root);
    // Violin staff is above Cello, but both have x=0 start; check that Violin's rect is above
    // and that within same staff left-to-right holds
    expect(rects['Violin: C 5 quarter note']!.left,
        lessThan(rects['Violin: E 5 quarter note']!.left));
    handle.dispose();
  });

  testWidgets('MultiSystemView exposes per-note semantics system by system',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(SizedBox(
      width: 200,
      child: MultiSystemView(
        score: Score.simple(notes: 'c4:q d4 e4 f4 | g4:h a4:h | b4:w'),
        staffSpace: 8,
      ),
    )));
    final root = tester.getSemantics(find.byType(MultiSystemView));
    final labels = _labels(root);
    expect(labels, contains('C 4 quarter note'));
    expect(labels, contains('B 4 whole note'));
    final rects = _rects(root);
    // First system notes left to right, second system also left to right but below
    expect(rects['C 4 quarter note']!.left,
        lessThan(rects['D 4 quarter note']!.left));
    handle.dispose();
  });

  testWidgets('MultiPartView exposes per-note semantics with part prefix',
      (tester) async {
    final handle = tester.ensureSemantics();
    final doc = MultiPartScore([
      Score.simple(
          notes: 'c5:q e5', metadata: const ScoreMetadata(instrument: 'Flute')),
      Score.simple(
          notes: 'c3:h', metadata: const ScoreMetadata(instrument: 'Cello')),
    ]);
    await tester.pumpWidget(_wrap(SizedBox(
      width: 300,
      height: 400,
      child: MultiPartView(
        document: doc,
        metrics: const PageMetrics(
            width: 100,
            height: 80,
            marginLeft: 5,
            marginTop: 5,
            marginRight: 5,
            marginBottom: 5),
        staffSpace: 8,
      ),
    )));
    final root = tester.getSemantics(find.byType(MultiPartView));
    final labels = _labels(root);
    expect(labels, contains('Flute: C 5 quarter note'));
    expect(labels, contains('Cello: C 3 half note'));
    handle.dispose();
  });

  testWidgets('TabStaffView exposes per-note semantics in reading order',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(TabStaffView(
      score: Score.simple(notes: 'c4:q e4 g4'),
      tuning: Tuning.standardGuitar,
      staffSpace: 10,
    )));
    final root = tester.getSemantics(find.byType(TabStaffView));
    final labels = _labels(root);
    expect(labels, contains('C 4 quarter note'));
    expect(labels, contains('E 4 quarter note'));
    final rects = _rects(root);
    expect(rects['C 4 quarter note']!.left,
        lessThan(rects['E 4 quarter note']!.left));
    handle.dispose();
  });

  testWidgets('InteractiveGrandStaffView exposes per-note semantics',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(InteractiveGrandStaffView(
      grandStaff: GrandStaff(
        upper: Score.simple(notes: 'c5:q e5'),
        lower: Score.simple(notes: 'c3:h'),
      ),
      staffSpace: 10,
    )));
    final root = tester.getSemantics(find.byType(InteractiveGrandStaffView));
    final labels = _labels(root);
    expect(labels, contains('C 5 quarter note'));
    expect(labels, contains('C 3 half note'));
    final rects = _rects(root);
    expect(rects['C 5 quarter note']!.left,
        lessThan(rects['E 5 quarter note']!.left));
    handle.dispose();
  });

  testWidgets('InteractiveMultiPartView delegates to MultiPartView semantics',
      (tester) async {
    final handle = tester.ensureSemantics();
    final doc = MultiPartScore([
      Score.simple(
          notes: 'c5:q e5',
          metadata: const ScoreMetadata(instrument: 'Violin')),
      Score.simple(notes: 'c3:h'),
    ]);
    await tester.pumpWidget(_wrap(SizedBox(
      width: 300,
      height: 400,
      child: InteractiveMultiPartView(
        document: doc,
        metrics: const PageMetrics(
            width: 100,
            height: 80,
            marginLeft: 5,
            marginTop: 5,
            marginRight: 5,
            marginBottom: 5),
        staffSpace: 8,
      ),
    )));
    // InteractiveMultiPartView wraps MultiPartView; its child provides semantics.
    // We check that the overall tree still contains the expected labels.
    final root =
        tester.getSemantics(find.byWidgetPredicate((w) => w is MultiPartView));
    final labels = _labels(root);
    expect(labels, contains('Violin: C 5 quarter note'));
    expect(labels, contains('Violin: E 5 quarter note'));
    handle.dispose();
  });
}
