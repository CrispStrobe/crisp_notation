/// The layout engine: turns a [Score] into a [ScoreLayout]
/// (HANDOVER.md §4.2, rules 1–14).
library;

import 'dart:math';

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../smufl/smufl_metadata.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';
import 'layout_settings.dart';
import 'score_layout.dart';

/// Pure, deterministic single-staff layout.
///
/// The same [Score] and [LayoutSettings] always produce an identical
/// [ScoreLayout]: no randomness, no clock, no platform dependence. All
/// output coordinates are in staff spaces (see [ScoreLayout]).
class LayoutEngine {
  /// Creates a layout engine.
  const LayoutEngine();

  /// Lays out [score] according to [settings].
  ScoreLayout layout(Score score, LayoutSettings settings) =>
      _LayoutBuilder(score, settings).build();
}

/// y-coordinate of a staff position (0 = bottom line → y = 4; y grows down).
double _yOf(num staffPosition) => (8 - staffPosition) / 2;

/// Mutable bounding-box accumulator.
class _Bounds {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;

  void expand(double left, double top, double right, double bottom) {
    if (left < minX) minX = left;
    if (top < minY) minY = top;
    if (right > maxX) maxX = right;
    if (bottom > maxY) maxY = bottom;
  }

  bool get isEmpty => minX > maxX;

  Rectangle<double> toRectangle() =>
      Rectangle(minX, minY, maxX - minX, maxY - minY);
}

/// A beamed group: indices into a measure's element list, plus direction.
class _BeamGroup {
  final List<int> indices;
  final bool stemsDown;
  _BeamGroup(this.indices, {required this.stemsDown});
}

/// Deferred stem/flag data for one beamed note, collected while walking the
/// measure and consumed when the group's beam geometry is computed.
class _BeamedNote {
  final String? elementId;
  final double stemX;

  /// y where the stem meets the notehead (anchor of the outermost notehead
  /// on the stem's far side).
  final double attachY;

  /// y of the outermost notehead on the beam side.
  final double refY;

  /// Beam levels this note needs (1 = eighth … 4 = sixty-fourth).
  final int beamCount;

  _BeamedNote({
    required this.elementId,
    required this.stemX,
    required this.attachY,
    required this.refY,
    required this.beamCount,
  });
}

/// Rendered notehead geometry of one element, kept for the tie pass.
/// Rests participate with an empty head list (a tie cannot cross a rest).
class _TieInfo {
  final NoteElement? note;
  final String? id;
  final bool stemsDown;

  /// Horizontal ink extent of the notehead/rest glyphs.
  final double left;
  final double right;

  /// Per pitch: the notehead column's left/right x and its center y.
  final List<(Pitch, double, double, double)> heads;

  _TieInfo({
    required this.note,
    required this.id,
    required this.stemsDown,
    required this.left,
    required this.right,
    required this.heads,
  });
}

class _LayoutBuilder {
  final Score score;
  final LayoutSettings s;
  SmuflMetadata get meta => s.metadata;

  final List<LayoutPrimitive> _primitives = [];
  final Map<String, _Bounds> _elementBounds = {};
  final List<MeasureRegion> _measureRegions = [];
  final List<_TieInfo> _tieInfos = [];
  final _Bounds _ink = _Bounds();

  double _x = 0;

  // Mid-score changes (v0.3.8) update these as measures are laid out.
  late Clef _clef = score.clef;
  late KeySignature _key = score.keySignature;
  late TimeSignature? _time = score.timeSignature;

  _LayoutBuilder(this.score, this.s);

  // Key signature accidental staff positions per clef, in writing order.
  // Bass/alto shift the treble pattern down 2/1 positions; the tenor sharp
  // pattern is its own shape (F# starts low to stay inside the staff).
  static const Map<Clef, List<int>> _sharpPositions = {
    Clef.treble: [8, 5, 9, 6, 3, 7, 4],
    Clef.bass: [6, 3, 7, 4, 1, 5, 2],
    Clef.alto: [7, 4, 8, 5, 2, 6, 3],
    Clef.tenor: [2, 6, 3, 7, 4, 8, 5],
  };
  static const Map<Clef, List<int>> _flatPositions = {
    Clef.treble: [4, 7, 3, 6, 2, 5, 1],
    Clef.bass: [2, 5, 1, 4, 0, 3, -1],
    Clef.alto: [3, 6, 2, 5, 1, 4, 0],
    Clef.tenor: [5, 8, 4, 7, 3, 6, 2],
  };

  // log2(dot factor) for 0..2 dots: 1, 3/2, 7/4.
  static const List<double> _dotLog2 = [
    0.0,
    0.5849625007211562,
    0.8073549220576042
  ];

  ScoreLayout build() {
    _x = s.leadingPadding;
    _layoutClef();
    _layoutKeySignature();
    _layoutTimeSignature();

    for (var i = 0; i < score.measures.length; i++) {
      final measure = score.measures[i];
      _applyMeasureChanges(measure);
      if (measure.startRepeat) _addStartRepeat();
      final startX = _x;
      _layoutMeasure(measure);
      _measureRegions.add(MeasureRegion(i, startX: startX, endX: _x));
      if (measure.volta != null) {
        _addVolta(measure.volta!, startX, _x);
      }
      if (measure.endRepeat) {
        _addEndRepeat();
      } else if (i < score.measures.length - 1) {
        _addBarline();
      }
    }
    _layoutTies();
    _layoutSlurs();
    _layoutDynamics();
    final width = _addFinalBarline();

    // Staff lines span the full width; paint them first.
    final staffLines = [
      for (var line = 0; line < 5; line++)
        LinePrimitive(
          Point(0, line.toDouble()),
          Point(width, line.toDouble()),
          thickness: s.staffLineThickness,
        ),
    ];
    _primitives.insertAll(0, staffLines);
    _ink.expand(
      0,
      -s.staffLineThickness / 2,
      width,
      4 + s.staffLineThickness / 2,
    );

    final top = _ink.minY - s.verticalPadding;
    final bottom = _ink.maxY + s.verticalPadding;
    return ScoreLayout(
      width: width,
      height: bottom - top,
      top: top,
      primitives: List.unmodifiable(_primitives),
      regions: List.unmodifiable([
        for (final entry in _elementBounds.entries)
          ElementRegion(entry.key, entry.value.toRectangle()),
      ]),
      measureRegions: List.unmodifiable(_measureRegions),
    );
  }

