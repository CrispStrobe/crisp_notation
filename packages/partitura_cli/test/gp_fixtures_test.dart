import 'dart:io';

import 'package:partitura_cli/src/gp_container.dart';
import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Regression tests against real Guitar Pro binaries (vendored from alphaTab,
/// MPL-2.0 — see test/data/gp/README.md). These lock the whole read path for
/// every container format: GP5 binary, GP6 `.gpx` (BCFZ/BCFS), GP7/8 `.gp`.
void main() {
  const dir = 'test/data/gp';

  int noteCount(Score s) {
    var notes = 0;
    for (final m in s.measures) {
      for (final e in m.elements) {
        if (e is NoteElement) notes++;
      }
    }
    return notes;
  }

  Score gp5(String name) =>
      gp5ToScore(File('$dir/$name').readAsBytesSync());
  Score gpx(String name) =>
      scoreFromGpif(readGpifFromGpx(File('$dir/$name').readAsBytesSync()));
  Score gp(String name) =>
      scoreFromGpif(readGpifFromGp(File('$dir/$name').readAsBytesSync()));

  group('GP5 (binary)', () {
    test('chords: two measures, eight notes', () {
      final s = gp5('chords.gp5');
      expect(s.measures, hasLength(2));
      expect(noteCount(s), 8);
    });

    test('bends: three notes each carry a bend', () {
      final s = gp5('bends.gp5');
      expect(s.measures, hasLength(2));
      expect(noteCount(s), 3);
      expect(s.bends, hasLength(3));
    });
  });

  group('GP6 (.gpx)', () {
    test('chords: five measures, eight notes', () {
      final s = gpx('chords.gpx');
      expect(s.measures, hasLength(5));
      expect(noteCount(s), 8);
    });

    test('slides: five glissandos', () {
      final s = gpx('slides.gpx');
      expect(s.measures, hasLength(2));
      expect(noteCount(s), 8);
      expect(s.glissandos, hasLength(5));
    });
  });

  group('GP7/8 (.gp)', () {
    test('chords: five measures, eight notes', () {
      final s = gp('chords.gp');
      expect(s.measures, hasLength(5));
      expect(noteCount(s), 8);
    });

    test('bends: three notes each carry a bend', () {
      final s = gp('bends.gp');
      expect(s.measures, hasLength(2));
      expect(noteCount(s), 3);
      expect(s.bends, hasLength(3));
    });
  });
}
