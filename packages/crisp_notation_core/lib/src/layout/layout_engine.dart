/// The layout engine: turns a [Score] into a [ScoreLayout]
/// (see docs/CONTRACT.md for the engraving rules).
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

part 'layout_engine_data.dart';
part 'layout_beaming.dart';
part 'layout_spans.dart';
part 'layout_furniture.dart';
part 'layout_annotations.dart';
part 'layout_barlines.dart';
part 'layout_tuplets.dart';
part 'layout_marks.dart';
part 'layout_overlays.dart';

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
  ///
  /// [targetWidth], when set, pads the final staff width and closing barline
  /// to at least that value without stretching note spacing.
  ScoreLayout layout(
    Score score,
    LayoutSettings settings, {
    double? leadingWidth,
    List<double>? measureWidths,
    double? targetWidth,
    double spacingStretch = 1.0,
    bool drawTimeSignature = true,
    bool finalBarline = true,
    bool showNoteNames = false,
    NoteNameStyle noteNameStyle = NoteNameStyle.letter,
    bool showBeatNumbers = false,
    bool showMeasureNumbers = false,
    int measureNumberInterval = 1,
    Map<String, bool> deferredStems = const {},
    List<Map<Fraction, double>>? forcedColumns,
    int staffLineCount = 5,
  }) =>
      _LayoutBuilder(score, settings,
              leadingWidth: leadingWidth,
              measureWidths: measureWidths,
              targetWidth: targetWidth,
              spacingStretch: spacingStretch,
              drawTimeSignature: drawTimeSignature,
              finalBarline: finalBarline,
              showNoteNames: showNoteNames,
              noteNameStyle: noteNameStyle,
              showBeatNumbers: showBeatNumbers,
              showMeasureNumbers: showMeasureNumbers,
              measureNumberInterval: measureNumberInterval,
              deferredStems: deferredStems,
              forcedColumns: forcedColumns,
              staffLineCount: staffLineCount)
          .build();
}

class _LayoutBuilder {
  final Score score;
  final LayoutSettings s;
  final double? leadingWidth;
  final List<double>? measureWidths;
  final double? targetWidth;
  final double spacingStretch;
  final bool drawTimeSignature;
  final bool finalBarline;
  final bool showNoteNames;
  final NoteNameStyle noteNameStyle;
  final bool showBeatNumbers;
  final bool showMeasureNumbers;
  final int measureNumberInterval;

  /// Number of staff lines (5 for an ordinary notation staff; 1 for a neutral
  /// percussion line, etc.). Drives every vertical staff reference below.
  final int staffLineCount;

  SmuflMetadata get meta => s.metadata;

  /// Staff position of the top line (bottom line is position 0; each position
  /// step is half a staff space). 8 for a 5-line staff.
  int get _topPosition => 2 * (staffLineCount - 1);

  /// Staff position of the middle line — the reference for stem direction.
  /// 4 for a 5-line staff.
  double get _middlePosition => (staffLineCount - 1).toDouble();

  /// y of the middle line — the reference for stem-length clamps. 2 for a
  /// 5-line staff.
  double get _middleY => (staffLineCount - 1) / 2;

  /// y of a staff [position] (position 0 = bottom line → y = staffLineCount−1;
  /// y grows downward). For a 5-line staff this is `(8 − position) / 2`.
  double _yOf(num position) => (_topPosition - position) / 2;

  final List<LayoutPrimitive> _primitives = [];
  final Map<String, _Bounds> _elementBounds = {};
  final List<MeasureRegion> _measureRegions = [];
  final List<_TieInfo> _tieInfos = [];

  /// Index into [_tieInfos] of the note-carrying entry for each element id,
  /// built once (lazily, after all measures are laid out). The span/mark
  /// post-passes look their endpoints up here in O(1); without it each of the
  /// dozen passes did a linear `indexWhere` per span, making a score with a
  /// mark on every note O(n²). See [_tieIndexOf].
  late final Map<String, int> _tieIndexById = {
    for (var i = 0; i < _tieInfos.length; i++)
      if (_tieInfos[i].note != null && _tieInfos[i].id != null)
        _tieInfos[i].id!: i,
  };

