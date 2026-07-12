import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.2: alto and tenor (C) clefs — theory positions and layout.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<GlyphPrimitive> glyphsNamed(ScoreLayout layout, String name) =>
    layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName == name)
        .toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('theory: staff positions', () {
    test('middle C sits on the clef line of both C clefs', () {
      expect(const Pitch(Step.c).staffPosition(Clef.alto), 4); // middle line
      expect(const Pitch(Step.c).staffPosition(Clef.tenor), 6); // 4th line
    });

    test('bottom lines: F3 in alto, D3 in tenor', () {
      expect(const Pitch(Step.f, octave: 3).staffPosition(Clef.alto), 0);
      expect(const Pitch(Step.d, octave: 3).staffPosition(Clef.tenor), 0);
    });

    test('pitchAt inverts staffPosition for the new clefs too', () {
      for (final clef in [Clef.alto, Clef.tenor]) {
        for (var position = -6; position <= 14; position++) {
          expect(
            clef.pitchAt(position).staffPosition(clef),
            position,
            reason: '$clef position $position',
          );
        }
      }
      expect(Clef.alto.pitchAt(4), const Pitch(Step.c));
      expect(Clef.tenor.pitchAt(6), const Pitch(Step.c));
    });

    test('viola open strings land where alto-clef readers expect', () {
      // C3 second ledger below; G3 first space; D4 third space; A4 the
      // space just above the staff — no ledger line needed.
      expect(const Pitch(Step.c, octave: 3).staffPosition(Clef.alto), -3);
      expect(const Pitch(Step.g, octave: 3).staffPosition(Clef.alto), 1);
      expect(const Pitch(Step.d).staffPosition(Clef.alto), 5);
      expect(const Pitch(Step.a).staffPosition(Clef.alto), 9);
    });
  });

  group('layout: C clef anchoring', () {
    test('alto: cClef anchored on the middle line (y = 2)', () {
      final layout = layoutOf(Score.simple(clef: Clef.alto, notes: 'c4:q'));
      final clef = glyphsNamed(layout, SmuflGlyph.cClef).single;
      expect(clef.position.y, 2.0);
      expect(clef.elementId, isNull);
    });

    test('tenor: cClef anchored on the fourth line (y = 1)', () {
      final layout = layoutOf(Score.simple(clef: Clef.tenor, notes: 'c4:q'));
      final clef = glyphsNamed(layout, SmuflGlyph.cClef).single;
      expect(clef.position.y, 1.0);
    });

    test('noteheads land on clef-relative positions', () {
      // C4 in alto sits on the middle line (y=2); in tenor on the 4th
      // line (y=1).
      final alto = layoutOf(Score.simple(clef: Clef.alto, notes: 'c4:q'));
      expect(
        glyphsNamed(alto, SmuflGlyph.noteheadBlack).single.position.y,
        2.0,
      );
      final tenor = layoutOf(Score.simple(clef: Clef.tenor, notes: 'c4:q'));
      expect(
        glyphsNamed(tenor, SmuflGlyph.noteheadBlack).single.position.y,
        1.0,
      );
    });
  });

  group('layout: key signatures in C clefs', () {
    List<double> signatureYs(Clef clef, int fifths) {
      final layout = layoutOf(Score(
        clef: clef,
        keySignature: KeySignature(fifths),
        measures: [
          Measure([
            NoteElement.note(clef.pitchAt(4), NoteDuration.whole, id: 'n'),
          ]),
        ],
      ));
      final glyph =
          fifths > 0 ? SmuflGlyph.accidentalSharp : SmuflGlyph.accidentalFlat;
      return glyphsNamed(layout, glyph)
          .where((g) => g.elementId == null)
          .map((g) => g.position.y)
          .toList();
    }

    test('alto sharps sit one third below treble', () {
      final treble = signatureYs(Clef.treble, 7);
      final alto = signatureYs(Clef.alto, 7);
      expect(alto, [for (final y in treble) y + 0.5]);
      // Positions [7,4,8,5,2,6,3] -> y = (8-p)/2.
      expect(alto, [0.5, 2.0, 0.0, 1.5, 3.0, 1.0, 2.5]);
    });

    test('alto flats sit one third below treble', () {
      final treble = signatureYs(Clef.treble, -7);
      final alto = signatureYs(Clef.alto, -7);
      expect(alto, [for (final y in treble) y + 0.5]);
    });

    test('tenor sharps use the subterranean-F pattern', () {
      // Positions [2,6,3,7,4,8,5]: F#3 starts low, then C#4 high.
      expect(signatureYs(Clef.tenor, 7), [3.0, 1.0, 2.5, 0.5, 2.0, 0.0, 1.5]);
    });

    test('tenor flats sit one third above treble', () {
      final treble = signatureYs(Clef.treble, -7);
      final tenor = signatureYs(Clef.tenor, -7);
      expect(tenor, [for (final y in treble) y - 0.5]);
    });

    test('every signature stays within the staff in every clef', () {
      for (final clef in Clef.values) {
        for (var fifths = -7; fifths <= 7; fifths++) {
          if (fifths == 0) continue;
          for (final y in signatureYs(clef, fifths)) {
            // Bass 7-flat Fb legitimately sits on the first ledger below.
            expect(y, inInclusiveRange(-0.5, 4.5),
                reason: '$clef fifths $fifths y $y');
          }
        }
      }
    });
  });

  group('layout: everything else generalizes', () {
    test('beaming, stems and accidentals work in C clefs', () {
      final layout = layoutOf(Score.simple(
        clef: Clef.alto,
        keySignature: const KeySignature(-1),
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:e d4 e4 f4 | g3+c4:h bn3:q r:q',
      ));
      // Four eighths filling the first half of 4/4 merge into one beam.
      expect(
        layout.primitives.whereType<BeamPrimitive>(),
        hasLength(1),
      );
      // The Bn needs its natural (key has Bb).
      final naturals = glyphsNamed(layout, SmuflGlyph.accidentalNatural)
          .where((g) => g.elementId != null);
      expect(naturals, hasLength(1));
      expect(layout.regions, hasLength(7));
    });

    test('deterministic in the new clefs', () {
      Score score() => Score.simple(
            clef: Clef.tenor,
            keySignature: const KeySignature(3),
            timeSignature: TimeSignature.threeFour,
            notes: 'c4:q b3+d4 a3 | g#3:h.',
          );
      final a = layoutOf(score());
      final b = layoutOf(score());
      expect(
        a.primitives.map((p) => p.toString()).join('\n'),
        b.primitives.map((p) => p.toString()).join('\n'),
      );
    });
  });
}