  // ---------------------------------------------------------------- helpers

  void _addGlyph(
    String name,
    double x,
    double y, {
    String? elementId,
    double scale = 1.0,
  }) {
    _primitives.add(
      GlyphPrimitive(name, Point(x, y), scale: scale, elementId: elementId),
    );
    final box = meta.bBoxOf(name);
    // SMuFL bounding boxes are y-up relative to the origin; flip.
    _expand(
      elementId,
      x + box.swX * scale,
      y - box.neY * scale,
      x + box.neX * scale,
      y - box.swY * scale,
    );
  }

  void _addLine(
    Point<double> from,
    Point<double> to,
    double thickness, {
    String? elementId,
  }) {
    _primitives.add(
      LinePrimitive(from, to, thickness: thickness, elementId: elementId),
    );
    final h = thickness / 2;
    _expand(
      elementId,
      min(from.x, to.x) - h,
      min(from.y, to.y) - h,
      max(from.x, to.x) + h,
      max(from.y, to.y) + h,
    );
  }

  void _addCurve(
    Point<double> start,
    Point<double> control1,
    Point<double> control2,
    Point<double> end,
    double thickness,
  ) {
    _primitives.add(
      CurvePrimitive(start, control1, control2, end, thickness: thickness),
    );
    // The control polygon bounds the Bézier.
    final xs = [start.x, control1.x, control2.x, end.x];
    final ys = [start.y, control1.y, control2.y, end.y];
    final h = thickness / 2;
    _expand(
      null,
      xs.reduce(min) - h,
      ys.reduce(min) - h,
      xs.reduce(max) + h,
      ys.reduce(max) + h,
    );
  }

  void _addBeam(
    Point<double> start,
    Point<double> end,
    double thickness,
  ) {
    _primitives.add(BeamPrimitive(start, end, thickness: thickness));
    final h = thickness / 2;
    _expand(
      null,
      min(start.x, end.x),
      min(start.y, end.y) - h,
      max(start.x, end.x),
      max(start.y, end.y) + h,
    );
  }

  void _expand(
    String? elementId,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    _ink.expand(left, top, right, bottom);
    if (elementId != null) {
      _elementBounds
          .putIfAbsent(elementId, _Bounds.new)
          .expand(left, top, right, bottom);
    }
  }

  double _glyphWidth(String name) => meta.bBoxOf(name).width;

  // ------------------------------------------------------- leading elements

  /// Rule 1: clef anchored on its reference line (gClef on G4's line,
  /// fClef on F3's, cClef on C4's).
  void _layoutClef() {
    final (glyph, position) = switch (_clef) {
      Clef.treble => (SmuflGlyph.gClef, 2), // G4
      Clef.bass => (SmuflGlyph.fClef, 6), // F3
      Clef.alto => (SmuflGlyph.cClef, 4), // C4 on the middle line
      Clef.tenor => (SmuflGlyph.cClef, 6), // C4 on the fourth line
    };
    _addGlyph(glyph, _x, _yOf(position));
    _x += _glyphWidth(glyph) + s.clefGap;
  }

  /// Rule 2: key signature in standard order at conventional octaves.
  void _layoutKeySignature() {
    final fifths = _key.fifths;
    if (fifths == 0) return;
    final count = fifths.abs();
    final table = fifths > 0 ? _sharpPositions[_clef]! : _flatPositions[_clef]!;
    final glyph =
        fifths > 0 ? SmuflGlyph.accidentalSharp : SmuflGlyph.accidentalFlat;
    final width = _glyphWidth(glyph);
    for (var i = 0; i < count; i++) {
      _addGlyph(glyph, _x, _yOf(table[i]));
      _x += width + s.keyAccidentalGap;
    }
    _x += s.signatureGap - s.keyAccidentalGap;
  }

  /// Rule 3: stacked timeSig digits centered on the staff.
  void _layoutTimeSignature() {
    final time = _time;
    if (time == null) return;
    final numerator = _timeSigGlyphs(time.beats);
    final denominator = _timeSigGlyphs(time.beatUnit);
    final numWidth = _rowWidth(numerator);
    final denWidth = _rowWidth(denominator);
    final groupWidth = max(numWidth, denWidth);
    // SMuFL timeSig digits are vertically centered on their origin; the
    // numerator centers on the space-above-middle line (y=1), the
    // denominator on the space-below-middle line (y=3).
    _addTimeSigRow(numerator, _x + (groupWidth - numWidth) / 2, 1);
    _addTimeSigRow(denominator, _x + (groupWidth - denWidth) / 2, 3);
    _x += groupWidth + s.signatureGap;
  }

  List<String> _timeSigGlyphs(int value) => [
        for (final ch in value.toString().split(''))
          SmuflGlyph.timeSigDigit(int.parse(ch)),
      ];

  double _rowWidth(List<String> glyphs) =>
      glyphs.fold(0.0, (sum, g) => sum + _glyphWidth(g));

  void _addTimeSigRow(List<String> glyphs, double startX, double y) {
    var x = startX;
    for (final glyph in glyphs) {
      // Align the glyph's left ink edge with the cursor.
      _addGlyph(glyph, x - meta.bBoxOf(glyph).swX, y);
      x += _glyphWidth(glyph);
    }
  }

  // ---------------------------------------------------------------- measure

  void _layoutMeasure(Measure measure) {
    _validateTuplets(measure);
    final tieBase = _tieInfos.length;
    final groups = _computeBeamGroups(measure);
    final beamedIndex = <int, _BeamGroup>{
      for (final group in groups)
        for (final index in group.indices) index: group,
    };
    final deferred = <_BeamGroup, List<_BeamedNote>>{};

    // Accidental state: (step, octave) -> alteration written earlier in
    // this measure. Resets every measure (rule 9).
    final written = <(Step, int), int>{};

    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      final log2Adjust = _tupletLog2Adjust(measure, i);
      switch (element) {
        case NoteElement():
          final group = beamedIndex[i];
          final beamed = _layoutNote(
            element,
            written,
            stemsDownOverride: group?.stemsDown,
            deferStem: group != null,
            log2Adjust: log2Adjust,
          );
          if (group != null && beamed != null) {
            deferred.putIfAbsent(group, () => []).add(beamed);
          }
        case RestElement():
          _layoutRest(element, log2Adjust: log2Adjust);
      }
    }