  /// The [_tieInfos] index of the note with [id], or -1 — the O(1) replacement
  /// for `_tieInfos.indexWhere((i) => i.note != null && i.id == id)`.
  int _tieIndexOf(String? id) => id == null ? -1 : (_tieIndexById[id] ?? -1);

  final _Bounds _ink = _Bounds();

  // Cross-measure beaming: the note ids each cross-measure beam claims (excluded
  // from per-measure beaming), the beam each belongs to and its stem direction,
  // and the deferred stem data gathered across measures for a post-pass.
  final Set<String> _crossMeasureIds = {};
  // Note ids drawn small (cue / ossia notes).
  late final Set<String> _cueIds = score.cueNoteIds.toSet();
  // Per-note-id widest lyric-syllable half-width, so a wide syllable can widen
  // the note spacing (lyric-driven spacing) rather than only nudging text.
  late final Map<String, double> _lyricHalfWidths = () {
    final map = <String, double>{};
    for (final lyric in score.lyrics) {
      final w = _estTextHalfWidth(lyric.text, s.lyricSize);
      if (w > (map[lyric.elementId] ?? 0)) map[lyric.elementId] = w;
    }
    return map;
  }();
  final Map<String, CrossMeasureBeam> _crossBeamOf = {};
  final Map<CrossMeasureBeam, bool> _crossBeamStemsDown = {};
  final Map<CrossMeasureBeam, List<_BeamedNote>> _crossBeamNotes = {};

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

  /// Element ids whose stem/flag are deferred (drawn later by a cross-staff
  /// beam pass): id → whether that note stems down. Their stubs are collected
  /// into [_crossStaffStubs].
  final Map<String, bool> deferredStems;

  /// Optional shared column table for cross-staff onset gridding (§2.9): one
  /// map per measure, from an element's onset (a [Fraction] from the measure
  /// start) to its x offset from the measure's content start. When set, each
  /// single-voice element is placed at its onset's column instead of advancing
  /// sequentially, so simultaneous notes on different staves share an x. The
  /// key at the measure's total duration positions the closing barline.
  final List<Map<Fraction, double>>? forcedColumns;

  /// Stem anchors of the [deferredStems] notes, keyed by element id.
  final Map<String, CrossStaffStub> _crossStaffStubs = {};

  _LayoutBuilder(this.score, this.s,
      {this.leadingWidth,
      this.measureWidths,
      this.targetWidth,
      this.spacingStretch = 1.0,
      this.drawTimeSignature = true,
      this.finalBarline = true,
      this.showNoteNames = false,
      this.noteNameStyle = NoteNameStyle.letter,
      this.showBeatNumbers = false,
      this.showMeasureNumbers = false,
      this.measureNumberInterval = 1,
      this.deferredStems = const {},
      this.forcedColumns,
      this.staffLineCount = 5});

  // log2(dot factor) for 0..2 dots: 1, 3/2, 7/4.
  static const List<double> _dotLog2 = [
    0.0,
    0.5849625007211562,
    0.8073549220576042
  ];

