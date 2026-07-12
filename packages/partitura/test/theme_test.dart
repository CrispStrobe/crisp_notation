import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

void main() {
  group('PartituraTheme', () {
    test('value equality covers every field', () {
      const base = PartituraTheme();
      expect(base, const PartituraTheme());
      expect(base.hashCode, const PartituraTheme().hashCode);
      expect(base, isNot(const PartituraTheme(staffColor: Color(0xFF000001))));
      expect(base, isNot(const PartituraTheme(noteColor: Color(0xFF000001))));
      expect(
        base,
        isNot(const PartituraTheme(highlightColor: Color(0xFF000001))),
      );
      expect(base, isNot(const PartituraTheme(kidMode: true)));
      expect(base, isNot(const PartituraTheme(hitSlop: 2)));
      expect(base, isNot(const PartituraTheme(lineBoost: 2)));
      expect(
        base,
        isNot(const PartituraTheme(elementColors: {'x': Color(0xFF000001)})),
      );
      expect(
        const PartituraTheme(elementColors: {'x': Color(0xFF000001)}),
        const PartituraTheme(elementColors: {'x': Color(0xFF000001)}),
      );
    });

    test('copyWith replaces exactly the given fields', () {
      const original = PartituraTheme.kids;
      final recolored = original.copyWith(noteColor: const Color(0xFF112233));
      expect(recolored.noteColor, const Color(0xFF112233));
      expect(recolored.kidMode, original.kidMode);
      expect(recolored.hitSlop, original.hitSlop);
      expect(recolored.lineBoost, original.lineBoost);
      expect(recolored.highlightColor, original.highlightColor);

      final full = original.copyWith(
        staffColor: const Color(0xFF000001),
        noteColor: const Color(0xFF000002),
        highlightColor: const Color(0xFF000003),
        elementColors: const {'a': Color(0xFF000004)},
        kidMode: false,
        hitSlop: 0.25,
        lineBoost: 2.0,
      );
      expect(full.staffColor, const Color(0xFF000001));
      expect(full.noteColor, const Color(0xFF000002));
      expect(full.highlightColor, const Color(0xFF000003));
      expect(full.elementColors, const {'a': Color(0xFF000004)});
      expect(full.kidMode, isFalse);
      expect(full.hitSlop, 0.25);
      expect(full.lineBoost, 2.0);
      // copyWith with no arguments is identity by value.
      expect(original.copyWith(), original);
    });

    test('presets encode the kid-mode ergonomics contract', () {
      expect(PartituraTheme.standard.kidMode, isFalse);
      expect(PartituraTheme.kids.kidMode, isTrue);
      expect(
        PartituraTheme.kids.hitSlop,
        greaterThan(PartituraTheme.standard.hitSlop),
      );
      expect(
        PartituraTheme.kids.lineBoost,
        greaterThan(PartituraTheme.standard.lineBoost),
      );
    });
  });

  group('GhostNote', () {
    test('value equality', () {
      const a = GhostNote(
        xSpaces: 5,
        staffPosition: 2,
        duration: NoteDuration.quarter,
      );
      expect(
        a,
        const GhostNote(
          xSpaces: 5,
          staffPosition: 2,
          duration: NoteDuration.quarter,
        ),
      );
      expect(
        a.hashCode,
        const GhostNote(
          xSpaces: 5,
          staffPosition: 2,
          duration: NoteDuration.quarter,
        ).hashCode,
      );
      expect(
        a,
        isNot(const GhostNote(
          xSpaces: 6,
          staffPosition: 2,
          duration: NoteDuration.quarter,
        )),
      );
      expect(
        a,
        isNot(const GhostNote(
          xSpaces: 5,
          staffPosition: 3,
          duration: NoteDuration.quarter,
        )),
      );
      expect(
        a,
        isNot(const GhostNote(
          xSpaces: 5,
          staffPosition: 2,
          duration: NoteDuration.half,
        )),
      );
    });
  });

  group('StaffTarget', () {
    test('value equality and toString', () {
      const target = StaffTarget(staffPosition: 4, measureIndex: 1);
      expect(target, const StaffTarget(staffPosition: 4, measureIndex: 1));
      expect(
        target,
        isNot(const StaffTarget(staffPosition: 5, measureIndex: 1)),
      );
      expect(
        target,
        isNot(const StaffTarget(staffPosition: 4, measureIndex: 0)),
      );
      expect(target.toString(), contains('position 4'));
      expect(target.toString(), contains('measure 1'));
    });

    test('pitchFor covers the full quantization range in both clefs', () {
      for (final clef in Clef.values) {
        for (var position = -6; position <= 14; position++) {
          final target = StaffTarget(staffPosition: position, measureIndex: 0);
          final pitch = target.pitchFor(clef);
          expect(pitch.staffPosition(clef), position,
              reason: '$clef position $position');
          expect(pitch.alter, 0);
          expect(
            target.pitchFor(clef, preferredAlter: 1).alter,
            1,
            reason: '$clef position $position sharp',
          );
        }
      }
    });
  });
}