    for (final group in groups) {
      final notes = deferred[group];
      if (notes != null && notes.length >= 2) {
        _layoutBeamGroup(notes, stemsDown: group.stemsDown);
      }
    }
    _layoutArticulations(measure, tieBase);
    _layoutTuplets(measure, tieBase);
  }

  /// v0.3.4: articulation marks on the notehead side (opposite the stem),
  /// stacked outward in enum order; fermatas always go above the element
  /// and outside the staff.
  void _layoutArticulations(Measure measure, int tieBase) {
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      if (element is! NoteElement || element.articulations.isEmpty) {
        continue;
      }
      final info = _tieInfos[tieBase + i];
      final centerX = (info.left + info.right) / 2;
      final above = info.stemsDown; // notehead side = opposite the stem
      final headYs = info.heads.map((h) => h.$4);
      var y = above ? headYs.reduce(min) - 0.75 : headYs.reduce(max) + 0.75;
      for (final articulation in Articulation.values) {
        if (articulation == Articulation.fermata ||
            !element.articulations.contains(articulation)) {
          continue;
        }
        final glyph = SmuflGlyph.articulationGlyph(articulation, above: above);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, y,
            elementId: element.id);
        y += (above ? -1 : 1) * (box.height + 0.45);
      }
      if (element.articulations.contains(Articulation.fermata)) {
        final bounds = element.id == null ? null : _elementBounds[element.id];
        final top = min(bounds?.minY ?? headYs.reduce(min), -0.5);
        final glyph =
            SmuflGlyph.articulationGlyph(Articulation.fermata, above: true);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, top - 0.4,
            elementId: element.id);
      }
    }
  }

  void _validateTuplets(Measure measure) {
    final seen = <int>{};
    for (final span in measure.tuplets) {
      if (span.endIndex >= measure.elements.length) {
        throw ArgumentError(
          '$span exceeds the measure (${measure.elements.length} elements)',
        );
      }
      for (var i = span.startIndex; i <= span.endIndex; i++) {
        if (!seen.add(i)) {
          throw ArgumentError('Tuplet spans overlap at element $i');
        }
      }
    }
  }

  /// log2(normal/actual) for the element's tuplet span; spacing shrinks
  /// tuplet members to their sounding width.
  double _tupletLog2Adjust(Measure measure, int index) {
    for (final span in measure.tuplets) {
      if (span.contains(index)) {
        return log(span.normal / span.actual) / ln2;
      }
    }
    return 0;
  }

  /// v0.3.3: tuplet ratio digit with a bracket, on the stem side of the
  /// group.
  void _layoutTuplets(Measure measure, int tieBase) {
    for (final span in measure.tuplets) {
      final infos = _tieInfos.sublist(
          tieBase + span.startIndex, tieBase + span.endIndex + 1);
      final notes = infos.where((i) => i.note != null).toList();
      final downCount = notes.where((i) => i.stemsDown).length;
      final below = notes.isNotEmpty && downCount * 2 >= notes.length;

      final x1 = infos.first.left - 0.2;
      final x2 = infos.last.right + 0.2;
      double topOf(_TieInfo info) =>
          (info.id == null ? null : _elementBounds[info.id]?.minY) ?? -1.0;
      double bottomOf(_TieInfo info) =>
          (info.id == null ? null : _elementBounds[info.id]?.maxY) ?? 5.0;

      final double bracketY;
      final double hookDir;
      if (below) {
        bracketY = infos.map(bottomOf).reduce(max) + 0.7;
        hookDir = -1;
      } else {
        bracketY = infos.map(topOf).reduce(min) - 0.7;
        hookDir = 1;
      }

      final digits = [
        for (final ch in span.actual.toString().split(''))
          SmuflGlyph.tupletDigit(int.parse(ch)),
      ];
      final digitsWidth = digits.fold(0.0, (sum, g) => sum + _glyphWidth(g));
      final thickness =
          meta.engravingDefault('tupletBracketThickness', orElse: 0.16);
      final midX = (x1 + x2) / 2;
      final gap = digitsWidth / 2 + 0.3;

      _addLine(Point(x1, bracketY), Point(midX - gap, bracketY), thickness);
      _addLine(Point(midX + gap, bracketY), Point(x2, bracketY), thickness);
      _addLine(
          Point(x1, bracketY), Point(x1, bracketY + hookDir * 0.7), thickness);
      _addLine(
          Point(x2, bracketY), Point(x2, bracketY + hookDir * 0.7), thickness);

      var digitX = midX - digitsWidth / 2;
      for (final glyph in digits) {
        _addGlyph(glyph, digitX - meta.bBoxOf(glyph).swX, bracketY + 0.75);
        digitX += _glyphWidth(glyph);
      }
    }
  }

  // ------------------------------------------------------------------ notes

  /// Rules 4–6, 8–11: noteheads, stem, flag, ledger lines, accidentals,
  /// dots, chord clustering. Returns deferred stem data when [deferStem].
  _BeamedNote? _layoutNote(
    NoteElement element,
    Map<(Step, int), int> written, {
    bool? stemsDownOverride,
    bool deferStem = false,
    double log2Adjust = 0,
  }) {
    if (element.pitches.isEmpty) {
      throw ArgumentError('NoteElement.pitches must not be empty');
    }
    final id = element.id;
    final pitches = [...element.pitches]..sort(
        (a, b) => a.staffPosition(_clef) - b.staffPosition(_clef),
      );
    final positions = [
      for (final pitch in pitches) pitch.staffPosition(_clef),
    ];
    final bottom = positions.first;
    final top = positions.last;

    _layoutGraceNotes(element, id);

    final base = element.duration.base;
    final headGlyph = switch (base) {
      DurationBase.breve => SmuflGlyph.noteheadDoubleWhole,
      DurationBase.whole => SmuflGlyph.noteheadWhole,
      DurationBase.half => SmuflGlyph.noteheadHalf,
      _ => SmuflGlyph.noteheadBlack,
    };
    final headWidth = _glyphWidth(headGlyph);
    final hasStem = base != DurationBase.whole && base != DurationBase.breve;

    // Rule 5: stem down when the notehead farthest from the middle line is
    // on or above it (chords: decided by the farther extreme; ties → down).
    final stemsDown = stemsDownOverride ?? ((top - 4) >= (4 - bottom));

    // Rule 9: accidentals — shown when the pitch deviates from what the key
    // signature and earlier accidentals in this measure imply;
    // `showAccidental` overrides. Hidden accidentals do not update state.
    final shown = <(Pitch, int)>[]; // pitch + its staff position
    for (var i = 0; i < pitches.length; i++) {
      final pitch = pitches[i];
      final key = (pitch.step, pitch.octave);
      final implied = written[key] ?? _key.alterFor(pitch.step);
      final show = element.showAccidental ?? (pitch.alter != implied);
      if (show) {
        shown.add((pitch, positions[i]));
        written[key] = pitch.alter;
      }
    }
    // Naive vertical stacking: topmost accidental closest to the note,
    // each further one in its own column to the left.
    shown.sort((a, b) => b.$2 - a.$2);
    var preWidth = 0.0;
    for (final (pitch, _) in shown) {
      preWidth +=
          _glyphWidth(SmuflGlyph.accidentalFor(pitch.alter)) + s.accidentalGap;
    }

    final noteX = _x + preWidth;

    var accRight = noteX - s.accidentalGap;
    for (final (pitch, position) in shown) {
      final glyph = SmuflGlyph.accidentalFor(pitch.alter);
      final accX = accRight - _glyphWidth(glyph);
      _addGlyph(glyph, accX - meta.bBoxOf(glyph).swX, _yOf(position),
          elementId: id);
      accRight = accX - s.accidentalGap;
    }

    // Rule 11: seconds are resolved by offsetting the interfering notehead
    // to the other side of the stem. Walk from the stem's anchor end.
    final columnX = List<double>.filled(positions.length, noteX);
    final flippedX = stemsDown
        ? noteX - headWidth + s.stemThickness
        : noteX + headWidth - s.stemThickness;
    final order = stemsDown
        ? [for (var i = positions.length - 1; i >= 0; i--) i]
        : [for (var i = 0; i < positions.length; i++) i];
    for (var k = 1; k < order.length; k++) {
      final current = order[k];
      final previous = order[k - 1];
      if ((positions[current] - positions[previous]).abs() == 1 &&
          columnX[previous] == noteX) {
        columnX[current] = hasStem ? flippedX : noteX + headWidth;
      }
    }

    for (var i = 0; i < positions.length; i++) {
      _addGlyph(headGlyph, columnX[i], _yOf(positions[i]), elementId: id);
    }
    _tieInfos.add(_TieInfo(
      note: element,
      id: id,
      stemsDown: stemsDown,
      left: columnX.reduce(min),
      right: columnX.reduce(max) + headWidth,
      heads: [
        for (var i = 0; i < positions.length; i++)
          (
            pitches[i],
            columnX[i],
            columnX[i] + headWidth,
            _yOf(positions[i]),
          ),
      ],
    ));

    // Rule 8: ledger lines.
    final minColX = columnX.reduce(min);
    final maxColX = columnX.reduce(max);
    _addLedgerLines(
      bottom,
      top,
      minColX - s.legerLineExtension,
      maxColX + headWidth + s.legerLineExtension,
      id,
    );

    // Rules 5–6: stem and flag (or defer to the beam pass).
    _BeamedNote? beamed;
    double? stemTipY;
    double stemX = noteX;
    if (hasStem) {
      final anchors = meta.anchorsOf(headGlyph);
      if (stemsDown) {
        final anchor = anchors.stemDownNW ?? const Point(0.0, 0.0);
        stemX = noteX + anchor.x + s.stemThickness / 2;
        final attachY = _yOf(top) - anchor.y; // SMuFL y-up -> flip sign
        if (deferStem) {
          beamed = _BeamedNote(
            elementId: id,
            stemX: stemX,
            attachY: attachY,
            refY: _yOf(bottom),
            beamCount: _beamCountOf(base),
          );
        } else {
          var tipY =
              _yOf(bottom) + s.stemLength + _stemExtension(_beamCountOf(base));
          if (tipY < 2) tipY = 2; // extend toward the middle line
          _addLine(
            Point(stemX, attachY),
            Point(stemX, tipY),
            s.stemThickness,
            elementId: id,
          );
          stemTipY = tipY;
        }
      } else {
        final anchor = anchors.stemUpSE ?? Point(headWidth, 0.0);
        stemX = noteX + anchor.x - s.stemThickness / 2;
        final attachY = _yOf(bottom) - anchor.y;
        if (deferStem) {
          beamed = _BeamedNote(
            elementId: id,
            stemX: stemX,
            attachY: attachY,
            refY: _yOf(top),
            beamCount: _beamCountOf(base),
          );
        } else {
          var tipY =
              _yOf(top) - s.stemLength - _stemExtension(_beamCountOf(base));
          if (tipY > 2) tipY = 2; // extend toward the middle line
          _addLine(
            Point(stemX, attachY),
            Point(stemX, tipY),
            s.stemThickness,
            elementId: id,
          );
          stemTipY = tipY;
        }
      }
    }

    if (!deferStem && stemTipY != null) {
      final flagGlyph = switch (base) {
        DurationBase.eighth =>
          stemsDown ? SmuflGlyph.flag8thDown : SmuflGlyph.flag8thUp,
        DurationBase.sixteenth =>
          stemsDown ? SmuflGlyph.flag16thDown : SmuflGlyph.flag16thUp,
        DurationBase.thirtySecond =>
          stemsDown ? SmuflGlyph.flag32ndDown : SmuflGlyph.flag32ndUp,
        DurationBase.sixtyFourth =>
          stemsDown ? SmuflGlyph.flag64thDown : SmuflGlyph.flag64thUp,
        _ => null,
      };
      if (flagGlyph != null) {
        _addGlyph(flagGlyph, stemX - s.stemThickness / 2, stemTipY,
            elementId: id);
      }
    }

    // Rule 10: augmentation dots right of the notehead; a dot for a
    // notehead on a line sits in the space above.
    var inkRight = maxColX + headWidth;
    if (element.duration.dots > 0) {
      final dotWidth = _glyphWidth(SmuflGlyph.augmentationDot);
      final dotStart = maxColX + headWidth + s.dotGap;
      for (final position in positions.toSet()) {
        final dotY = position.isEven ? _yOf(position) - 0.5 : _yOf(position);
        for (var d = 0; d < element.duration.dots; d++) {
          _addGlyph(
            SmuflGlyph.augmentationDot,
            dotStart + d * (dotWidth + s.dotSpacing),
            dotY,
            elementId: id,
          );
        }
      }
      inkRight = dotStart +
          element.duration.dots * (dotWidth + s.dotSpacing) -
          s.dotSpacing;
    }

    _advance(noteX, inkRight, element.duration, log2Adjust);
    return beamed;
  }

  /// v0.3.6: grace notes — an acciaccatura group of small (0.6×) eighths
  /// before the host element, stems always up, slash on the first stem.
  void _layoutGraceNotes(NoteElement element, String? id) {
    if (element.graceNotes.isEmpty) return;
    const graceScale = 0.6;
    final headBox = meta.bBoxOf(SmuflGlyph.noteheadBlack);
    final graceHeadWidth = headBox.width * graceScale;
    final anchor = meta.anchorsOf(SmuflGlyph.noteheadBlack).stemUpSE ??
        Point(headBox.width, 0.0);
    var isFirst = true;
    for (final pitch in element.graceNotes) {
      final position = pitch.staffPosition(_clef);
      final y = _yOf(position);
      _addGlyph(SmuflGlyph.noteheadBlack, _x, y,
          scale: graceScale, elementId: id);
      final stemX = _x + anchor.x * graceScale - s.stemThickness / 2;
      final tipY = y - 2.2;
      _addLine(
        Point(stemX, y - anchor.y * graceScale),
        Point(stemX, tipY),
        s.stemThickness,
        elementId: id,
      );
      _addGlyph(SmuflGlyph.flag8thUp, stemX - s.stemThickness / 2, tipY,
          scale: graceScale, elementId: id);
      if (isFirst) {
        _addLine(
          Point(stemX - 0.55, tipY + 1.5),
          Point(stemX + 0.65, tipY + 0.6),
          0.12,
          elementId: id,
        );
        isFirst = false;
      }
      for (var q = -2; q >= position; q -= 2) {
        _addLine(Point(_x - 0.25, _yOf(q)),
            Point(_x + graceHeadWidth + 0.25, _yOf(q)), s.legerLineThickness,
            elementId: id);
      }
      for (var q = 10; q <= position; q += 2) {
        _addLine(Point(_x - 0.25, _yOf(q)),
            Point(_x + graceHeadWidth + 0.25, _yOf(q)), s.legerLineThickness,
            elementId: id);
      }
      _x += graceHeadWidth + 0.5;
    }
    _x += 0.3;
  }

  /// Rule 8 helper: ledger lines at even positions outside the staff.
  void _addLedgerLines(
    int bottomPosition,
    int topPosition,
    double left,
    double right,
    String? elementId,
  ) {
    for (var p = -2; p >= bottomPosition; p -= 2) {
      _addLine(
        Point(left, _yOf(p)),
        Point(right, _yOf(p)),
        s.legerLineThickness,
        elementId: elementId,
      );
    }
    for (var p = 10; p <= topPosition; p += 2) {
      _addLine(
        Point(left, _yOf(p)),
        Point(right, _yOf(p)),
        s.legerLineThickness,
        elementId: elementId,
      );
    }
  }

  // ------------------------------------------------------------------ rests

  /// Rule 12: rest glyphs at their conventional vertical homes.
  void _layoutRest(RestElement element, {double log2Adjust = 0}) {
    final (glyph, y) = switch (element.duration.base) {
      // The breve rest fills the space between the middle and fourth
      // staff lines.
      DurationBase.breve => (SmuflGlyph.restDoubleWhole, 2.0),
      // The whole rest hangs from the fourth staff line (y = 1).
      DurationBase.whole => (SmuflGlyph.restWhole, 1.0),
      // The half rest sits on the middle line (y = 2).
      DurationBase.half => (SmuflGlyph.restHalf, 2.0),
      DurationBase.quarter => (SmuflGlyph.restQuarter, 2.0),
      DurationBase.eighth => (SmuflGlyph.rest8th, 2.0),
      DurationBase.sixteenth => (SmuflGlyph.rest16th, 2.0),
      DurationBase.thirtySecond => (SmuflGlyph.rest32nd, 2.0),
      DurationBase.sixtyFourth => (SmuflGlyph.rest64th, 2.0),
    };
    final id = element.id;
    _addGlyph(glyph, _x, y, elementId: id);
    // Rests break tie chains.
    _tieInfos.add(_TieInfo(
      note: null,
      id: id,
      stemsDown: false,
      left: _x,
      right: _x + _glyphWidth(glyph),
      heads: const [],
    ));

    var inkRight = _x + _glyphWidth(glyph);
    if (element.duration.dots > 0) {
      final dotWidth = _glyphWidth(SmuflGlyph.augmentationDot);
      final dotStart = inkRight + s.dotGap;
      for (var d = 0; d < element.duration.dots; d++) {
        // Rest dots sit in the third space (y = 1.5).
        _addGlyph(
          SmuflGlyph.augmentationDot,
          dotStart + d * (dotWidth + s.dotSpacing),
          1.5,
          elementId: id,
        );
      }
      inkRight = dotStart +
          element.duration.dots * (dotWidth + s.dotSpacing) -
          s.dotSpacing;
    }
    _advance(_x, inkRight, element.duration, log2Adjust);
  }

  // -------------------------------------------------------------- spacing

  /// Rule 13: notes/rests advance proportionally to duration with a minimum
  /// gap: `advance = spacingBase + spacingPerLog2 * (4 + log2(duration))`
  /// staff spaces, measured from the notehead column ([fromX]); a sixteenth
  /// gets `spacingBase`. The next element never starts closer than
  /// [minNoteGap] after this element's ink ([inkRight]).
  void _advance(
    double fromX,
    double inkRight,
    NoteDuration duration,
    double log2Adjust,
  ) {
    final baseLog2 = duration.base == DurationBase.breve
        ? 1.0
        : -duration.base.index.toDouble();
    final log2Duration = baseLog2 + _dotLog2[duration.dots] + log2Adjust;
    final ideal = s.spacingBase + s.spacingPerLog2 * (4 + log2Duration);
    _x = max(fromX + ideal, inkRight + s.minNoteGap);
  }

  // ------------------------------------------------------------------ ties

  /// v0.3.1: for every note with `tieToNext`, draw a tie curve to each
  /// identically-pitched notehead of the immediately following note
  /// element (also across barlines). The curve sits on the notehead side,
  /// away from the stem: above for stems-down notes, below for stems-up.
  /// Ties into rests or the end of the score draw nothing.
  void _layoutTies() {
    for (var i = 0; i < _tieInfos.length - 1; i++) {
      final start = _tieInfos[i];
      final note = start.note;
      if (note == null || !note.tieToNext) continue;
      final next = _tieInfos[i + 1];
      if (next.note == null) continue;
      final dir = start.stemsDown ? -1.0 : 1.0;
      for (final (pitch, _, xRight, y) in start.heads) {
        final matches = next.heads.where((h) => h.$1 == pitch);
        if (matches.isEmpty) continue;
        final x1 = xRight + 0.15;
        final x2 = matches.first.$2 - 0.15;
        if (x2 <= x1) continue;
        final baseY = y + dir * 0.6;
        final controlY = baseY + dir * (0.35 + min(0.6, (x2 - x1) * 0.06));
        _addCurve(
          Point(x1, baseY),
          Point(x1 + (x2 - x1) * 0.3, controlY),
          Point(x1 + (x2 - x1) * 0.7, controlY),
          Point(x2, baseY),
          0.18,
        );
      }
    }
  }

  /// v0.3.2: slurs between note elements referenced by id. The curve goes
  /// above unless every spanned note stems up; endpoints anchor just
  /// outside each end element's ink, and the arc clears everything in
  /// between.
  void _layoutSlurs() {
    for (final slur in score.slurs) {
      final startIndex =
          _tieInfos.indexWhere((i) => i.note != null && i.id == slur.startId);
      final endIndex =
          _tieInfos.indexWhere((i) => i.note != null && i.id == slur.endId);
      if (startIndex < 0 || endIndex < 0) {
        throw ArgumentError('$slur references an unknown note element id');
      }
      if (endIndex <= startIndex) {
        throw ArgumentError('$slur must run forward in reading order');
      }
      final spanned = _tieInfos.sublist(startIndex, endIndex + 1);
      final notes = spanned.where((i) => i.note != null);
      final above = !notes.every((i) => !i.stemsDown);

      double headCenterX(_TieInfo info) =>
          (info.heads.first.$2 + info.heads.first.$3) / 2;
      double? topOf(_TieInfo info) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) return bounds.minY;
        if (info.heads.isEmpty) return null;
        return info.heads.map((h) => h.$4).reduce(min) - 0.5;
      }

      double? bottomOf(_TieInfo info) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) return bounds.maxY;
        if (info.heads.isEmpty) return null;
        return info.heads.map((h) => h.$4).reduce(max) + 0.5;
      }

      final x1 = headCenterX(spanned.first);
      final x2 = headCenterX(spanned.last);
      final double y1;
      final double y2;
      final double controlY;
      if (above) {
        y1 = topOf(spanned.first)! - 0.35;
        y2 = topOf(spanned.last)! - 0.35;
        final clearance =
            spanned.map(topOf).whereType<double>().reduce(min) - 0.4;
        controlY =
            min(min(y1, y2), clearance) - (0.5 + min(1.5, (x2 - x1) * 0.06));
      } else {
        y1 = bottomOf(spanned.first)! + 0.35;
        y2 = bottomOf(spanned.last)! + 0.35;
        final clearance =
            spanned.map(bottomOf).whereType<double>().reduce(max) + 0.4;
        controlY =
            max(max(y1, y2), clearance) + (0.5 + min(1.5, (x2 - x1) * 0.06));
      }
      _addCurve(
        Point(x1, y1),
        Point(x1 + (x2 - x1) * 0.3, controlY),
        Point(x1 + (x2 - x1) * 0.7, controlY),
        Point(x2, y2),
        0.2,
      );
    }
  }

  /// v0.3.5: dynamic markings centered below their element and hairpin
  /// wedges between two elements, both on the dynamics line under the
  /// staff (pushed lower by any element ink reaching below it).
  void _layoutDynamics() {
    _TieInfo infoOf(String id, String what) {
      final index = _tieInfos.indexWhere((i) => i.note != null && i.id == id);
      if (index < 0) {
        throw ArgumentError('$what references an unknown note element id');
      }
      return _tieInfos[index];
    }

    double lineFor(Iterable<_TieInfo> infos) {
      var y = 6.2;
      for (final info in infos) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) y = max(y, bounds.maxY + 1.0);
      }
      return y;
    }

    for (final marking in score.dynamics) {
      final info = infoOf(marking.elementId, '$marking');
      final glyph = SmuflGlyph.dynamicGlyph(marking.level);
      final box = meta.bBoxOf(glyph);
      final centerX = (info.left + info.right) / 2;
      // Dynamics glyphs sit on their text baseline; center their ink.
      _addGlyph(
        glyph,
        centerX - box.swX - box.width / 2,
        lineFor([info]) + 0.6,
        elementId: marking.elementId,
      );
    }

    for (final hairpin in score.hairpins) {
      final start = infoOf(hairpin.startId, '$hairpin');
      final endIndex =
          _tieInfos.indexWhere((i) => i.note != null && i.id == hairpin.endId);
      if (endIndex < 0) {
        throw ArgumentError('$hairpin references an unknown note element id');
      }
      final startIndex = _tieInfos.indexOf(start);
      if (endIndex <= startIndex) {
        throw ArgumentError('$hairpin must run forward in reading order');
      }
      final end = _tieInfos[endIndex];
      final x1 = (start.left + start.right) / 2;
      final x2 = (end.left + end.right) / 2;
      final midY = lineFor(_tieInfos.sublist(startIndex, endIndex + 1)) + 0.55;
      final thickness = meta.engravingDefault('hairpinThickness', orElse: 0.16);
      const halfOpening = 0.55;
      final openX = hairpin.type == HairpinType.crescendo ? x2 : x1;
      final tipX = hairpin.type == HairpinType.crescendo ? x1 : x2;
      _addLine(Point(tipX, midY), Point(openX, midY - halfOpening), thickness);
      _addLine(Point(tipX, midY), Point(openX, midY + halfOpening), thickness);
    }
  }

  // -------------------------------------------------------------- barlines

  /// v0.3.8: mid-score clef/key/time changes drawn at the measure start.
  void _applyMeasureChanges(Measure measure) {
    final clefChange = measure.clefChange;
    if (clefChange != null && clefChange != _clef) {
      _clef = clefChange;
      final (glyph, position) = switch (_clef) {
        Clef.treble => (SmuflGlyph.gClef, 2),
        Clef.bass => (SmuflGlyph.fClef, 6),
        Clef.alto => (SmuflGlyph.cClef, 4),
        Clef.tenor => (SmuflGlyph.cClef, 6),
      };
      const changeScale = 0.8;
      _addGlyph(glyph, _x, _yOf(position), scale: changeScale);
      _x += _glyphWidth(glyph) * changeScale + s.clefGap * 0.75;
    }
    final keyChange = measure.keyChange;
    if (keyChange != null && keyChange != _key) {
      // Cancellation naturals for steps the new signature drops.
      final oldFifths = _key.fifths;
      final oldTable =
          oldFifths > 0 ? _sharpPositions[_clef]! : _flatPositions[_clef]!;
      final oldSteps = _key.alteredSteps;
      final newSteps = keyChange.alteredSteps.toSet();
      final naturalWidth = _glyphWidth(SmuflGlyph.accidentalNatural);
      for (var i = 0; i < oldSteps.length; i++) {
        if (newSteps.contains(oldSteps[i]) &&
            (keyChange.fifths > 0) == (oldFifths > 0)) {
          continue;
        }
        _addGlyph(SmuflGlyph.accidentalNatural, _x, _yOf(oldTable[i]));
        _x += naturalWidth + s.keyAccidentalGap;
      }
      _key = keyChange;
      _layoutKeySignature();
    }
    final timeChange = measure.timeChange;
    if (timeChange != null && timeChange != _time) {
      _time = timeChange;
      _layoutTimeSignature();
    }
  }

  /// v0.3.8: `|:` — thick line, thin line, dots.
  void _addStartRepeat() {
    final thickX = _x + s.thickBarlineThickness / 2;
    _addLine(Point(thickX, 0), Point(thickX, 4), s.thickBarlineThickness);
    final thinX = thickX + s.thickBarlineThickness / 2 + s.barlineSeparation;
    _addLine(Point(thinX, 0), Point(thinX, 4), s.thinBarlineThickness);
    final dotsX = thinX + s.thinBarlineThickness / 2 + 0.3;
    _addGlyph(SmuflGlyph.repeatDots, dotsX, 4);
    _x = dotsX + _glyphWidth(SmuflGlyph.repeatDots) + s.barlineGap;
  }

  /// v0.3.8: `:|` — dots, thin line, thick line.
  void _addEndRepeat() {
    final dotsX = _x;
    _addGlyph(SmuflGlyph.repeatDots, dotsX, 4);
    final thinX = dotsX + _glyphWidth(SmuflGlyph.repeatDots) + 0.3;
    _addLine(Point(thinX, 0), Point(thinX, 4), s.thinBarlineThickness);
    final thickX = thinX + s.thinBarlineThickness / 2 + s.barlineSeparation;
    _addLine(Point(thickX, 0), Point(thickX, 4), s.thickBarlineThickness);
    _x = thickX + s.thickBarlineThickness / 2 + s.barlineGap;
  }

  /// v0.3.8: volta (ending) bracket with its number over the measure.
  void _addVolta(int number, double startX, double endX) {
    const y = -1.8;
    const hook = 0.8;
    final thickness =
        meta.engravingDefault('repeatEndingLineThickness', orElse: 0.16);
    _addLine(Point(startX, y), Point(endX - 0.3, y), thickness);
    _addLine(Point(startX, y), Point(startX, y + hook), thickness);
    _addLine(Point(endX - 0.3, y), Point(endX - 0.3, y + hook), thickness);
    var digitX = startX + 0.5;
    for (final ch in number.toString().split('')) {
      final glyph = SmuflGlyph.tupletDigit(int.parse(ch));
      _addGlyph(glyph, digitX - meta.bBoxOf(glyph).swX, y + 1.0, scale: 0.8);
      digitX += _glyphWidth(glyph) * 0.8;
    }
  }

  void _addBarline() {
    _addLine(
      Point(_x, 0),
      Point(_x, 4),
      s.thinBarlineThickness,
    );
    _x += s.thinBarlineThickness + s.barlineGap;
  }

  /// Rule 13: `barlineFinal` (thin + thick) at the end; returns the width.
  double _addFinalBarline() {
    final thinX = _x;
    _addLine(Point(thinX, 0), Point(thinX, 4), s.thinBarlineThickness);
    final thickX = thinX +
        s.thinBarlineThickness / 2 +
        s.barlineSeparation +
        s.thickBarlineThickness / 2;
    _addLine(Point(thickX, 0), Point(thickX, 4), s.thickBarlineThickness);
    return thickX + s.thickBarlineThickness / 2;
  }

  // ---------------------------------------------------------------- beaming

  /// Rule 7: group eighths/sixteenths within a beat (simple meter). In
  /// even x/4 meters, adjacent all-eighth beat groups within the same half
  /// measure merge (so 8 eighths in 4/4 yield 2 beams). No beaming across
  /// rests or beat boundaries.
  List<_BeamGroup> _computeBeamGroups(Measure measure) {
    final time = _time;
    // Unmetered scores group per quarter-note window.
    final span = time == null ? Fraction(1, 4) : Fraction(1, time.beatUnit);
    final halfSpan = Fraction(1, 2);

    // Which tuplet span (by list index) an element belongs to, or -1.
    int spanOf(int index) {
      for (var t = 0; t < measure.tuplets.length; t++) {
        if (measure.tuplets[t].contains(index)) return t;
      }
      return -1;
    }

    var onset = Fraction.zero;
    final runs = <List<int>>[];
    final onsets = <Fraction>[];
    List<int>? current;
    int? currentWindow;
    int? currentSpan;

    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      onsets.add(onset);
      final beamable =
          element is NoteElement && _beamCountOf(element.duration.base) >= 1;
      if (beamable) {
        final window = _windowIndex(onset, span);
        // Beam runs never cross a tuplet boundary in either direction.
        final tuplet = spanOf(i);
        if (current != null &&
            window == currentWindow &&
            tuplet == currentSpan) {
          current.add(i);
        } else {
          current = [i];
          currentWindow = window;
          currentSpan = tuplet;
          runs.add(current);
        }
      } else {
        current = null;
        currentWindow = null;
        currentSpan = null;
      }
      onset += measure.effectiveDurationAt(i);
    }

    // Merge adjacent all-eighth beat groups within the same half measure
    // (tuplet groups never merge).
    if (time != null && time.beatUnit == 4 && time.beats.isEven) {
      bool allEighths(List<int> run) => run.every((i) =>
          (measure.elements[i] as NoteElement).duration.base ==
          DurationBase.eighth);
      for (var i = 0; i < runs.length - 1;) {
        final a = runs[i];
        final b = runs[i + 1];
        if (b.first == a.last + 1 &&
            spanOf(a.first) == -1 &&
            spanOf(b.first) == -1 &&
            allEighths(a) &&
            allEighths(b) &&
            _windowIndex(onsets[a.first], halfSpan) ==
                _windowIndex(onsets[b.first], halfSpan)) {
          a.addAll(b);
          runs.removeAt(i + 1);
        } else {
          i++;
        }
      }
    }

    final groups = <_BeamGroup>[];
    for (final run in runs.where((r) => r.length >= 2)) {
      var maxAbove = -100;
      var maxBelow = -100;
      for (final i in run) {
        final note = measure.elements[i] as NoteElement;
        for (final pitch in note.pitches) {
          final p = pitch.staffPosition(_clef);
          if (p - 4 > maxAbove) maxAbove = p - 4;
          if (4 - p > maxBelow) maxBelow = 4 - p;
        }
      }
      groups.add(_BeamGroup(run, stemsDown: maxAbove >= maxBelow));
    }
    return groups;
  }

  /// Beams (or flags) a duration needs: eighth 1 … sixty-fourth 4;
  /// quarter and longer (incl. breve) 0.
  static int _beamCountOf(DurationBase base) => switch (base) {
        DurationBase.eighth => 1,
        DurationBase.sixteenth => 2,
        DurationBase.thirtySecond => 3,
        DurationBase.sixtyFourth => 4,
        _ => 0,
      };

  /// Extra stem length so multi-flag/multi-beam notes stay clear.
  static double _stemExtension(int beamCount) =>
      beamCount > 2 ? (beamCount - 2) * 0.75 : 0.0;

  static int _windowIndex(Fraction onset, Fraction span) =>
      (onset.numerator * span.denominator) ~/
      (onset.denominator * span.numerator);

  /// Beam geometry: a straight beam through the stem tips, slant clamped to
  /// ±1 staff space over the group, intercept chosen so every stem keeps at
  /// least the default length. [BeamPrimitive] points are the midpoints of
  /// the beam's end edges; stems run to the beam's center line.
  void _layoutBeamGroup(List<_BeamedNote> notes, {required bool stemsDown}) {
    final first = notes.first;
    final last = notes.last;
    final dx = last.stemX - first.stemX;
    final slant = ((last.refY - first.refY) / 2).clamp(-1.0, 1.0);
    final slope = dx == 0 ? 0.0 : slant / dx;

    // Multi-level groups (32nds/64ths) need longer stems so the extra
    // beams stay clear of the noteheads.
    final stemLength = s.stemLength +
        _stemExtension(notes.map((n) => n.beamCount).reduce(max));
    double intercept;
    if (stemsDown) {
      intercept =
          notes.map((n) => n.refY + stemLength - slope * n.stemX).reduce(max);
      // Never let a downward beam sit above the middle line.
      for (final n in notes) {
        final y = slope * n.stemX + intercept;
        if (y < 2) intercept += 2 - y;
      }
    } else {
      intercept =
          notes.map((n) => n.refY - stemLength - slope * n.stemX).reduce(min);
      for (final n in notes) {
        final y = slope * n.stemX + intercept;
        if (y > 2) intercept -= y - 2;
      }
    }

    double beamY(double x) => slope * x + intercept;

    for (final note in notes) {
      _addLine(
        Point(note.stemX, note.attachY),
        Point(note.stemX, beamY(note.stemX)),
        s.stemThickness,
        elementId: note.elementId,
      );
    }

    _addBeam(
      Point(first.stemX, beamY(first.stemX)),
      Point(last.stemX, beamY(last.stemX)),
      s.beamThickness,
    );

    // Secondary/tertiary/quaternary beams, offset toward the noteheads.
    final maxLevel = notes.map((n) => n.beamCount).reduce(max);
    for (var level = 2; level <= maxLevel; level++) {
      final offset = (s.beamThickness + s.beamSpacing) *
          (level - 1) *
          (stemsDown ? -1 : 1);
      var i = 0;
      while (i < notes.length) {
        if (notes[i].beamCount < level) {
          i++;
          continue;
        }
        var j = i;
        while (j + 1 < notes.length && notes[j + 1].beamCount >= level) {
          j++;
        }
        if (j > i) {
          _addBeam(
            Point(notes[i].stemX, beamY(notes[i].stemX) + offset),
            Point(notes[j].stemX, beamY(notes[j].stemX) + offset),
            s.beamThickness,
          );
        } else {
          // Lone short note between longer ones: a beamlet stub pointing
          // into the group (leftward unless it is the group's first note).
          final x = notes[i].stemX;
          final stubX = i == 0 ? x + 1.0 : x - 1.0;
          _addBeam(
            Point(min(x, stubX), beamY(min(x, stubX)) + offset),
            Point(max(x, stubX), beamY(max(x, stubX)) + offset),
            s.beamThickness,
          );
        }
        i = j + 1;
      }
    }
  }
}
