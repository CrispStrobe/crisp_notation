/// The layout engine: turns a [Score] into a [ScoreLayout]
/// (HANDOVER.md §4.2, rules 1–14).
library;

import 'dart:math';

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../smufl/smufl_metadata.dart';
import '../tablature/chord_diagram.dart';
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
  ///
  /// [leadingWidth] and [measureWidths] set **minimum** widths for the
  /// leading segment (clef/key/time) and each measure — the grand-staff
  /// layout uses them to align barlines across staves. Narrow content is
  /// padded; content wider than an override keeps its natural width.
  ///
  /// [spacingStretch] multiplies the duration-proportional ideal advance
  /// (≥ 1.0); system justification uses it to widen lines uniformly.
  ///
  /// With [drawTimeSignature] false the leading time signature is not
  /// drawn but still governs beaming — later systems of a broken score
  /// use this. With [finalBarline] false the layout closes with a plain
  /// thin barline instead of the thin+thick end-of-score pair — systems
  /// that continue on the next line use this.
  ScoreLayout layout(
    Score score,
    LayoutSettings settings, {
    double? leadingWidth,
    List<double>? measureWidths,
    double spacingStretch = 1.0,
    bool drawTimeSignature = true,
    bool finalBarline = true,
    bool showNoteNames = false,
    bool showBeatNumbers = false,
    bool showMeasureNumbers = false,
  }) =>
      _LayoutBuilder(score, settings,
              leadingWidth: leadingWidth,
              measureWidths: measureWidths,
              spacingStretch: spacingStretch,
              drawTimeSignature: drawTimeSignature,
              finalBarline: finalBarline,
              showNoteNames: showNoteNames,
              showBeatNumbers: showBeatNumbers,
              showMeasureNumbers: showMeasureNumbers)
          .build();
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
/// A feathered group carries its (beginBeams, endBeams) fan.
class _BeamGroup {
  final List<int> indices;

  /// Metric onset (from the measure start) of each note in [indices], aligned
  /// index-for-index. Lets the beam layout break secondary beams at metric
  /// subdivisions.
  final List<Fraction> onsets;
  final bool stemsDown;
  final (int, int)? feather;
  final double? forcedSlant;
  _BeamGroup(this.indices,
      {required this.onsets,
      required this.stemsDown,
      this.feather,
      this.forcedSlant});
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

  /// Voice this element belongs to (0 or 1); ties never cross voices.
  final int voice;

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
    this.voice = 0,
  });
}

class _LayoutBuilder {
  final Score score;
  final LayoutSettings s;
  final double? leadingWidth;
  final List<double>? measureWidths;
  final double spacingStretch;
  final bool drawTimeSignature;
  final bool finalBarline;
  final bool showNoteNames;
  final bool showBeatNumbers;
  final bool showMeasureNumbers;
  SmuflMetadata get meta => s.metadata;

  final List<LayoutPrimitive> _primitives = [];
  final Map<String, _Bounds> _elementBounds = {};
  final List<MeasureRegion> _measureRegions = [];
  final List<_TieInfo> _tieInfos = [];
  final _Bounds _ink = _Bounds();

  /// Per-glyph ink rectangles `(left, top, right, bottom)`, fed by [_expand],
  /// for per-column skyline queries (so above/below marks clear only the ink
  /// in their own horizontal span, not the whole system's extremes).
  final List<(double, double, double, double)> _inkRects = [];

  double _x = 0;

  /// Staff-position shift per element id from ottava spans (v0.6.4):
  /// −7 inside an 8va (written an octave lower), +7 inside an 8vb.
  late final Map<String, int> _ottavaShift = _computeOttavaShifts();

  Map<String, int> _computeOttavaShifts() {
    if (score.ottavas.isEmpty) return const {};
    final order = <String>[
      for (final measure in score.measures)
        for (final voice in measure.voices)
          for (final element in voice)
            if (element.id != null) element.id!,
    ];
    final shifts = <String, int>{};
    for (final ottava in score.ottavas) {
      final start = order.indexOf(ottava.startId);
      final end = order.indexOf(ottava.endId);
      if (start < 0 || end < start) {
        throw ArgumentError('$ottava does not span forward in this score');
      }
      for (var i = start; i <= end; i++) {
        shifts[order[i]] = ottava.down ? 7 : -7;
      }
    }
    return shifts;
  }

  /// The written staff position of [pitch] for element [id] — sounding
  /// position adjusted by any covering ottava.
  int _writtenPosition(Pitch pitch, String? id) =>
      pitch.staffPosition(_clef) + (_ottavaShift[id] ?? 0);

  // Mid-score changes (v0.3.8) update these as measures are laid out.
  late Clef _clef = score.clef;
  late KeySignature _key = score.keySignature;
  late TimeSignature? _time = score.timeSignature;

  _LayoutBuilder(this.score, this.s,
      {this.leadingWidth,
      this.measureWidths,
      this.spacingStretch = 1.0,
      this.drawTimeSignature = true,
      this.finalBarline = true,
      this.showNoteNames = false,
      this.showBeatNumbers = false,
      this.showMeasureNumbers = false});

  // Key signature accidental staff positions per clef, in writing order.
  // Bass/alto shift the treble pattern down 2/1 positions; the tenor sharp
  // pattern is its own shape (F# starts low to stay inside the staff).
  static const Map<Clef, List<int>> _sharpPositions = {
    Clef.treble: [8, 5, 9, 6, 3, 7, 4],
    Clef.bass: [6, 3, 7, 4, 1, 5, 2],
    Clef.alto: [7, 4, 8, 5, 2, 6, 3],
    Clef.tenor: [2, 6, 3, 7, 4, 8, 5],
    // Octave clefs write key signatures like their base clef.
    Clef.treble8va: [8, 5, 9, 6, 3, 7, 4],
    Clef.treble8vb: [8, 5, 9, 6, 3, 7, 4],
    Clef.bass8vb: [6, 3, 7, 4, 1, 5, 2],
  };
  static const Map<Clef, List<int>> _flatPositions = {
    Clef.treble: [4, 7, 3, 6, 2, 5, 1],
    Clef.bass: [2, 5, 1, 4, 0, 3, -1],
    Clef.alto: [3, 6, 2, 5, 1, 4, 0],
    Clef.tenor: [5, 8, 4, 7, 3, 6, 2],
    Clef.treble8va: [4, 7, 3, 6, 2, 5, 1],
    Clef.treble8vb: [4, 7, 3, 6, 2, 5, 1],
    Clef.bass8vb: [2, 5, 1, 4, 0, 3, -1],
  };

  /// Key-signature accidental staff positions for [clef]. Uses the hand-tuned
  /// table where one exists (preserving tenor's special sharp shape); otherwise
  /// derives them by the standard engraving rule — each accidental a fifth from
  /// the last, taken up while it stays on the staff and dropping an octave
  /// otherwise. Reproduces the treble table exactly; keeps every signature
  /// within the five lines (positions −1..9) for the C-/F-clef positions.
  static List<int> _keyAccidentalPositions(Clef clef, {required bool sharp}) {
    final table = (sharp ? _sharpPositions : _flatPositions)[clef];
    if (table != null) return table;
    const high = 9;
    final firstStep = sharp ? 3 : 6; // F for sharps, B for flats
    final upDelta = sharp ? 4 : 3; // a fifth up (sharps) / a fourth up (flats)
    final downDelta = sharp ? 3 : 4; // the octave-complementary drop
    // The lowest occurrence of the first natural on/above the bottom line,
    // lifted as high as it fits — the traditional starting octave.
    var p = (firstStep - clef.bottomLineDiatonicIndex) % 7; // 0..6
    while (p + 7 <= high) {
      p += 7;
    }
    final out = [p];
    for (var i = 1; i < 7; i++) {
      final up = p + upDelta;
      p = up <= high ? up : p - downDelta;
      out.add(p);
    }
    return out;
  }

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
    if (drawTimeSignature) _layoutTimeSignature();
    if (leadingWidth != null && _x < leadingWidth!) {
      _x = leadingWidth!;
    }