  ScoreLayout build() {
    _prepareCrossMeasureBeams();
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
      _layoutMeasure(measure, i);
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
    _layoutCrossMeasureBeams();
    _layoutTies();
    _layoutLaissezVibrer();
    _layoutDynamics();
    _layoutSlurs();
    _layoutGlissandos();
    _layoutPortamentos();
    _layoutOttavas();
    _layoutTrillExtensions();
    _layoutPedals();
    _layoutLyrics();
    _layoutFiguredBass();
    _layoutNoteNames();
    _layoutNavigation();
    _layoutAnnotations();
    _layoutJazzArticulations();
    _layoutPalmMuteLetRing();
    _layoutNotationVibrato();
    _layoutBreathMarks();
    _layoutChordDiagrams();
    _layoutBeatNumbers();
    _layoutMeasureNumbers();
    final width = _addFinalBarline();

    // Staff lines span the full width; paint them first.
    final staffLines = [
      for (var line = 0; line < staffLineCount; line++)
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
      (staffLineCount - 1) + s.staffLineThickness / 2,
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
      crossStaffStubs: Map.unmodifiable(_crossStaffStubs),
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

  void _drawTimeSig(TimeSignature time) {
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

  /// Whether [element]'s stem is deferred to the cross-staff beam pass.
  bool _isCrossStaff(NoteElement element) =>
      element.id != null && deferredStems.containsKey(element.id);

  /// Records the stem stub of a cross-staff [beamed] note under [id].
  void _recordCrossStaffStub(String? id, _BeamedNote? beamed) {
    if (id != null && beamed != null) {
      _crossStaffStubs[id] = CrossStaffStub(
        stemX: beamed.stemX,
        attachY: beamed.attachY,
        beamCount: beamed.beamCount,
      );
    }
  }

  void _layoutMeasure(Measure measure, int measureIndex) {
    _validateTuplets(measure);
    if (measure.multiRest != null) {
      _layoutMultiRest(measure.multiRest!);
      return;
    }
    if (measure.measureRepeat != null) {
      _layoutMeasureRepeat(measure.measureRepeat!);
      return;
    }
    if (measure.voices.length > 1) {
      _layoutMultiVoiceMeasure(measure, measureIndex);
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

    // §2.9 cross-staff gridding: when a shared column table is supplied, each
    // element is placed at its onset's column (from the measure's content
    // start) instead of advancing sequentially, so simultaneous notes on other
    // staves share its x.
    final columns =
        forcedColumns != null && measureIndex < forcedColumns!.length
            ? forcedColumns![measureIndex]
            : null;
    final measureContentStart = _x;
    var onset = Fraction.zero;

    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      final log2Adjust = _tupletLog2Adjust(measure, i);
      tieIndexOf[i] = _tieInfos.length;
      // The grid column x is the notehead position (accidental-aware): the
      // note anchors its head there via noteXOverride and its accidental
      // extends left; a rest anchors its ink there via _x.
      final columnX = columns == null ? null : columns[onset];
      if (columnX != null) _x = measureContentStart + columnX;
      _applyInlineClefs(measure, onset);
      final columnNoteX = columnX == null ? null : _x;
      onset += measure.effectiveDurationAt(i);
      switch (element) {
        case NoteElement():
          final crossStaff = _isCrossStaff(element);
          final cm = crossStaff ? null : _crossBeamOf[element.id];
          final group = (crossStaff || cm != null) ? null : beamedIndex[i];
          final result = _layoutNote(
            element,
            written,
            stemsDownOverride: crossStaff
                ? deferredStems[element.id]
                : (group?.stemsDown ??
                    (cm != null ? _crossBeamStemsDown[cm] : null)),
            deferStem: crossStaff || cm != null || group != null,
            noteXOverride: columnNoteX,
          );
          if (crossStaff) {
            _recordCrossStaffStub(element.id, result.beamed);
          } else if (group != null && result.beamed != null) {
            deferred.putIfAbsent(group, () => []).add(result.beamed!);
          } else if (cm != null && result.beamed != null) {
            _crossBeamNotes.putIfAbsent(cm, () => []).add(result.beamed!);
          }
          _advance(result.noteX, result.inkRight, element.duration, log2Adjust,
              lyricReserve: _lyricReserveFor(element.id));
        case RestElement():
          final result = _layoutRest(element);
          _advance(result.noteX, result.inkRight, element.duration, log2Adjust);
      }
    }

    // Advance to the SHARED measure-end column (the largest onset across ALL
    // voices/staves in this measure), not just this voice's own content end, so
    // a voice whose measure is short (e.g. a 3/8 final bar under 4/4 others)
    // still draws its barline at the aligned full-measure x instead of
    // mid-measure. For a normal full measure `onset == measureEnd`, so this is
    // unchanged.
    if (columns != null && columns.isNotEmpty) {
      final measureEnd = columns.keys.reduce((a, b) => a > b ? a : b);
      final endX = columns[measureEnd];
      if (endX != null) _x = max(_x, measureContentStart + endX);
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
  void _layoutMultiVoiceMeasure(Measure measure, int measureIndex) {
    final voices = measure.voices;
    final n = voices.length;
    // §2.9: shared cross-staff column table (onset → x from measure start).
    final forced = forcedColumns != null && measureIndex < forcedColumns!.length
        ? forcedColumns![measureIndex]
        : null;
    final measureContentStart = _x;
    Fraction effectiveAt(int voice, int index) =>
        measure.effectiveDurationAt(index, voice: voice);

    final groupsPerVoice = [
      for (var v = 0; v < n; v++)
        _computeBeamGroups(
          voices[v],
          effectiveAt: (i) => effectiveAt(v, i),
          tuplets: measure.tupletsForVoice(v),
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
      // Force this column onto the shared cross-staff grid when supplied.
      if (forced != null && forced[onset] != null) {
        _x = measureContentStart + forced[onset]!;
      }
      _applyInlineClefs(measure, onset);
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
              final show = el.showAccidental ??
                  (pitch.microtone != null || pitch.alter != implied);
              if (show) {
                jointShown.add((pitch, _writtenPosition(pitch, el.id), el.id));
                if (pitch.microtone == null) written[key] = pitch.alter;
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
            _x = columnX + _glyphWidth(SmuflGlyph.noteheadWhole) + 0.55;
          }
        }
        switch (element) {
          case NoteElement():
            final crossStaff = _isCrossStaff(element);
            final cm = crossStaff ? null : _crossBeamOf[element.id];
            final group =
                (crossStaff || cm != null) ? null : beamedIndexPerVoice[v][i];
            final result = _layoutNote(
              element,
              written,
              stemsDownOverride: crossStaff
                  ? deferredStems[element.id]
                  : (group?.stemsDown ??
                      (cm != null ? _crossBeamStemsDown[cm] : v.isOdd)),
              deferStem: crossStaff || cm != null || group != null,
              voice: v,
              noteXOverride: columnNoteX,
            );
            if (crossStaff) {
              _recordCrossStaffStub(element.id, result.beamed);
            } else if (group != null && result.beamed != null) {
              deferred.putIfAbsent(group, () => []).add(result.beamed!);
            } else if (cm != null && result.beamed != null) {
              _crossBeamNotes.putIfAbsent(cm, () => []).add(result.beamed!);
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

    // The shared measure-end column fixes the trailing width so barlines align.
    if (forced != null && forced[measureEnd] != null) {
      _x = max(_x, measureContentStart + forced[measureEnd]!);
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

  /// Measure-repeat (simile) sign — the SMuFL repeat-bar glyph centred in the
  /// bar (2/4-bar variants carry their own "2"/"4" above the slash).
  void _layoutMeasureRepeat(int count) {
    const barWidth = 4.0;
    final left = _x + 0.6;
    final right = _x + 0.6 + barWidth;
    final glyph = SmuflGlyph.measureRepeat(count);
    final w = _glyphWidth(glyph);
    _addGlyph(glyph, (left + right) / 2 - w / 2, 2.0); // centred on the staff
    _x = right + 0.6;
  }

  /// log2(normal/actual) for the element's tuplet span; spacing shrinks
  /// tuplet members to their sounding width.
  double _tupletLog2Adjust(Measure measure, int index) {
    for (final span in measure.tuplets) {
      if (span.voice == 0 && span.contains(index)) {
        return log(span.normal / span.actual) / ln2;
      }
    }
    return 0;
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
      final width = _glyphWidth(_accidentalGlyphOf(shown[i].$1));
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

  /// The accidental glyph for [p]: a microtonal (quarter-tone) glyph when the
  /// pitch carries one — remappable via [LayoutSettings.microtonalGlyphs] — else
  /// the standard glyph for its semitone alteration.
  String _accidentalGlyphOf(Pitch p) => p.microtone != null
      ? (s.microtonalGlyphs[p.microtone!] ?? p.microtone!.defaultGlyph)
      : SmuflGlyph.accidentalFor(p.alter);

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
      final glyph = _accidentalGlyphOf(pitch);
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
    // Cue / ossia notes draw small: head, stem, flag and dots are scaled.
    final scale = _cueIds.contains(id) ? 0.72 : 1.0;
    final headGlyph = _noteheadGlyph(element.notehead, base);
    final headWidth = _glyphWidth(headGlyph) * scale;
    // A notehead scheme replaces the round head per pitch (by scale degree for
    // shapes, or with the pitch letter / solfège syllable), but never overrides
    // an explicit notehead shape (x, diamond, …).
    final scheme = element.notehead == NoteheadShape.normal
        ? s.noteheadScheme
        : NoteheadScheme.normal;
    final useShapes =
        scheme == NoteheadScheme.sacredHarp || scheme == NoteheadScheme.aikin;
    final useText =
        scheme == NoteheadScheme.pitchName || scheme == NoteheadScheme.solfege;
    final hasStem = base != DurationBase.whole && base != DurationBase.breve;

    // Rule 5: stem down when the notehead farthest from the middle line is
    // on or above it (chords: decided by the farther extreme; ties → down).
    final stemsDown = stemsDownOverride ??
        ((top - _middlePosition) >= (_middlePosition - bottom));

    // Rule 9: accidentals — shown when the pitch deviates from what the key
    // signature and earlier accidentals in this measure imply;
    // `showAccidental` overrides. Hidden accidentals do not update state.
    final shown = <(Pitch, int, String?)>[]; // pitch, staff position, id
    for (var i = 0; i < pitches.length; i++) {
      final pitch = pitches[i];
      final key = (pitch.step, pitch.octave);
      final implied = written[key] ?? _key.alterFor(pitch.step);
      final show = element.showAccidental ??
          (pitch.microtone != null || pitch.alter != implied);
      if (show) {
        shown.add((pitch, positions[i], id));
        if (pitch.microtone == null) written[key] = pitch.alter;
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
      if (useText) {
        // Draw the pitch letter / solfège syllable centered in the head slot.
        final textSize = 1.25 * scale;
        _primitives.add(TextPrimitive(
          _noteheadLabel(pitches[i], scheme),
          Point(
              columnX[i] + headWidth / 2, _yOf(positions[i]) + 0.34 * textSize),
          size: textSize,
          elementId: id,
        ));
        continue;
      }
      final glyph =
          useShapes ? _shapeNoteGlyph(pitches[i], base, scheme) : headGlyph;
      _addGlyph(glyph, columnX[i], _yOf(positions[i]),
          elementId: id, scale: scale);
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
    final stemThickness = s.stemThickness * scale;
    final stemLength = s.stemLength * scale;
    if (hasStem) {
      final anchors = meta.anchorsOf(headGlyph);
      if (stemsDown) {
        final anchor = anchors.stemDownNW ?? const Point(0.0, 0.0);
        stemX = noteX + anchor.x * scale + stemThickness / 2;
        final attachY = _yOf(top) - anchor.y * scale; // SMuFL y-up -> flip sign
        if (deferStem) {
          beamed = _BeamedNote(
            elementId: id,
            stemX: stemX,
            attachY: attachY,
            refY: _yOf(bottom),
            beamCount: _beamCountOf(base),
          );
        } else {
          var tipY = _yOf(bottom) +
              stemLength +
              _stemExtension(_beamCountOf(base)) * scale;
          if (tipY < _middleY) tipY = _middleY; // extend toward the middle line
          _addLine(
            Point(stemX, attachY),
            Point(stemX, tipY),
            stemThickness,
            elementId: id,
          );
          stemTipY = tipY;
        }
      } else {
        final anchor = anchors.stemUpSE ?? Point(_glyphWidth(headGlyph), 0.0);
        stemX = noteX + anchor.x * scale - stemThickness / 2;
        final attachY = _yOf(bottom) - anchor.y * scale;
        if (deferStem) {
          beamed = _BeamedNote(
            elementId: id,
            stemX: stemX,
            attachY: attachY,
            refY: _yOf(top),
            beamCount: _beamCountOf(base),
          );
        } else {
          var tipY = _yOf(top) -
              stemLength -
              _stemExtension(_beamCountOf(base)) * scale;
          if (tipY > _middleY) tipY = _middleY; // extend toward the middle line
          _addLine(
            Point(stemX, attachY),
            Point(stemX, tipY),
            stemThickness,
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
        _addGlyph(flagGlyph, stemX - stemThickness / 2, stemTipY,
            elementId: id, scale: scale);
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
      final dotWidth = _glyphWidth(SmuflGlyph.augmentationDot) * scale;
      final dotSpacing = s.dotSpacing * scale;
      final dotStart = maxColX + headWidth + s.dotGap * scale;
      for (final position in positions.toSet()) {
        final dotY = position.isEven ? _yOf(position) - 0.5 : _yOf(position);
        for (var d = 0; d < element.duration.dots; d++) {
          _addGlyph(
            SmuflGlyph.augmentationDot,
            dotStart + d * (dotWidth + dotSpacing),
            dotY,
            elementId: id,
            scale: scale,
          );
        }
      }
      inkRight = dotStart +
          element.duration.dots * (dotWidth + dotSpacing) -
          dotSpacing;
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
    for (var p = _topPosition + 2; p <= topPosition; p += 2) {
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
    double log2Adjust, {
    double lyricReserve = 0,
  }) {
    final baseLog2 = duration.base == DurationBase.breve
        ? 1.0
        : -duration.base.index.toDouble();
    final log2Duration = baseLog2 + _dotLog2[duration.dots] + log2Adjust;
    final ideal = (s.spacingBase + s.spacingPerLog2 * (4 + log2Duration)) *
        spacingStretch;
    // A wide lyric syllable widens the advance so the next note clears it.
    _x = max(max(fromX + ideal, inkRight + s.minNoteGap), lyricReserve);
  }

  /// The x the next note must reach so this note's widest lyric syllable
  /// (centered on the notehead column, just added to [_tieInfos]) clears with a
  /// small gap; 0 when the note carries no lyric.
  double _lyricReserveFor(String? id) {
    if (id == null) return 0;
    final half = _lyricHalfWidths[id];
    if (half == null) return 0;
    final info = _tieInfos.last;
    final centerX = (info.left + info.right) / 2;
    return centerX + half + 0.35;
  }

  // ------------------------------------------------------------------ ties

  double _slurArchDepth(double span) => 0.55 + min(2.7, span.abs() * 0.045);

  double _slurEndpointY(double y, double span, {required bool above}) {
    if (span.abs() <= 12) return y;
    return above ? min(y, -0.65) : max(y, 4.65);
  }

  double _slurClearanceOffset(
    Point<double> start,
    Point<double> control1,
    Point<double> control2,
    Point<double> end, {
    required bool above,
  }) {
    var violation = 0.0;
    const clearance = 0.75;
    const sampleCount = 64;
    for (var i = 1; i < sampleCount; i++) {
      final t = i / sampleCount;
      final p = _cubicPoint(start, control1, control2, end, t);
      if (above) {
        final skyline = _skylineTop(p.x - 0.45, p.x + 0.45);
        if (skyline == null) continue;
        violation = max(violation, p.y - (skyline - clearance));
      } else {
        final skyline = _skylineBottom(p.x - 0.45, p.x + 0.45);
        if (skyline == null) continue;
        violation = max(violation, (skyline + clearance) - p.y);
      }
    }
    if (violation <= 0) return 0;
    return above ? -violation : violation;
  }

  Point<double> _cubicPoint(
    Point<double> p0,
    Point<double> p1,
    Point<double> p2,
    Point<double> p3,
    double t,
  ) {
    final u = 1 - t;
    return Point(
      u * u * u * p0.x +
          3 * u * u * t * p1.x +
          3 * u * t * t * p2.x +
          t * t * t * p3.x,
      u * u * u * p0.y +
          3 * u * u * t * p1.y +
          3 * u * t * t * p2.y +
          t * t * t * p3.y,
    );
  }

  bool _isBassFamily(Clef clef) =>
      clef == Clef.bass || clef == Clef.bass8vb || clef == Clef.subbass;

  /// Palm-mute ("P.M.") and let-ring ("let ring") spans on the notation staff:
  /// a label followed by a dashed line above the staff, clearing the ink under
  /// the span, with a downward hook at the end. (These also render on tab.)
  void _layoutPalmMuteLetRing() {
    if (score.palmMutes.isEmpty && score.letRings.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final pm in score.palmMutes) {
      _textBracketAbove('P.M.', pm.startId, pm.endId, infoOf);
    }
    for (final lr in score.letRings) {
      _textBracketAbove('let ring', lr.startId, lr.endId, infoOf);
    }
  }

  /// A vibrato on the notation staff: a horizontal wavy line above the note,
  /// clearing the ink above it. (Vibrato also renders on tab.)
  void _layoutNotationVibrato() {
    if (score.vibratos.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final vib in score.vibratos) {
      final info = infoOf[vib.noteId];
      if (info == null || info.note == null) {
        continue;
      }
      final centerX = (info.left + info.right) / 2;
      final amp = vib.wide ? 0.42 : 0.26;
      const half = 0.5; // width of each half-wave
      const count = 4;
      final top = _skylineTop(info.left - 0.4, info.left + count * half) ?? 0.0;
      final baseY = min(-1.2, top - 0.5);
      var px = centerX - count * half / 2;
      for (var k = 0; k < count; k++) {
        final dir = k.isEven ? -1.0 : 1.0;
        final peakY = baseY + dir * amp;
        _primitives.add(CurvePrimitive(
          Point(px, baseY),
          Point(px + half * 0.4, peakY),
          Point(px + half * 0.6, peakY),
          Point(px + half, baseY),
          thickness: vib.wide ? 0.16 : 0.13,
        ));
        px += half;
      }
      _ink.expand(centerX - count * half / 2, baseY - amp - 0.2,
          centerX + count * half / 2, baseY + amp + 0.2);
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
        continue;
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
      _layoutClefChange(clefChange);
    }
    final keyChange = measure.keyChange;
    if (keyChange != null && keyChange != _key) {
      // Cancellation naturals for steps the new signature no longer alters the
      // same way (dropped, or changed sign / amount).
      final oldSteps = _key.alteredSteps;
      final oldPositions = _key.custom != null
          ? [for (final step in oldSteps) _keyStepPosition(_clef, step)]
          : (_key.fifths > 0
              ? _sharpPositions[_clef]!
              : _flatPositions[_clef]!);
      final naturalWidth = _glyphWidth(SmuflGlyph.accidentalNatural);
      for (var i = 0; i < oldSteps.length; i++) {
        if (keyChange.alterFor(oldSteps[i]) == _key.alterFor(oldSteps[i])) {
          continue;
        }
        _addGlyph(SmuflGlyph.accidentalNatural, _x, _yOf(oldPositions[i]));
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

  void _applyInlineClefs(Measure measure, Fraction onset) {
    for (final change in measure.inlineClefs) {
      if (change.onset == onset && change.clef != _clef) {
        _layoutClefChange(change.clef);
      }
    }
  }

  // ---------------------------------------------------------------- beaming

  // Shape per movable-do scale degree (0-6) for each shape-note [scheme].
  static const _sacredHarpShapes = [
    'TriangleLeft', // fa (1)
    'Round', //        sol (2)
    'Square', //       la (3)
    'TriangleLeft', // fa (4)
    'Round', //        sol (5)
    'Square', //       la (6)
    'Diamond', //      mi (7)
  ];
  static const _aikinShapes = [
    'TriangleUp', //    do (1)
    'Moon', //          re (2)
    'Diamond', //       mi (3)
    'TriangleLeft', //  fa (4)
    'Round', //         sol (5)
    'Square', //        la (6)
    'TriangleRound', // ti (7)
  ];

  static const _solfegeSyllables = ['do', 're', 'mi', 'fa', 'sol', 'la', 'ti'];

  /// The text drawn in place of the notehead under a text scheme: the pitch
  /// letter (`pitchName`) or the movable-do solfège syllable (`solfege`).
  String _noteheadLabel(Pitch pitch, NoteheadScheme scheme) {
    if (scheme == NoteheadScheme.pitchName) {
      return pitch.step.name.toUpperCase();
    }
    final degree = ((pitch.step.index - _keyTonicStepIndex()) % 7 + 7) % 7;
    return _solfegeSyllables[degree];
  }

  /// The shape-note notehead glyph for [pitch] at duration [base] under
  /// [scheme], mapped from the pitch's movable-do scale degree in the key.
  String _shapeNoteGlyph(
      Pitch pitch, DurationBase base, NoteheadScheme scheme) {
    final degree = ((pitch.step.index - _keyTonicStepIndex()) % 7 + 7) % 7;
    final shapes =
        scheme == NoteheadScheme.aikin ? _aikinShapes : _sacredHarpShapes;
    final variant = switch (base) {
      DurationBase.breve => 'DoubleWhole',
      DurationBase.whole || DurationBase.half => 'White',
      _ => 'Black',
    };
    return 'noteShape${shapes[degree]}$variant';
  }

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
}