    for (var i = 0; i < score.measures.length; i++) {
      final measure = score.measures[i];
      _applyMeasureChanges(measure);
      if (measure.startRepeat) _addStartRepeat();
      final startX = _x;
      _layoutMeasure(measure);
      final widths = measureWidths;
      if (widths != null && i < widths.length && _x < startX + widths[i]) {
        _x = startX + widths[i];
      }
      _measureRegions.add(MeasureRegion(i, startX: startX, endX: _x));
      if (measure.volta != null) {
        _addVolta(measure.volta!, startX, _x);
      }
      if (measure.endRepeat) {
        _addEndRepeat();
      } else if (i < score.measures.length - 1) {
        _addBarline(measure.barline);
      }
    }
    _layoutTies();
    _layoutSlurs();
    _layoutGlissandos();
    _layoutOttavas();
    _layoutDynamics();
    _layoutPedals();
    _layoutLyrics();
    _layoutFiguredBass();
    _layoutNoteNames();
    _layoutNavigation();
    _layoutAnnotations();
    _layoutJazzArticulations();
    _layoutBreathMarks();
    _layoutChordDiagrams();
    _layoutBeatNumbers();
    _layoutMeasureNumbers();
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
    bool round = false,
  }) {
    _primitives.add(
      LinePrimitive(from, to,
          thickness: thickness, elementId: elementId, round: round),
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
    _inkRects.add((left, top, right, bottom));
    if (elementId != null) {
      _elementBounds
          .putIfAbsent(elementId, _Bounds.new)
          .expand(left, top, right, bottom);
    }
  }

  /// Highest ink (smallest y) whose x-range overlaps `[xL, xR)`, or null when
  /// that column is empty. Only ink placed so far is considered, so the pass
  /// order determines what a mark clears.
  double? _skylineTop(double xL, double xR) {
    double? best;
    for (final (l, t, r, _) in _inkRects) {
      if (r <= xL || l >= xR) continue;
      if (best == null || t < best) best = t;
    }
    return best;
  }

  /// Lowest ink (largest y) whose x-range overlaps `[xL, xR)`, or null.
  double? _skylineBottom(double xL, double xR) {
    double? best;
    for (final (l, _, r, b) in _inkRects) {
      if (r <= xL || l >= xR) continue;
      if (best == null || b > best) best = b;
    }
    return best;
  }

  double _glyphWidth(String name) => meta.bBoxOf(name).width;

  // ------------------------------------------------------- leading elements

  /// Rule 1: clef anchored on its reference line (gClef on G4's line,
  /// fClef on F3's, cClef on C4's).
  void _layoutClef() {
    final (glyph, position) = _clefGlyph(_clef);
    _addGlyph(glyph, _x, _yOf(position));
    _x += _glyphWidth(glyph) + s.clefGap;
  }

  /// Glyph + anchor staff position per clef (octave clefs carry the 8).
  static (String, int) _clefGlyph(Clef clef) => switch (clef) {
        Clef.treble => (SmuflGlyph.gClef, 2), // G4
        Clef.bass => (SmuflGlyph.fClef, 6), // F3
        Clef.alto => (SmuflGlyph.cClef, 4), // C4 on the middle line
        Clef.tenor => (SmuflGlyph.cClef, 6), // C4 on the fourth line
        Clef.treble8va => (SmuflGlyph.gClef8va, 2),
        Clef.treble8vb => (SmuflGlyph.gClef8vb, 2),
        Clef.bass8vb => (SmuflGlyph.fClef8vb, 6),
        Clef.frenchViolin => (SmuflGlyph.gClef, 0), // G4 on the bottom line
        Clef.soprano => (SmuflGlyph.cClef, 0), // C4 on the bottom line
        Clef.mezzoSoprano => (SmuflGlyph.cClef, 2), // C4 on the second line
        Clef.baritone => (SmuflGlyph.fClef, 4), // F3 on the middle line
        Clef.subbass => (SmuflGlyph.fClef, 8), // F3 on the top line
        Clef.percussion => (SmuflGlyph.percussionClef, 4), // centered
      };

  /// Rule 2: key signature in standard order at conventional octaves.
  void _layoutKeySignature() {
    final fifths = _key.fifths;
    // A neutral percussion staff carries no key signature.
    if (fifths == 0 || _clef == Clef.percussion) return;
    final count = fifths.abs();
    final table = _keyAccidentalPositions(_clef, sharp: fifths > 0);
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
    if (time.symbol != TimeSymbol.numeric) {
      // A single C / ¢ glyph, centered on the middle staff line (y = 2).
      final glyph = time.symbol == TimeSymbol.cut
          ? SmuflGlyph.timeSigCutCommon
          : SmuflGlyph.timeSigCommon;
      _addGlyph(glyph, _x - meta.bBoxOf(glyph).swX, 2);
      _x += _glyphWidth(glyph) + s.signatureGap;
      return;
    }
    final components = time.components;
    final numerator = components == null
        ? _timeSigGlyphs(time.beats)
        : [
            for (var i = 0; i < components.length; i++) ...[
              if (i > 0) SmuflGlyph.timeSigPlus,
              ..._timeSigGlyphs(components[i]),
            ],
          ];
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
    if (measure.multiRest != null) {
      _layoutMultiRest(measure.multiRest!);
      return;
    }
    if (measure.voices.length > 1) {
      _layoutMultiVoiceMeasure(measure);
      return;
    }
    final groups = _computeBeamGroups(
      measure.elements,
      effectiveAt: measure.effectiveDurationAt,
      tuplets: measure.tuplets,
    );
    final beamedIndex = <int, _BeamGroup>{
      for (final group in groups)
        for (final index in group.indices) index: group,
    };
    final deferred = <_BeamGroup, List<_BeamedNote>>{};
    final tieIndexOf = <int, int>{};

    // Accidental state: (step, octave) -> alteration written earlier in
    // this measure. Resets every measure (rule 9).
    final written = <(Step, int), int>{};

    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      final log2Adjust = _tupletLog2Adjust(measure, i);
      tieIndexOf[i] = _tieInfos.length;
      switch (element) {
        case NoteElement():
          final group = beamedIndex[i];
          final result = _layoutNote(
            element,
            written,
            stemsDownOverride: group?.stemsDown,
            deferStem: group != null,
          );
          if (group != null && result.beamed != null) {
            deferred.putIfAbsent(group, () => []).add(result.beamed!);
          }
          _advance(result.noteX, result.inkRight, element.duration, log2Adjust);
        case RestElement():
          final result = _layoutRest(element);
          _advance(result.noteX, result.inkRight, element.duration, log2Adjust);
      }
    }

    for (final group in groups) {
      final notes = deferred[group];
      if (notes != null && notes.length >= 2) {
        _layoutBeamGroup(notes,
            stemsDown: group.stemsDown,
            onsets: group.onsets,
            feather: group.feather,
            forcedSlant: group.forcedSlant);
      }
    }
    _layoutArticulations(measure.elements, tieIndexOf);
    _layoutFingerings(measure.elements, tieIndexOf);
    _layoutArpeggios(measure.elements, tieIndexOf);
    _layoutTuplets(measure, tieIndexOf);
  }

  /// v0.4.1 / v0.4.4: a measure with two to four voices. Odd-indexed voices
  /// (2, 4) stem down, even-indexed (1, 3) stem up; elements sharing an onset
  /// align in one column, rests displace vertically (staggered per voice), and
  /// a note whose head collides (a second/unison) with a higher voice already
  /// placed in the column is shifted rightward. When every sounding note in a
  /// column clears the others, their accidentals share one column block and the
  /// heads align behind it.
  void _layoutMultiVoiceMeasure(Measure measure) {
    final voices = measure.voices;
    final n = voices.length;
    Fraction effectiveAt(int voice, int index) => voice == 0
        ? measure.effectiveDurationAt(index)
        : voices[voice][index].duration.toFraction();

    final groupsPerVoice = [
      for (var v = 0; v < n; v++)
        _computeBeamGroups(
          voices[v],
          effectiveAt: (i) => effectiveAt(v, i),
          tuplets: v == 0 ? measure.tuplets : const [],
          forcedStemsDown: v.isOdd,
        ),
    ];
    final beamedIndexPerVoice = [
      for (final groups in groupsPerVoice)
        <int, _BeamGroup>{
          for (final group in groups)
            for (final index in group.indices) index: group,
        },
    ];
    final deferred = <_BeamGroup, List<_BeamedNote>>{};
    final tieIndexPerVoice = [for (var v = 0; v < n; v++) <int, int>{}];

    // Onsets per voice, plus the merged distinct column onsets.
    final onsetsPerVoice = <List<Fraction>>[];
    var measureEnd = Fraction.zero;
    for (var v = 0; v < n; v++) {
      var onset = Fraction.zero;
      final onsets = <Fraction>[];
      for (var i = 0; i < voices[v].length; i++) {
        onsets.add(onset);
        onset += effectiveAt(v, i);
      }
      onsetsPerVoice.add(onsets);
      if (onset > measureEnd) measureEnd = onset;
    }
    final columns = <Fraction>[
      for (final onsets in onsetsPerVoice) ...onsets,
    ]..sort();
    final distinct = <Fraction>[];
    for (final onset in columns) {
      if (distinct.isEmpty || distinct.last != onset) distinct.add(onset);
    }

    // Shared accidental state: every voice writes on the same staff.
    final written = <(Step, int), int>{};
    final cursor = List<int>.filled(n, 0);

    for (var c = 0; c < distinct.length; c++) {
      final onset = distinct[c];
      final columnX = _x;
      final nextOnset = c + 1 < distinct.length ? distinct[c + 1] : measureEnd;
      final delta = nextOnset - onset;
      var idealEnd = columnX;
      var inkRight = columnX;

      // Head positions of higher voices already placed in this column, for
      // collision checks.
      final placedPositions = <int>[];

      // The notes sounding at this onset across all voices.
      final sounding = <NoteElement>[];
      for (var v = 0; v < n; v++) {
        final i = cursor[v];
        if (i < voices[v].length && onsetsPerVoice[v][i] == onset) {
          final el = voices[v][i];
          if (el is NoteElement) sounding.add(el);
        }
      }

      // When two or more voices sound notes here whose heads do not collide
      // (every cross-voice pair is more than a second apart), lay out all their
      // accidentals jointly in one shared column block and align the noteheads
      // behind it — so accidentals from different voices never overlap and the
      // heads share an x.
      double? columnNoteX;
      if (sounding.length >= 2) {
        final posPerNote = [
          for (final el in sounding)
            [for (final p in el.pitches) _writtenPosition(p, el.id)],
        ];
        var collides = false;
        for (var a = 0; a < posPerNote.length && !collides; a++) {
          for (var b = a + 1; b < posPerNote.length && !collides; b++) {
            if (posPerNote[a]
                .any((x) => posPerNote[b].any((y) => (x - y).abs() <= 1))) {
              collides = true;
            }
          }
        }
        if (!collides) {
          final jointShown = <(Pitch, int, String?)>[];
          for (final el in sounding) {
            final ps = [...el.pitches]..sort((a, b) =>
                a.staffPosition(_clef).compareTo(b.staffPosition(_clef)));
            for (final pitch in ps) {
              final key = (pitch.step, pitch.octave);
              final implied = written[key] ?? _key.alterFor(pitch.step);
              final show = el.showAccidental ?? (pitch.alter != implied);
              if (show) {
                jointShown.add((pitch, _writtenPosition(pitch, el.id), el.id));
                written[key] = pitch.alter;
              }
            }
          }
          if (jointShown.isNotEmpty) {
            final acc = _accidentalColumns(jointShown);
            columnNoteX = columnX + acc.preWidth;
            _drawAccidentalColumns(acc, columnNoteX);
          }
        }
      }

      for (var v = 0; v < n; v++) {
        final i = cursor[v];
        if (i >= voices[v].length || onsetsPerVoice[v][i] != onset) {
          continue;
        }
        cursor[v] = i + 1;
        final element = voices[v][i];
        tieIndexPerVoice[v][i] = _tieInfos.length;
        _x = columnX;
        if (element is NoteElement && placedPositions.isNotEmpty) {
          final myPositions = [
            for (final pitch in element.pitches)
              _writtenPosition(pitch, element.id),
          ];
          final collides = placedPositions
              .any((p1) => myPositions.any((p2) => (p1 - p2).abs() <= 1));
          if (collides) {
            _x = columnX + _glyphWidth(SmuflGlyph.noteheadBlack) + 0.15;
          }
        }
        switch (element) {
          case NoteElement():
            final group = beamedIndexPerVoice[v][i];
            final result = _layoutNote(
              element,
              written,
              stemsDownOverride: group?.stemsDown ?? v.isOdd,
              deferStem: group != null,
              voice: v,
              noteXOverride: columnNoteX,
            );
            if (group != null && result.beamed != null) {
              deferred.putIfAbsent(group, () => []).add(result.beamed!);
            }
            placedPositions.addAll([
              for (final pitch in element.pitches)
                _writtenPosition(pitch, element.id),
            ]);
            idealEnd = max(idealEnd, result.noteX + _idealAdvance(delta));
            inkRight = max(inkRight, result.inkRight);
          case RestElement():
            // Stagger rests away from the staff centre: voice 1 up, 2 down,
            // 3 further up, 4 further down.
            final magnitude = (v ~/ 2 + 1).toDouble();
            final result = _layoutRest(
              element,
              voice: v,
              yOffset: v.isEven ? -magnitude : magnitude,
            );
            idealEnd = max(idealEnd, result.noteX + _idealAdvance(delta));
            inkRight = max(inkRight, result.inkRight);
        }
      }
      _x = max(idealEnd, inkRight + s.minNoteGap);
    }

    for (var v = 0; v < n; v++) {
      for (final group in groupsPerVoice[v]) {
        final notes = deferred[group];
        if (notes != null && notes.length >= 2) {
          _layoutBeamGroup(notes,
              stemsDown: group.stemsDown,
              onsets: group.onsets,
              feather: group.feather);
        }
      }
      _layoutArticulations(voices[v], tieIndexPerVoice[v]);
      _layoutFingerings(voices[v], tieIndexPerVoice[v]);
      _layoutArpeggios(voices[v], tieIndexPerVoice[v]);
    }
    _layoutTuplets(measure, tieIndexPerVoice[0]);
  }

  /// Ideal advance for an onset gap of [delta] (fraction of a whole note).
  double _idealAdvance(Fraction delta) {
    if (delta.numerator <= 0) return 0;
    final log2Delta = log(delta.numerator / delta.denominator) / ln2;
    return (s.spacingBase + s.spacingPerLog2 * (4 + log2Delta)) *
        spacingStretch;
  }

  /// v0.3.4: articulation marks on the notehead side (opposite the stem),
  /// stacked outward in enum order; fermatas always go above the element
  /// and outside the staff.
  void _layoutArticulations(
    List<MusicElement> elements,
    Map<int, int> tieIndexOf,
  ) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element is! NoteElement ||
          (element.articulations.isEmpty && element.ornament == null)) {
        continue;
      }
      final info = _tieInfos[tieIndexOf[i]!];
      final centerX = (info.left + info.right) / 2;
      final above = info.stemsDown; // notehead side = opposite the stem
      final headYs = info.heads.map((h) => h.$4);
      var y = above ? headYs.reduce(min) - 0.75 : headYs.reduce(max) + 0.75;
      for (final articulation in Articulation.values) {
        if (articulation == Articulation.fermata ||
            articulation == Articulation.upBow ||
            articulation == Articulation.downBow ||
            !element.articulations.contains(articulation)) {
          continue;
        }
        final glyph = SmuflGlyph.articulationGlyph(articulation, above: above);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, y,
            elementId: element.id);
        y += (above ? -1 : 1) * (box.height + 0.45);
      }
      final bounds = element.id == null ? null : _elementBounds[element.id];
      var top = min(bounds?.minY ?? headYs.reduce(min), -0.5);
      // Bowing marks (up/down bow) always sit above the staff, like fermata.
      for (final bow in const [Articulation.downBow, Articulation.upBow]) {
        if (!element.articulations.contains(bow)) continue;
        final glyph = SmuflGlyph.articulationGlyph(bow, above: true);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, top - 0.4,
            elementId: element.id);
        top -= box.height + 0.4;
      }
      if (element.articulations.contains(Articulation.fermata)) {
        final glyph =
            SmuflGlyph.articulationGlyph(Articulation.fermata, above: true);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, top - 0.4,
            elementId: element.id);
        top -= box.height + 0.4;
      }
      // v0.6.2: the ornament sits above everything else on the element.
      final ornament = element.ornament;
      if (ornament != null) {
        final glyph = SmuflGlyph.ornamentGlyph(ornament);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, top - 0.4,
            elementId: element.id);
      }
    }
  }

  /// v0.7.2: fingering digits stacked above the note, from the topmost
  /// notehead upward (first entry nearest the note).
  void _layoutFingerings(
    List<MusicElement> elements,
    Map<int, int> tieIndexOf,
  ) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element is! NoteElement || element.fingerings.isEmpty) continue;
      final info = _tieInfos[tieIndexOf[i]!];
      final centerX = (info.left + info.right) / 2;
      // Start above the current ink over the note (heads, stem, ornaments,
      // articulations already placed) so digits never collide with them.
      final bounds = element.id == null ? null : _elementBounds[element.id];
      final headTop = info.heads.map((h) => h.$4).reduce(min);
      var y = min(bounds?.minY ?? headTop, headTop) - 0.6;
      for (final finger in element.fingerings) {
        if (finger < 0 || finger > 9) continue;
        final glyph = SmuflGlyph.fingeringDigit(finger);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, y,
            elementId: element.id);
        y -= box.height + 0.2;
      }
    }
  }

  /// v0.7.2: glissando/slide — a straight line from the first note's right
  /// edge to the second note's left edge, at their notehead centers.
  void _layoutGlissandos() {
    for (final gliss in score.glissandos) {
      final startIdx =
          _tieInfos.indexWhere((i) => i.note != null && i.id == gliss.startId);
      final endIdx =
          _tieInfos.indexWhere((i) => i.note != null && i.id == gliss.endId);
      if (startIdx < 0 || endIdx < 0) {
        throw ArgumentError('$gliss references an unknown note element id');
      }
      if (endIdx <= startIdx) {
        throw ArgumentError('$gliss must run forward in reading order');
      }
      final start = _tieInfos[startIdx];
      final end = _tieInfos[endIdx];
      double centerY(_TieInfo i) =>
          i.heads.map((h) => h.$4).reduce((a, b) => a + b) / i.heads.length;
      _addLine(
        Point(start.right + 0.15, centerY(start)),
        Point(end.left - 0.15, centerY(end)),
        meta.engravingDefault('glissandoLineThickness', orElse: 0.15),
      );
    }
  }

  /// v0.7.2: arpeggio — a vertical wavy line just left of the chord,
  /// spanning its noteheads, tiled from `wiggleArpeggiatoUp` and capped with
  /// a direction arrowhead.
  void _layoutArpeggios(
    List<MusicElement> elements,
    Map<int, int> tieIndexOf,
  ) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element is! NoteElement || element.arpeggio == null) continue;
      final info = _tieInfos[tieIndexOf[i]!];
      final ys = info.heads.map((h) => h.$4);
      final topY = ys.reduce(min) - 0.5;
      final bottomY = ys.reduce(max) + 0.5;
      final x = info.left - 0.5;
      final tileH = meta.bBoxOf(SmuflGlyph.wiggleArpeggiatoUp).height;
      for (var y = bottomY; y > topY; y -= tileH) {
        _addGlyph(SmuflGlyph.wiggleArpeggiatoUp, x, y, elementId: element.id);
      }
      if (element.arpeggio == Arpeggio.up) {
        _addGlyph(SmuflGlyph.wiggleArpeggiatoUpArrow, x, topY,
            elementId: element.id);
      } else {
        _addGlyph(SmuflGlyph.wiggleArpeggiatoDownArrow, x, bottomY,
            elementId: element.id);
      }
    }
  }

  /// v0.6.3: multi-measure rest — an H-bar on the middle line spanning a
  /// fixed-width measure, with the measure count in time-signature
  /// digits centered above the staff.
  void _layoutMultiRest(int count) {
    const barWidth = 8.0;
    const capHalf = 1.0; // vertical end caps span the middle two spaces
    final left = _x + 1.0;
    final right = _x + 1.0 + barWidth;
    _addLine(Point(left, 2), Point(right, 2), 0.5);
    _addLine(Point(left, 2 - capHalf), Point(left, 2 + capHalf), 0.16);
    _addLine(Point(right, 2 - capHalf), Point(right, 2 + capHalf), 0.16);

    final digits = _timeSigGlyphs(count);
    final width = _rowWidth(digits);
    var digitX = (left + right) / 2 - width / 2;
    for (final glyph in digits) {
      _addGlyph(glyph, digitX, -1.0);
      digitX += _glyphWidth(glyph);
    }
    _x = right + 1.0;
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
  void _layoutTuplets(Measure measure, Map<int, int> tieIndexOf) {
    for (final span in measure.tuplets) {
      final infos = [
        for (var i = span.startIndex; i <= span.endIndex; i++)
          _tieInfos[tieIndexOf[i]!],
      ];
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
  /// Assigns the accidentals in [shown] (each `(pitch, staff position, id)`) to
  /// zigzag columns (outside-in; an accidental shares a column only when it
  /// clears the others there by ≥ 6 staff positions) and returns the columns
  /// plus the total left-of-notehead width. Shared by single notes and the
  /// joint two-voice accidental layout.
  ({
    List<(Pitch, int, String?)> shown,
    List<int> columnIndex,
    List<double> widths,
    double preWidth,
  }) _accidentalColumns(List<(Pitch, int, String?)> shownIn) {
    final shown = [...shownIn]..sort((a, b) => b.$2 - a.$2);
    final zigzag = <int>[];
    var lowIndex = 0, highIndex = shown.length - 1;
    var fromTop = true;
    while (lowIndex <= highIndex) {
      zigzag.add(fromTop ? lowIndex++ : highIndex--);
      fromTop = !fromTop;
    }
    const clearance = 6; // staff positions (3 spaces)
    final columnIndex = List<int>.filled(shown.length, 0);
    final columnPositions = <List<int>>[];
    for (final index in zigzag) {
      final position = shown[index].$2;
      var column = columnPositions.indexWhere(
          (list) => list.every((p) => (p - position).abs() >= clearance));
      if (column < 0) {
        columnPositions.add(<int>[]);
        column = columnPositions.length - 1;
      }
      columnPositions[column].add(position);
      columnIndex[index] = column;
    }
    final widths = List<double>.filled(columnPositions.length, 0);
    for (var i = 0; i < shown.length; i++) {
      final width = _glyphWidth(SmuflGlyph.accidentalFor(shown[i].$1.alter));
      if (width > widths[columnIndex[i]]) widths[columnIndex[i]] = width;
    }
    var preWidth = 0.0;
    for (final width in widths) {
      preWidth += width + s.accidentalGap;
    }
    return (
      shown: shown,
      columnIndex: columnIndex,
      widths: widths,
      preWidth: preWidth,
    );
  }

  /// Draws the accidental columns from [acc] to the left of [noteX], each glyph
  /// tagged with its own element id.
  void _drawAccidentalColumns(
    ({
      List<(Pitch, int, String?)> shown,
      List<int> columnIndex,
      List<double> widths,
      double preWidth,
    }) acc,
    double noteX,
  ) {
    // Right edge per column, walking left from the notehead.
    final columnRight = List<double>.filled(acc.widths.length, 0);
    var edge = noteX - s.accidentalGap;
    for (var c = 0; c < acc.widths.length; c++) {
      columnRight[c] = edge;
      edge -= acc.widths[c] + s.accidentalGap;
    }
    for (var i = 0; i < acc.shown.length; i++) {
      final (pitch, position, id) = acc.shown[i];
      final glyph = SmuflGlyph.accidentalFor(pitch.alter);
      final accX = columnRight[acc.columnIndex[i]] - _glyphWidth(glyph);
      _addGlyph(glyph, accX - meta.bBoxOf(glyph).swX, _yOf(position),
          elementId: id);
    }
  }

  ({double noteX, double inkRight, _BeamedNote? beamed}) _layoutNote(
    NoteElement element,
    Map<(Step, int), int> written, {
    bool? stemsDownOverride,
    bool deferStem = false,
    int voice = 0,
    double? noteXOverride,
  }) {
    if (element.pitches.isEmpty) {
      throw ArgumentError('NoteElement.pitches must not be empty');
    }
    final id = element.id;
    final pitches = [...element.pitches]..sort(
        (a, b) => a.staffPosition(_clef) - b.staffPosition(_clef),
      );
    final positions = [
      for (final pitch in pitches) _writtenPosition(pitch, id),
    ];
    final bottom = positions.first;
    final top = positions.last;

    _layoutGraceNotes(element, id);

    final base = element.duration.base;
    final headGlyph = _noteheadGlyph(element.notehead, base);
    final headWidth = _glyphWidth(headGlyph);
    final hasStem = base != DurationBase.whole && base != DurationBase.breve;

    // Rule 5: stem down when the notehead farthest from the middle line is
    // on or above it (chords: decided by the farther extreme; ties → down).
    final stemsDown = stemsDownOverride ?? ((top - 4) >= (4 - bottom));

    // Rule 9: accidentals — shown when the pitch deviates from what the key
    // signature and earlier accidentals in this measure imply;
    // `showAccidental` overrides. Hidden accidentals do not update state.
    final shown = <(Pitch, int, String?)>[]; // pitch, staff position, id
    for (var i = 0; i < pitches.length; i++) {
      final pitch = pitches[i];
      final key = (pitch.step, pitch.octave);
      final implied = written[key] ?? _key.alterFor(pitch.step);
      final show = element.showAccidental ?? (pitch.alter != implied);
      if (show) {
        shown.add((pitch, positions[i], id));
        written[key] = pitch.alter;
      }
    }
    // Rule 9b (v0.6.1): accidental stacking in zigzag columns. In a two-voice
    // column both voices' accidentals were computed jointly and drawn by the
    // caller, which pre-marked `written`, so `shown` is empty here and only the
    // shared [noteXOverride] applies; a single note lays out its own.
    final acc = _accidentalColumns(shown);
    final noteX = noteXOverride ?? (_x + acc.preWidth);
    _drawAccidentalColumns(acc, noteX);

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
      voice: voice,
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

    // v0.7.2: single-note tremolo — strokes centered on the stem, biased
    // toward the notehead. Only unbeamed, stemmed notes (deferred/beamed
    // stems and whole notes carry none).
    final tremolo = element.tremolo;
    if (tremolo != null && stemTipY != null) {
      final glyph = SmuflGlyph.tremoloStrokes(tremolo);
      final box = meta.bBoxOf(glyph);
      final noteSideY = stemsDown ? _yOf(top) : _yOf(bottom);
      final midY = noteSideY + (stemTipY - noteSideY) * 0.4;
      _addGlyph(
        glyph,
        stemX - (box.swX + box.neX) / 2,
        midY + (box.neY + box.swY) / 2,
        elementId: id,
      );
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

    return (noteX: noteX, inkRight: inkRight, beamed: beamed);
  }

  /// v0.3.6: grace notes — a group of small (0.6×) eighths before the host
  /// element, stems always up; an acciaccatura slashes the first stem, an
  /// appoggiatura does not.
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
        if (element.graceStyle == GraceStyle.acciaccatura) {
          _addLine(
            Point(stemX - 0.55, tipY + 1.5),
            Point(stemX + 0.65, tipY + 0.6),
            0.12,
            elementId: id,
          );
        }
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

  /// Rule 12: rest glyphs at their conventional vertical homes
  /// ([yOffset] shifts them apart in two-voice measures).
  ({double noteX, double inkRight}) _layoutRest(
    RestElement element, {
    int voice = 0,
    double yOffset = 0,
  }) {
    final (glyph, baseY) = switch (element.duration.base) {
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
    final startX = _x;
    final y = baseY + yOffset;
    final id = element.id;
    _addGlyph(glyph, startX, y, elementId: id);
    // Rests break tie chains.
    _tieInfos.add(_TieInfo(
      note: null,
      id: id,
      stemsDown: false,
      voice: voice,
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
          1.5 + yOffset,
          elementId: id,
        );
      }
      inkRight = dotStart +
          element.duration.dots * (dotWidth + s.dotSpacing) -
          s.dotSpacing;
    }
    return (noteX: startX, inkRight: inkRight);
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
    final ideal = (s.spacingBase + s.spacingPerLog2 * (4 + log2Duration)) *
        spacingStretch;
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
      // The next element of the SAME voice (columns interleave voices).
      _TieInfo? next;
      for (var j = i + 1; j < _tieInfos.length; j++) {
        if (_tieInfos[j].voice == start.voice) {
          next = _tieInfos[j];
          break;
        }
      }
      if (next == null || next.note == null) continue;
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
      // Clear everything under the arc — not just the spanned noteheads, but
      // any articulations, accidentals, ornaments or other slurs in the span
      // (via the ink skyline).
      final loX = min(x1, x2), hiX = max(x1, x2);
      if (above) {
        y1 = topOf(spanned.first)! - 0.35;
        y2 = topOf(spanned.last)! - 0.35;
        final noteTop = spanned.map(topOf).whereType<double>().reduce(min);
        final clearance = min(noteTop, _skylineTop(loX, hiX) ?? noteTop) - 0.4;
        controlY =
            min(min(y1, y2), clearance) - (0.5 + min(1.5, (x2 - x1) * 0.06));
      } else {
        y1 = bottomOf(spanned.first)! + 0.35;
        y2 = bottomOf(spanned.last)! + 0.35;
        final noteBottom =
            spanned.map(bottomOf).whereType<double>().reduce(max);
        final clearance =
            max(noteBottom, _skylineBottom(loX, hiX) ?? noteBottom) + 0.4;
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

  /// v0.7.2: sustain-pedal marks — "Ped." under the start note and a release
  /// star under the end note, on a line below the staff and any dynamics.
  void _layoutPedals() {
    for (final pedal in score.pedals) {
      final startIdx =
          _tieInfos.indexWhere((i) => i.note != null && i.id == pedal.startId);
      final endIdx =
          _tieInfos.indexWhere((i) => i.note != null && i.id == pedal.endId);
      if (startIdx < 0 || endIdx < 0) {
        throw ArgumentError('$pedal references an unknown note element id');
      }
      if (endIdx < startIdx) {
        throw ArgumentError('$pedal must run forward in reading order');
      }
      final start = _tieInfos[startIdx];
      final end = _tieInfos[endIdx];
      // Below all spanned ink and clear of the dynamics line.
      var y = 8.0;
      for (final info in _tieInfos.sublist(startIdx, endIdx + 1)) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) y = max(y, bounds.maxY + 1.2);
      }
      void mark(String glyph, _TieInfo info, String id) {
        final box = meta.bBoxOf(glyph);
        _addGlyph(
            glyph, (info.left + info.right) / 2 - box.swX - box.width / 2, y,
            elementId: id);
      }

      mark(SmuflGlyph.keyboardPedalPed, start, pedal.startId);
      mark(SmuflGlyph.keyboardPedalUp, end, pedal.endId);
    }
  }

  /// v0.6.4: ottava brackets — the "8va"/"8vb" label at the span start
  /// with a dashed line to the span end and a small closing hook,
  /// above (8va) or below (8vb) the spanned ink.
  void _layoutOttavas() {
    if (score.ottavas.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final ottava in score.ottavas) {
      final start = infoOf[ottava.startId];
      final end = infoOf[ottava.endId];
      if (start == null || end == null) {
        throw ArgumentError('$ottava references an unknown note element id');
      }
      final left = start.left;
      final right = end.right;
      double edge = ottava.down ? 5.0 : -1.0;
      for (final info in _tieInfos) {
        if (info.id == null || !_ottavaShift.containsKey(info.id)) continue;
        final bounds = _elementBounds[info.id];
        if (bounds == null) continue;
        edge = ottava.down
            ? max(edge, bounds.maxY + 0.6)
            : min(edge, bounds.minY - 0.6);
      }
      final y = edge;
      _primitives.add(TextPrimitive(
        ottava.down ? '8vb' : '8va',
        Point(left + 0.9, y + 0.35),
        size: 1.6,
      ));
      // Dashed line from after the label to the span end.
      var x = left + 2.2;
      while (x < right - 0.7) {
        _addLine(Point(x, y), Point(min(x + 0.5, right), y), 0.12);
        x += 1.0;
      }
      // Closing hook toward the staff.
      _addLine(
        Point(right, y),
        Point(right, y + (ottava.down ? -0.75 : 0.75)),
        0.12,
      );
      _ink.expand(left, y - 0.8, right, y + 0.8);
    }
  }

  /// v0.4.4: lyric syllables on a shared baseline below all other ink,
  /// centered under their note; hyphens between connected syllables,
  /// extender lines under melismas.
  ///
  /// Core cannot measure text, so syllable widths are estimated at
  /// 0.5 em per character (renderers center the real text on the same
  /// anchor; see [TextPrimitive]).
  /// Half the estimated rendered width of [text] at em [size], in staff
  /// spaces. The layout has no text-font metrics, so this is a deliberately
  /// generous per-character average (≈0.62 em) chosen so the reserved box
  /// covers wide glyphs (uppercase, `m`, `w`) — the space budget that keeps
  /// words from overlapping. Text is center-anchored, so callers use ±this.
  static double _estTextHalfWidth(String text, double size) =>
      0.31 * size * max(1, text.length);

  /// Nudges box [centers] rightward (never left) as little as possible so
  /// consecutive boxes `center ± halfWidth` keep at least [gap] between them.
  /// The lists are parallel and must be in left-to-right order; guarantees no
  /// horizontal overlap. The layout has no text-font metrics, so callers pass
  /// a per-character width estimate — enough to keep words from colliding.
  static void _spreadRight(
      List<double> centers, List<double> halfWidths, double gap) {
    for (var i = 1; i < centers.length; i++) {
      final minCenter =
          centers[i - 1] + halfWidths[i - 1] + gap + halfWidths[i];
      if (centers[i] < minCenter) centers[i] = minCenter;
    }
  }

  void _layoutLyrics() {
    if (score.lyrics.isEmpty) return;
    final size = s.lyricSize;
    final lineHeight = size * 1.5;

    final infoIndexOf = <String, int>{
      for (var i = 0; i < _tieInfos.length; i++)
        if (_tieInfos[i].id != null) _tieInfos[i].id!: i,
    };
    double halfWidthOf(String text) => _estTextHalfWidth(text, size);

    // First verse's baseline: below the ink under the lyric span (a per-column
    // skyline), so a low note elsewhere on the line does not push the words
    // down. Extra verses stack below it.
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (final lyric in score.lyrics) {
      final index = infoIndexOf[lyric.elementId];
      if (index == null) continue;
      regionL = min(regionL, _tieInfos[index].left);
      regionR = max(regionR, _tieInfos[index].right);
    }
    final localBottom = _skylineBottom(regionL, regionR) ?? 4;
    final firstBaseline = max(6.5, localBottom + s.lyricGap + 0.72 * size);

    // Group syllables into verses; each verse is its own stacked row.
    final byVerse = <int, List<Lyric>>{};
    for (final lyric in score.lyrics) {
      byVerse.putIfAbsent(lyric.verse, () => []).add(lyric);
    }
    final verses = byVerse.keys.toList()..sort();

    for (var row = 0; row < verses.length; row++) {
      final lyrics = byVerse[verses[row]]!;
      final baselineY = firstBaseline + row * lineHeight;
      // Notes that carry a syllable *in this verse* — an extender stops here.
      final lyricIds = {for (final l in lyrics) l.elementId};

      // Anchor x per syllable, then keep them from colliding on close notes:
      // push each right of the previous by its width + a word gap. Hyphens and
      // extenders below use the adjusted centers, so they stay aligned.
      final centers = <double>[];
      for (final lyric in lyrics) {
        final index = infoIndexOf[lyric.elementId];
        if (index == null || _tieInfos[index].note == null) {
          throw ArgumentError('$lyric references an unknown note element id');
        }
        final info = _tieInfos[index];
        centers.add((info.left + info.right) / 2);
      }
      _spreadRight(
        centers,
        [for (final l in lyrics) halfWidthOf(l.text)],
        0.4 * size,
      );

      for (var i = 0; i < lyrics.length; i++) {
        final lyric = lyrics[i];
        final centerX = centers[i];
        final halfWidth = halfWidthOf(lyric.text);
        _primitives.add(TextPrimitive(
          lyric.text,
          Point(centerX, baselineY),
          size: size,
          elementId: lyric.elementId,
        ));
        _expand(
          lyric.elementId,
          centerX - halfWidth,
          baselineY - 0.72 * size,
          centerX + halfWidth,
          baselineY + 0.25 * size,
        );

        if (lyric.hyphenToNext && i + 1 < lyrics.length) {
          // Dash centered between this syllable's end and the next one's
          // start, on the x-height line.
          final gapStart = centerX + halfWidth;
          final gapEnd = centers[i + 1] - halfWidthOf(lyrics[i + 1].text);
          if (gapEnd > gapStart + 0.2) {
            final mid = (gapStart + gapEnd) / 2;
            final dashHalf = min(0.3, (gapEnd - gapStart) / 4);
            _addLine(
              Point(mid - dashHalf, baselineY - 0.25 * size),
              Point(mid + dashHalf, baselineY - 0.25 * size),
              0.1,
              elementId: lyric.elementId,
            );
          }
        }

        if (lyric.extender) {
          // Extender runs along the baseline under the following voice-1
          // notes that carry no syllable of their own in this verse.
          final startIndex = infoIndexOf[lyric.elementId]!;
          double? endX;
          for (var j = startIndex + 1; j < _tieInfos.length; j++) {
            final info = _tieInfos[j];
            if (info.voice != 0 || info.note == null) continue;
            if (info.id != null && lyricIds.contains(info.id)) break;
            endX = info.right;
          }
          if (endX != null && endX > centerX + halfWidth + 0.2) {
            _addLine(
              Point(centerX + halfWidth + 0.15, baselineY),
              Point(endX, baselineY),
              0.1,
              elementId: lyric.elementId,
            );
          }
        }
      }
    }
  }

  /// v0.4.5: text annotations (chord symbols, tempo/rehearsal text) on a
  /// shared baseline above their note. The baseline clears only the ink within
  /// the horizontal span the annotations occupy (a per-column skyline), so a
  /// high note elsewhere on the line no longer lifts the whole chord-symbol row.
  void _layoutAnnotations() {
    if (score.annotations.isEmpty && score.chordSymbols.isEmpty) return;
    final size = s.annotationSize;

    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    // Text annotations and structured chord symbols share this above-staff row.
    final items = <(String, String)>[
      for (final a in score.annotations) (a.elementId, a.text),
      for (final c in score.chordSymbols) (c.elementId, c.text),
    ];
    // Gather each item's note-centered anchor and estimated half-width, then
    // order left-to-right and spread so wide symbols on close notes never
    // overlap.
    final placed = <(String, String, double, double)>[]; // id, text, ctr, half
    for (final (id, text) in items) {
      final info = infoOf[id];
      if (info == null || info.note == null) {
        throw ArgumentError(
            'annotation/chord symbol references an unknown note id: $id');
      }
      placed.add((
        id,
        text,
        (info.left + info.right) / 2,
        _estTextHalfWidth(text, size),
      ));
    }
    placed.sort((a, b) => a.$3.compareTo(b.$3));
    final centers = [for (final p in placed) p.$3];
    final halves = [for (final p in placed) p.$4];
    _spreadRight(centers, halves, 0.4 * size);

    // Text bottom (baseline + descender) clears the highest ink under the
    // span the row actually covers, not the whole system.
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (var i = 0; i < centers.length; i++) {
      regionL = min(regionL, centers[i] - halves[i]);
      regionR = max(regionR, centers[i] + halves[i]);
    }
    final localTop = _skylineTop(regionL, regionR) ?? 0;
    final baselineY = min(-1.0, localTop - s.annotationGap - 0.25 * size);

    for (var i = 0; i < placed.length; i++) {
      final (id, text, _, halfWidth) = placed[i];
      final centerX = centers[i];
      _primitives.add(TextPrimitive(
        text,
        Point(centerX, baselineY),
        size: size,
        elementId: id,
      ));
      _expand(
        id,
        centerX - halfWidth,
        baselineY - 0.72 * size,
        centerX + halfWidth,
        baselineY + 0.25 * size,
      );
    }
  }

  /// Figured-bass figures stacked under each bass note, below all other ink
  /// (so it clears lyrics when both are present). Figures in one column align
  /// to their note; rows stack downward.
  void _layoutFiguredBass() {
    if (score.figuredBass.isEmpty) return;
    const rowHeight = 1.7;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    // Clear only the ink under the figured bass's own note span (a per-column
    // skyline), not the whole system's lowest note.
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (final fb in score.figuredBass) {
      final info = infoOf[fb.noteId];
      if (info == null) continue;
      regionL = min(regionL, info.left);
      regionR = max(regionR, info.right);
    }
    final localBottom = _skylineBottom(regionL, regionR) ?? 4;
    final topBaseline = max(6.2, localBottom + s.lyricGap + 1.0);
    for (final fb in score.figuredBass) {
      final info = infoOf[fb.noteId];
      if (info == null || info.note == null) {
        throw ArgumentError('$fb references an unknown note element id');
      }
      final centerX = (info.left + info.right) / 2;
      for (var row = 0; row < fb.figures.length; row++) {
        final glyphs = _figuredBassGlyphs(fb.figures[row]);
        if (glyphs.isEmpty) continue;
        final widths = [for (final g in glyphs) _glyphWidth(g)];
        final total =
            widths.fold(0.0, (a, b) => a + b) + 0.1 * (glyphs.length - 1);
        final y = topBaseline + row * rowHeight;
        var x = centerX - total / 2;
        for (var k = 0; k < glyphs.length; k++) {
          _addGlyph(glyphs[k], x, y, elementId: fb.noteId);
          x += widths[k] + 0.1;
        }
      }
    }
  }

  /// Parses a figured-bass figure string (e.g. `6`, `#6`, `b7`, `4+`) into the
  /// SMuFL figured-bass glyphs to draw left-to-right. Digits map to
  /// `figbass0`–`figbass9`; `#`/`♯`, `b`/`♭`, `n`/`♮` and `+` to the
  /// alteration glyphs. Unknown characters are skipped.
  static List<String> _figuredBassGlyphs(String figure) {
    final out = <String>[];
    for (final ch in figure.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        out.add(SmuflGlyph.figbassDigit(code - 0x30));
      } else {
        switch (ch) {
          case '#':
          case '♯':
            out.add(SmuflGlyph.figbassSharp);
          case 'b':
          case '♭':
            out.add(SmuflGlyph.figbassFlat);
          case 'n':
          case '♮':
            out.add(SmuflGlyph.figbassNatural);
          case '+':
            out.add(SmuflGlyph.figbassPlus);
        }
      }
    }
    return out;
  }

  /// Breath marks / caesuras: a comma or "railroad tracks" just after the
  /// note, at the top of the staff.
  void _layoutBreathMarks() {
    if (score.breathMarks.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final bm in score.breathMarks) {
      final info = infoOf[bm.noteId];
      if (info == null || info.note == null) {
        throw ArgumentError('$bm references an unknown note element id');
      }
      final glyph = bm.symbol == BreathSymbol.comma
          ? SmuflGlyph.breathMarkComma
          : SmuflGlyph.caesura;
      // Just after the note, sitting at (comma) or above (caesura) the top line.
      final x = info.right + 0.35;
      final y = bm.symbol == BreathSymbol.comma ? 0.0 : -0.5;
      _addGlyph(glyph, x, y, elementId: bm.noteId);
    }
  }

  /// Educational note-name overlay ([LayoutEngine.layout] `showNoteNames`): the
  /// pitch letter under each note, in a row below the staff (a chord stacks its
  /// letters top-to-bottom). Derived from the score, so it renders in both the
  /// Flutter and SVG back-ends.
  void _layoutNoteNames() {
    if (!showNoteNames) return;
    final size = s.lyricSize * 0.85;
    final baseline = max(6.5, _ink.maxY + s.lyricGap + 0.72 * size);
    final rowHeight = size * 1.1;
    for (final info in _tieInfos) {
      final note = info.note;
      if (note == null || note.pitches.isEmpty) continue;
      final centerX = (info.left + info.right) / 2;
      // Pitches are stored low→high; stack the names with the top pitch first.
      final names = [for (final p in note.pitches) _noteName(p)];
      for (var r = 0; r < names.length; r++) {
        final text = names[names.length - 1 - r];
        final y = baseline + r * rowHeight;
        final half = _estTextHalfWidth(text, size);
        _primitives.add(TextPrimitive(
          text,
          Point(centerX, y),
          size: size,
          elementId: info.id,
        ));
        _expand(info.id, centerX - half, y - 0.72 * size, centerX + half,
            y + 0.25 * size);
      }
    }
  }

  /// Educational rhythm-count overlay ([LayoutEngine.layout] `showBeatNumbers`):
  /// the beat number (`1`, `2`, …) above each note that lands on a beat, and
  /// `+` on the half-beat "and", in a row above all other ink.
  void _layoutBeatNumbers() {
    if (!showBeatNumbers) return;
    final size = s.lyricSize * 0.8;
    final baseline = min(-1.5, _ink.minY - 0.4 - 0.25 * size);
    final infoById = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    var meter = score.timeSignature;
    for (final measure in score.measures) {
      meter = measure.timeChange ?? meter;
      if (meter == null) continue;
      var onset = Fraction.zero;
      for (var i = 0; i < measure.elements.length; i++) {
        final element = measure.elements[i];
        final dur = measure.effectiveDurationAt(i);
        if (element is NoteElement && element.id != null) {
          final info = infoById[element.id];
          final label = _beatLabel(onset, meter.beatUnit);
          if (info != null && info.note != null && label != null) {
            final centerX = (info.left + info.right) / 2;
            final half = _estTextHalfWidth(label, size);
            _primitives.add(TextPrimitive(
              label,
              Point(centerX, baseline),
              size: size,
              elementId: element.id,
            ));
            _expand(element.id, centerX - half, baseline - 0.72 * size,
                centerX + half, baseline + 0.25 * size);
          }
        }
        onset += dur;
      }
    }
  }

  /// Measure-number overlay ([LayoutEngine.layout] `showMeasureNumbers`): a
  /// small bar number above the start of each measure. Pickups (anacruses) are
  /// unnumbered and don't advance the count, so the first full bar reads `1`.
  void _layoutMeasureNumbers() {
    if (!showMeasureNumbers) return;
    final size = s.lyricSize * 0.8;
    final baseline = min(-2.0, _ink.minY - 0.6 - 0.25 * size);
    final infoById = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    var barNo = 0;
    for (final measure in score.measures) {
      if (measure.pickup) continue; // anacrusis: uncounted, unnumbered
      barNo++;
      // Anchor at the leftmost laid-out element of the measure.
      _TieInfo? anchor;
      for (final element in measure.elements) {
        final info = element.id == null ? null : infoById[element.id];
        if (info != null) {
          anchor = info;
          break;
        }
      }
      if (anchor == null) continue;
      final label = '$barNo';
      final half = _estTextHalfWidth(label, size);
      final x = anchor.left + half;
      _primitives.add(TextPrimitive(
        label,
        Point(x, baseline),
        size: size,
        elementId: anchor.id,
      ));
      _expand(anchor.id, x - half, baseline - 0.72 * size, x + half,
          baseline + 0.25 * size);
    }
  }

  /// The counting label for a note [onset] whole notes into its measure: the
  /// beat number on a beat, `+` on the half-beat, else null (finer offbeats).
  static String? _beatLabel(Fraction onset, int beatUnit) {
    final beats = onset * Fraction(beatUnit, 1);
    if (beats.denominator == 1) return '${beats.numerator + 1}';
    if (beats.denominator == 2) return '+';
    return null;
  }

  /// The letter name of [pitch] with any accidental (`C`, `F#`, `Bb`, `Gx`).
  static String _noteName(Pitch pitch) {
    final letter = pitch.step.name.toUpperCase();
    final alter = pitch.alter;
    final accidental = switch (alter) {
      0 => '',
      2 => 'x',
      -2 => 'bb',
      _ => alter > 0 ? '#' * alter : 'b' * -alter,
    };
    return '$letter$accidental';
  }

  /// Jazz / brass articulations (scoop, doit, fall, plop): a small brass
  /// glyph just before or after the notehead, at the notehead's height.
  void _layoutJazzArticulations() {
    if (score.jazzMarks.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final mark in score.jazzMarks) {
      final info = infoOf[mark.noteId];
      if (info == null || info.note == null || info.heads.isEmpty) {
        throw ArgumentError('$mark references an unknown note element id');
      }
      // Vertical anchor: the notehead nearest the gesture — the top head for
      // marks that rise (doit/plop), the bottom head for those that fall.
      final ys = [for (final h in info.heads) h.$4];
      final topY = ys.reduce(min);
      final bottomY = ys.reduce(max);
      final glyph = switch (mark.type) {
        JazzArticulation.scoop => SmuflGlyph.brassScoop,
        JazzArticulation.doit => SmuflGlyph.brassDoitMedium,
        JazzArticulation.fall => SmuflGlyph.brassFallLipShort,
        JazzArticulation.plop => SmuflGlyph.brassPlop,
      };
      final rises = mark.type == JazzArticulation.doit ||
          mark.type == JazzArticulation.plop;
      final y = rises ? topY - 0.4 : bottomY + 0.4;
      final w = _glyphWidth(glyph);
      final x = mark.type.isBefore ? info.left - 0.3 - w : info.right + 0.3;
      _addGlyph(glyph, x, y, elementId: mark.noteId);
    }
  }

  /// Chord/fretboard diagrams placed above their note, on a shared baseline
  /// above all other ink (all diagrams align in one row).
  void _layoutChordDiagrams() {
    if (score.chordDiagrams.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    // Clear only the ink under the diagrams' own span.
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (final placed in score.chordDiagrams) {
      final info = infoOf[placed.elementId];
      if (info == null) continue;
      regionL = min(regionL, info.left);
      regionR = max(regionR, info.right);
    }
    final localTop = _skylineTop(regionL, regionR) ?? 0;
    final bottomY = localTop - s.annotationGap - 0.3;
    for (final placed in score.chordDiagrams) {
      final info = infoOf[placed.elementId];
      if (info == null || info.note == null) {
        throw ArgumentError('$placed references an unknown note element id');
      }
      final centerX = (info.left + info.right) / 2;
      final (prims, l, t, r, b) = placeChordDiagram(
        placed.diagram,
        s,
        centerX: centerX,
        bottomY: bottomY,
        scale: placed.scale,
      );
      _primitives.addAll(prims);
      _expand(placed.elementId, l, t, r, b);
    }
  }

  // -------------------------------------------------------------- barlines

  /// v0.3.8: mid-score clef/key/time changes drawn at the measure start.
  void _applyMeasureChanges(Measure measure) {
    final clefChange = measure.clefChange;
    if (clefChange != null && clefChange != _clef) {
      _clef = clefChange;
      final (glyph, position) = _clefGlyph(_clef);
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

  /// v0.7.1: navigation marks above the staff, all on one shared clearance
  /// line (as engravers align them per system). Targets
  /// ([NavigationMark.segno]/[NavigationMark.coda]) draw their SMuFL glyph at
  /// the measure's left edge; every instruction draws its text word
  /// ([SmuflGlyph.navigationLabel]) right-aligned above the closing barline.
  void _layoutNavigation() {
    final marks = <(MeasureRegion, NavigationMark)>[
      for (final region in _measureRegions)
        if (score.measures[region.index].navigation case final mark?)
          (region, mark),
    ];
    if (marks.isEmpty) return;
    // One clearance line for the marks: a fixed gap above the ink under the
    // span they occupy (not the whole system's tallest note).
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (final (region, _) in marks) {
      regionL = min(regionL, region.startX);
      regionR = max(regionR, region.endX);
    }
    final localTop = _skylineTop(regionL, regionR) ?? 0;
    final clearance = min(-1.0, localTop - s.navigationGap);
    for (final (region, mark) in marks) {
      final glyph = SmuflGlyph.navigationGlyph(mark);
      if (glyph != null) {
        // Baseline so the (y-up) bbox bottom lands on `clearance`; the tall
        // segno/coda glyph then sits entirely above the staff.
        _addGlyph(glyph, region.startX, clearance + meta.bBoxOf(glyph).swY);
        continue;
      }
      final label = SmuflGlyph.navigationLabel(mark)!;
      final size = s.navigationSize;
      final halfWidth = 0.25 * size * label.length;
      final centerX = region.endX - 0.3 - halfWidth;
      // Baseline so the text's descender rests on `clearance`.
      final baselineY = clearance - 0.25 * size;
      _primitives
          .add(TextPrimitive(label, Point(centerX, baselineY), size: size));
      _expand(
        null,
        centerX - halfWidth,
        baselineY - 0.72 * size,
        centerX + halfWidth,
        clearance,
      );
    }
  }

  /// A mid-score barline in the requested [style] (the measure's right edge).
  void _addBarline(BarlineStyle style) {
    switch (style) {
      case BarlineStyle.normal:
        _addLine(Point(_x, 0), Point(_x, 4), s.thinBarlineThickness);
        _x += s.thinBarlineThickness + s.barlineGap;
      case BarlineStyle.doubleBar:
        _addLine(Point(_x, 0), Point(_x, 4), s.thinBarlineThickness);
        final x2 = _x + s.thinBarlineThickness + s.barlineSeparation;
        _addLine(Point(x2, 0), Point(x2, 4), s.thinBarlineThickness);
        _x = x2 + s.thinBarlineThickness + s.barlineGap;
      case BarlineStyle.finalBar:
        _addLine(Point(_x, 0), Point(_x, 4), s.thinBarlineThickness);
        final xt = _x +
            s.thinBarlineThickness / 2 +
            s.barlineSeparation +
            s.thickBarlineThickness / 2;
        _addLine(Point(xt, 0), Point(xt, 4), s.thickBarlineThickness);
        _x = xt + s.thickBarlineThickness / 2 + s.barlineGap;
      case BarlineStyle.heavy:
        final xt = _x + s.thickBarlineThickness / 2;
        _addLine(Point(xt, 0), Point(xt, 4), s.thickBarlineThickness);
        _x = xt + s.thickBarlineThickness / 2 + s.barlineGap;
      case BarlineStyle.dashed:
        _addSegmentedBarline(dash: 0.5, gap: 0.4, round: false);
      case BarlineStyle.dotted:
        _addSegmentedBarline(dash: 0.02, gap: 0.32, round: true);
      case BarlineStyle.none:
        _x += s.barlineGap;
    }
  }

  /// A vertical barline drawn as short segments (dashed or, with [round],
  /// dotted), spanning the five staff lines.
  void _addSegmentedBarline(
      {required double dash, required double gap, required bool round}) {
    var y = 0.0;
    while (y <= 4 + 1e-9) {
      _addLine(
          Point(_x, y), Point(_x, min(y + dash, 4)), s.thinBarlineThickness,
          round: round);
      y += dash + gap;
    }
    _x += s.thinBarlineThickness + s.barlineGap;
  }

  /// Rule 13: `barlineFinal` (thin + thick) at the end; returns the width.
  /// With [finalBarline] false (systems that continue on the next line)
  /// a plain thin barline closes the layout instead.
  double _addFinalBarline() {
    // An explicit barline style on the last measure wins (a double bar, dashed
    // divider, or no barline ending a section) — honored even at a system
    // break. Only the default thin+thick "end of piece" is suppressed on a
    // continuation system (where the score's real end is elsewhere).
    final last = score.measures.isEmpty ? null : score.measures.last;
    if (last != null &&
        !last.endRepeat &&
        last.barline != BarlineStyle.normal) {
      _addBarline(last.barline);
      return _x;
    }
    final thinX = _x;
    _addLine(Point(thinX, 0), Point(thinX, 4), s.thinBarlineThickness);
    if (!finalBarline) return thinX + s.thinBarlineThickness / 2;
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
  List<_BeamGroup> _computeBeamGroups(
    List<MusicElement> elements, {
    required Fraction Function(int index) effectiveAt,
    required List<TupletSpan> tuplets,
    bool? forcedStemsDown,
  }) {
    final time = _time;
    // Unmetered scores group per quarter-note window.
    final span = time == null ? Fraction(1, 4) : Fraction(1, time.beatUnit);
    final halfSpan = Fraction(1, 2);

    // Which tuplet span (by list index) an element belongs to, or -1.
    int spanOf(int index) {
      for (var t = 0; t < tuplets.length; t++) {
        if (tuplets[t].contains(index)) return t;
      }
      return -1;
    }

    // Feathered spans (by note id) covering this element list: force each
    // into its own group and exclude its notes from normal beaming.
    final idIndex = <String, int>{
      for (var i = 0; i < elements.length; i++)
        if (elements[i].id case final id?) id: i,
    };
    final feathers = <(int, int, int, int)>[]; // start, end, begin, endBeams
    final slants = <(int, int, double)>[]; // start, end, slant
    final claimed = <int>{};
    for (final fb in score.featheredBeams) {
      final a = idIndex[fb.startId];
      final b = idIndex[fb.endId];
      if (a == null || b == null || b <= a) continue;
      feathers.add((a, b, fb.beginBeams, fb.endBeams));
      for (var i = a; i <= b; i++) {
        claimed.add(i);
      }
    }
    for (final bs in score.beamSlants) {
      final a = idIndex[bs.startId];
      final b = idIndex[bs.endId];
      if (a == null || b == null || b <= a || claimed.contains(a)) continue;
      slants.add((a, b, bs.slant));
      for (var i = a; i <= b; i++) {
        claimed.add(i);
      }
    }

    var onset = Fraction.zero;
    final runs = <List<int>>[];
    final onsets = <Fraction>[];
    List<int>? current;
    int? currentWindow;
    int? currentSpan;

    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      onsets.add(onset);
      final beamable = element is NoteElement &&
          _beamCountOf(element.duration.base) >= 1 &&
          !claimed.contains(i);
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
      } else if (element is RestElement) {
        // A rest does not break a beam on its own: if beamable notes continue
        // within the same beat window, the beam passes over the rest (the
        // rest's index is never added, so the beam simply spans the gap). The
        // window/tuplet check when the next note arrives re-attaches it or
        // starts a fresh run, so a rest at a beat boundary still separates.
      } else {
        current = null;
        currentWindow = null;
        currentSpan = null;
      }
      onset += effectiveAt(i);
    }

    // Merge adjacent all-eighth beat groups within the same half measure
    // (tuplet groups never merge).
    if (time != null && time.beatUnit == 4 && time.beats.isEven) {
      bool allEighths(List<int> run) => run.every((i) =>
          (elements[i] as NoteElement).duration.base == DurationBase.eighth);
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
      final bool stemsDown;
      if (forcedStemsDown != null) {
        stemsDown = forcedStemsDown;
      } else {
        var maxAbove = -100;
        var maxBelow = -100;
        for (final i in run) {
          final note = elements[i] as NoteElement;
          for (final pitch in note.pitches) {
            final p = pitch.staffPosition(_clef);
            if (p - 4 > maxAbove) maxAbove = p - 4;
            if (4 - p > maxBelow) maxBelow = 4 - p;
          }
        }
        stemsDown = maxAbove >= maxBelow;
      }
      groups.add(_BeamGroup(run,
          onsets: [for (final i in run) onsets[i]], stemsDown: stemsDown));
    }

    bool stemsDownFor(List<int> run) {
      if (forcedStemsDown != null) return forcedStemsDown;
      var maxAbove = -100;
      var maxBelow = -100;
      for (final i in run) {
        for (final pitch in (elements[i] as NoteElement).pitches) {
          final p = pitch.staffPosition(_clef);
          if (p - 4 > maxAbove) maxAbove = p - 4;
          if (4 - p > maxBelow) maxBelow = 4 - p;
        }
      }
      return maxAbove >= maxBelow;
    }

    for (final (a, b, begin, end) in feathers) {
      final run = [for (var i = a; i <= b; i++) i];
      groups.add(_BeamGroup(run,
          onsets: [for (final i in run) onsets[i]],
          stemsDown: stemsDownFor(run),
          feather: (begin, end)));
    }
    for (final (a, b, slant) in slants) {
      final run = [for (var i = a; i <= b; i++) i];
      groups.add(_BeamGroup(run,
          onsets: [for (final i in run) onsets[i]],
          stemsDown: stemsDownFor(run),
          forcedSlant: slant));
    }
    return groups;
  }

  /// The notehead glyph for a [shape] at a [base] duration — the shape picks
  /// the family, the duration the filled/open/whole/double-whole variant.
  static String _noteheadGlyph(NoteheadShape shape, DurationBase base) {
    // How "open" the head is: 0 filled (quarter-), 1 half, 2 whole, 3 breve.
    final level = switch (base) {
      DurationBase.breve => 3,
      DurationBase.whole => 2,
      DurationBase.half => 1,
      _ => 0,
    };
    switch (shape) {
      case NoteheadShape.normal:
        return const [
          SmuflGlyph.noteheadBlack,
          SmuflGlyph.noteheadHalf,
          SmuflGlyph.noteheadWhole,
          SmuflGlyph.noteheadDoubleWhole,
        ][level];
      case NoteheadShape.x:
        return const [
          SmuflGlyph.noteheadXBlack,
          SmuflGlyph.noteheadXHalf,
          SmuflGlyph.noteheadXWhole,
          SmuflGlyph.noteheadXDoubleWhole,
        ][level];
      case NoteheadShape.diamond:
        return const [
          SmuflGlyph.noteheadDiamondBlack,
          SmuflGlyph.noteheadDiamondHalf,
          SmuflGlyph.noteheadDiamondWhole,
          SmuflGlyph.noteheadDiamondDoubleWhole,
        ][level];
      case NoteheadShape.triangleUp:
        return const [
          SmuflGlyph.noteheadTriangleUpBlack,
          SmuflGlyph.noteheadTriangleUpHalf,
          SmuflGlyph.noteheadTriangleUpWhole,
          SmuflGlyph.noteheadTriangleUpDoubleWhole,
        ][level];
      case NoteheadShape.slash:
        // Slash heads have no separate durational variants in this subset.
        return SmuflGlyph.noteheadSlashVerticalEnds;
      case NoteheadShape.circleX:
        return SmuflGlyph.noteheadCircleX;
    }
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

  /// Whether the notes at [a] and [b] sit in different [sub]-sized metric
  /// windows — i.e. a metric subdivision boundary falls between them. Always
  /// false when [sub] is null (subdivision disabled, e.g. unmetered scores).
  static bool _crossesSubdivision(
          List<Fraction> onsets, Fraction? sub, int a, int b) =>
      sub != null &&
      _windowIndex(onsets[a], sub) != _windowIndex(onsets[b], sub);

  /// Beam geometry: a straight beam through the stem tips, slant clamped to
  /// ±1 staff space over the group, intercept chosen so every stem keeps at
  /// least the default length. [BeamPrimitive] points are the midpoints of
  /// the beam's end edges; stems run to the beam's center line.
  void _layoutBeamGroup(
    List<_BeamedNote> notes, {
    required bool stemsDown,
    required List<Fraction> onsets,
    (int, int)? feather,
    double? forcedSlant,
  }) {
    final first = notes.first;
    final last = notes.last;
    final dx = last.stemX - first.stemX;
    final slant =
        forcedSlant ?? ((last.refY - first.refY) / 2).clamp(-1.0, 1.0);
    final slope = dx == 0 ? 0.0 : slant / dx;

    // Multi-level groups (32nds/64ths) need longer stems so the extra
    // beams stay clear of the noteheads. A feathered group reserves room for
    // its widest fan end instead.
    final maxLevel = feather == null
        ? notes.map((n) => n.beamCount).reduce(max)
        : max(feather.$1, feather.$2);
    final stemLength = s.stemLength + _stemExtension(maxLevel);
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

    // v0.7 Phase 1.4: feathered (fanned) beam — the extra beams converge on
    // the primary at the "few" end and spread by one step per level at the
    // "many" end (accelerando if growing left→right, ritardando if not).
    if (feather != null) {
      final step = (s.beamThickness + s.beamSpacing) * (stemsDown ? -1 : 1);
      final lo = min(feather.$1, feather.$2);
      final hi = max(feather.$1, feather.$2);
      final growing = feather.$2 > feather.$1;
      for (var level = 2; level <= hi; level++) {
        final off = step * (level - 1);
        final double y1;
        final double y2;
        if (level <= lo) {
          y1 = beamY(first.stemX) + off;
          y2 = beamY(last.stemX) + off;
        } else if (growing) {
          y1 = beamY(first.stemX);
          y2 = beamY(last.stemX) + off;
        } else {
          y1 = beamY(first.stemX) + off;
          y2 = beamY(last.stemX);
        }
        _addBeam(
            Point(first.stemX, y1), Point(last.stemX, y2), s.beamThickness);
      }
      return;
    }

    // Secondary/tertiary/quaternary beams, offset toward the noteheads. They
    // break at the quarter-note metric point, so a group spanning more than a
    // quarter (e.g. a half-note beat in cut time) shows the sub-pulse rather
    // than one over-long secondary beam. In simple x/4 meters beam groups never
    // exceed a quarter, so this never fires there.
    final subdivision = _time == null ? null : Fraction(1, 4);
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
        while (j + 1 < notes.length &&
            notes[j + 1].beamCount >= level &&
            !_crossesSubdivision(onsets, subdivision, j, j + 1)) {
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
