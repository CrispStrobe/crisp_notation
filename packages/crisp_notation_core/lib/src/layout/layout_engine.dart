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
import '../theory/tempo.dart';
import '../theory/time_signature.dart';
import 'barline_pen.dart';
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
  ///
  /// [extraFingerings] draws fingering marks the score does not itself carry,
  /// keyed by note-element id and appended after any [NoteElement.fingerings] —
  /// the channel for fingerings COMPUTED at display time (a bowed-string or
  /// tab arranger fingering a score it did not build), so a caller can show
  /// them without rebuilding an immutable [Score]. Values are digits 0–9 or
  /// [kFingeringThumb]; anything else is skipped.
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
    bool showNoteOctaves = false,
    bool showBeatNumbers = false,
    bool showMeasureNumbers = false,
    int measureNumberInterval = 1,
    Map<String, bool> deferredStems = const {},
    Map<String, List<int>> extraFingerings = const {},
    List<Map<Fraction, double>>? forcedColumns,
    List<double>? measurePrefixes,
    bool? numberVerses,
    int staffLineCount = 5,
    bool? drawTempoMarks,
  }) =>
      _LayoutBuilder(
        _withoutRepeats(score),
        settings,
        leadingWidth: leadingWidth,
        measureWidths: measureWidths,
        targetWidth: targetWidth,
        spacingStretch: spacingStretch,
        drawTimeSignature: drawTimeSignature,
        finalBarline: finalBarline,
        showNoteNames: showNoteNames,
        noteNameStyle: noteNameStyle,
        showNoteOctaves: showNoteOctaves,
        showBeatNumbers: showBeatNumbers,
        showMeasureNumbers: showMeasureNumbers,
        measureNumberInterval: measureNumberInterval,
        deferredStems: deferredStems,
        extraFingerings: extraFingerings,
        forcedColumns: forcedColumns,
        measurePrefixes: measurePrefixes,
        numberVerses: numberVerses,
        staffLineCount: staffLineCount,
        drawTempoMarks: drawTempoMarks ?? settings.drawTempoMarks,
      ).build();
}

/// [score] with what a source states twice drawn once: a chord naming one
/// pitch twice (two voices' unison merged into one chord, or a cross-staff
/// chord read with its notes repeated) drew every head, dot, ledger line and
/// tie twice; a hairpin listed twice drew twice. The model keeps both, as
/// read; only the drawing merges them. Returns [score] itself when there is
/// nothing to merge.
Score _withoutRepeats(Score score) {
  List<MusicElement> merged(List<MusicElement> voice) {
    if (!voice.any((e) =>
        e is NoteElement && e.pitches.toSet().length != e.pitches.length)) {
      return voice;
    }
    return [
      for (final e in voice)
        e is NoteElement && e.pitches.toSet().length != e.pitches.length
            ? e.copyWith(pitches: e.pitches.toSet().toList())
            : e,
    ];
  }

  var changed = false;
  final measures = [
    for (final m in score.measures)
      () {
        final voices = [m.elements, m.voice2, m.voice3, m.voice4];
        final out = [for (final v in voices) merged(v)];
        if (List.generate(4, (i) => identical(out[i], voices[i]))
            .every((same) => same)) {
          return m;
        }
        changed = true;
        return m.copyWith(
            elements: out[0], voice2: out[1], voice3: out[2], voice4: out[3]);
      }(),
  ];
  final hairpins = score.hairpins.toSet().toList();
  if (hairpins.length != score.hairpins.length) changed = true;
  return changed
      ? score.copyWith(measures: measures, hairpins: hairpins)
      : score;
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

  /// When true, the note-name overlay appends the note's octave (scientific
  /// pitch — middle C is C4), e.g. `F2`. Off by default so a bare-letter
  /// overlay (the note-reading games) is unchanged; the Score Workshop opts in.
  final bool showNoteOctaves;
  final bool showBeatNumbers;
  final bool showMeasureNumbers;
  final int measureNumberInterval;

  /// Fingering marks to draw that the score itself does not carry, keyed by
  /// note-element id (see [LayoutEngine.layout]'s `extraFingerings`).
  final Map<String, List<int>> extraFingerings;

  /// Number of staff lines (5 for an ordinary notation staff; 1 for a neutral
  /// percussion line, etc.). Drives every vertical staff reference below.
  final int staffLineCount;

  /// Whether to draw metronome marks (`Score.tempo`, `Measure.tempoChange`)
  /// above the staff — off for the lower staves of a system.
  final bool drawTempoMarks;

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

  /// The pitches each note holds over a tie from the voice's previous note,
  /// by element id. A tied-over note does not repeat its accidental in the
  /// next bar (Gould): the tie carries it.
  late final Map<String, Set<(Step, int, int)>> _tiedIn = () {
    final out = <String, Set<(Step, int, int)>>{};
    for (var v = 0; v < 4; v++) {
      NoteElement? previous;
      for (final m in score.measures) {
        for (final e in m.voiceAt(v)) {
          if (e is! NoteElement) {
            previous = null;
            continue;
          }
          if (previous != null && previous.tieToNext && e.id != null) {
            final held = {
              for (final p in previous.pitches) (p.step, p.octave, p.alter),
            };
            final tied = {
              for (final p in e.pitches)
                if (held.contains((p.step, p.octave, p.alter)))
                  (p.step, p.octave, p.alter),
            };
            if (tied.isNotEmpty) out[e.id!] = tied;
          }
          previous = e;
        }
      }
    }
    return out;
  }();

  /// Whether [pitch] of the note [id] continues a tie from the bar before.
  bool _heldOver(String? id, Pitch pitch) =>
      pitch.microtone == null &&
      (_tiedIn[id]?.contains((pitch.step, pitch.octave, pitch.alter)) ?? false);

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

  /// Index into [_tieInfos] of EVERY element (notes and rests) by id. Marks
  /// that may sit on a rest (dynamics, hairpins) look their anchor up here.
  late final Map<String, int> _elementIndexById = {
    for (var i = 0; i < _tieInfos.length; i++)
      if (_tieInfos[i].id != null) _tieInfos[i].id!: i,
  };

  /// The [_tieInfos] index of the element (note or rest) with [id], or -1.
  int _elementIndexOf(String? id) =>
      id == null ? -1 : (_elementIndexById[id] ?? -1);

  /// The [_tieInfos] index of the note with [id], or -1 — the O(1) replacement
  /// for `_tieInfos.indexWhere((i) => i.note != null && i.id == id)`.
  int _tieIndexOf(String? id) => id == null ? -1 : (_tieIndexById[id] ?? -1);

  /// Per voice, the [_tieInfos] left edges of its notes AND rests (a voice
  /// resting under another is still a second voice on the staff) in
  /// ascending order,
  /// paired with the running maximum of their right edges. Built once, lazily
  /// (like [_tieIndexById]), so the "does another voice sound here?" query
  /// every tie and slur asks is a binary search, not a scan of the whole score.
  late final Map<int, (List<double>, List<double>, List<_TieInfo>)>
      _noteSpansByVoice = () {
    final byVoice = <int, List<_TieInfo>>{};
    for (final info in _tieInfos) {
      if (info.id != null) (byVoice[info.voice] ??= []).add(info);
    }
    return {
      for (final MapEntry(key: voice, value: infos) in byVoice.entries)
        voice: () {
          infos.sort((a, b) => a.left.compareTo(b.left));
          var maxRight = double.negativeInfinity;
          return (
            [for (final info in infos) info.left],
            [for (final info in infos) maxRight = max(maxRight, info.right)],
            infos,
          );
        }(),
    };
  }();

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
      final w = _textHalf(lyric.text, s.lyricSize);
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

  /// Each slur's ink as `(left, right, bottom)`, so the dynamics line (laid
  /// out after the slurs) can sit below a slur instead of through it.
  final List<(double, double, double)> _slurInk = [];

  /// [_inkRects] indices bucketed by x column ([_inkBucketWidth] staff spaces
  /// wide), so a skyline query visits only the ink near its span. Scanning
  /// every rect per query made each mark/slur pass O(n²) in a long score.
  /// A rect too wide to bucket cheaply (a staff line, a long beam) goes in
  /// [_wideInk] and is checked by every query — there are few of those.
  final Map<int, List<int>> _inkBuckets = {};
  final List<int> _wideInk = [];
  static const double _inkBucketWidth = 4;
  static const int _maxBucketsPerRect = 16;

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

  /// Per measure, the least room between the previous bar's end and this
  /// bar's content: the widest any staff of the system needs for its
  /// barline and start-of-bar changes (clef, key, time, start repeat), so a
  /// staff with a clef change does not start its bar later than the others.
  final List<double>? measurePrefixes;

  /// Whether verse numbers ("1.", "2.") may print before each verse's first
  /// syllable — they do when the layout holds two verses or more. Null or
  /// true allows them; a wrapped score passes false on every line but the
  /// one where the lyrics begin.
  final bool? numberVerses;

  /// Stem anchors of the [deferredStems] notes, keyed by element id.
  final Map<String, CrossStaffStub> _crossStaffStubs = {};

  _LayoutBuilder(
    this.score,
    this.s, {
    this.leadingWidth,
    this.measureWidths,
    this.targetWidth,
    this.spacingStretch = 1.0,
    this.drawTimeSignature = true,
    this.finalBarline = true,
    this.showNoteNames = false,
    this.noteNameStyle = NoteNameStyle.letter,
    this.showNoteOctaves = false,
    this.showBeatNumbers = false,
    this.showMeasureNumbers = false,
    this.measureNumberInterval = 1,
    this.deferredStems = const {},
    this.extraFingerings = const {},
    this.forcedColumns,
    this.measurePrefixes,
    this.numberVerses,
    this.staffLineCount = 5,
    this.drawTempoMarks = true,
  });

  // log2(dot factor) for 0..2 dots: 1, 3/2, 7/4.
  static const List<double> _dotLog2 = [
    0.0,
    0.5849625007211562,
    0.8073549220576042,
  ];

  final _staffFingerings = <(String?, double, List<int>)>[];

  /// [measure]'s start repeat stands where the barline before it would: no
  /// clef, key or time change is drawn between them. With one, the barline
  /// closes the previous bar and the repeat follows the new signature. (A
  /// "change" to what is already in force draws nothing.)
  bool _repeatOpensBar(Measure measure) =>
      measure.startRepeat &&
      (measure.clefChange ?? _clef) == _clef &&
      (measure.keyChange ?? _key) == _key &&
      (measure.timeChange ?? _time) == _time;

  /// A bar that is one rest for its whole length shows a whole rest (a breve
  /// rest in a bar of a breve or more) centred between its barlines, in
  /// every meter — the rest of a silent 3/4 bar is not a dotted half rest.
  void _centerFullBarRest(Measure measure, double startX, double endX) {
    // The bar's only content, in whichever voice holds it (a piano's left
    // hand often reads into voice 2 with voice 1 empty).
    final content = [
      ...measure.elements,
      ...measure.voice2,
      ...measure.voice3,
      ...measure.voice4,
    ];
    if (measure.multiRest != null || content.length != 1) return;
    final rest = content.single;
    final time = _time;
    if (rest is! RestElement ||
        rest.hidden ||
        rest.id == null ||
        time == null) {
      return;
    }
    final bar = Fraction(time.beats, time.beatUnit);
    if (rest.duration.toFraction() != bar) return;
    final breve = bar >= Fraction(2, 1);
    final glyph = breve ? SmuflGlyph.restDoubleWhole : SmuflGlyph.restWhole;
    _primitives.removeWhere((p) =>
        p is GlyphPrimitive &&
        p.elementId == rest.id &&
        (p.smuflName.startsWith('rest') ||
            p.smuflName == SmuflGlyph.augmentationDot));
    final width = _glyphWidth(glyph);
    // The whole rest hangs from the fourth line; the breve rest fills the
    // third space.
    _addGlyph(glyph, (startX + endX - width) / 2, breve ? 2.0 : 1.0,
        elementId: rest.id);
  }

  /// Where in the meter [measure]'s first note falls: zero, except in a
  /// pickup, which ends where a full bar would. Its length is the one it
  /// states, else what it holds (no reader states it; CometBeat's editor
  /// does).
  Fraction _metricStart(Measure measure) {
    final full = _time?.toFraction();
    if (!measure.pickup || full == null) return Fraction.zero;
    final actual = measure.actualDuration ?? measure.totalDuration;
    if (actual <= Fraction.zero || actual >= full) return Fraction.zero;
    return full - actual;
  }

  /// Half the width of [text] at [size]: measured by the renderer when it
  /// supplies [LayoutSettings.textWidth], else estimated.
  double _textHalf(String text, double size) {
    final measure = s.textWidth;
    return measure == null
        ? estimateTextHalfWidth(text, size)
        : measure(text, size) / 2;
  }

  /// The width of a bar with no elements, in staff spaces.
  static const _emptyMeasureWidth = 4.0;

  ScoreLayout build() {
    _prepareCrossMeasureBeams();
    _x = s.leadingPadding;
    _layoutClef();
    _layoutKeySignature();
    if (drawTimeSignature) _layoutTimeSignature();
    if (leadingWidth != null && _x < leadingWidth!) {
      _x = leadingWidth!;
    }

    // Where the volta bracket over the current run of bars began.
    double? voltaStartX;
    for (var i = 0; i < score.measures.length; i++) {
      final measure = score.measures[i];
      final previousEnd =
          _measureRegions.isEmpty ? null : _measureRegions.last.endX;
      _applyMeasureChanges(measure);
      if (measure.startRepeat) _addStartRepeat();
      final prefixes = measurePrefixes;
      if (prefixes != null && previousEnd != null && i < prefixes.length) {
        _x = max(_x, previousEnd + prefixes[i]);
      }
      final startX = _x;
      _layoutMeasure(measure, i);
      // A bar with nothing in it (a hidden whole-bar rest a reader drops,
      // `print-object="no"`) still reads as a bar: without a width its
      // barlines stacked into one thick smear.
      if (measure.multiRest == null &&
          measure.measureRepeat == null &&
          measure.voices.every((v) => v.isEmpty) &&
          _x < startX + _emptyMeasureWidth) {
        _x = startX + _emptyMeasureWidth;
      }
      final widths = measureWidths;
      if (widths != null && i < widths.length && _x < startX + widths[i]) {
        _x = startX + widths[i];
      }
      _measureRegions.add(MeasureRegion(i, startX: startX, endX: _x));
      _centerFullBarRest(measure, startX, _x);
      if (measure.voltaLabel case final label?) {
        // An ending that spans several bars is ONE bracket — its number and
        // left hook over the first bar, its right hook over the last. Drawn
        // bar by bar it read as a row of separate first endings.
        if (i == 0 || !score.measures[i - 1].voltaContinuesInto(measure)) {
          voltaStartX = startX;
        }
        if (i == score.measures.length - 1 ||
            !measure.voltaContinuesInto(score.measures[i + 1])) {
          _addVolta(label, voltaStartX ?? startX, _x);
        }
      }
      if (measure.endRepeat) {
        _addEndRepeat();
      } else if (i < score.measures.length - 1 &&
          !_repeatOpensBar(score.measures[i + 1])) {
        // A start repeat (thick, thin, dots) replaces the barline before it;
        // drawing both read as `| ‖:` (1,071 bars in the real corpus).
        _addBarline(measure.barline);
      }
    }
    _layoutCrossMeasureBeams();
    _layoutTies();
    _layoutLaissezVibrer();
    // Slurs BEFORE dynamics: a slur hugs its notes and dynamics/hairpins sit
    // outside it. The other order made a slur treat a hairpin under its notes
    // as an obstacle and dive beneath it (365 slurs in the real corpus).
    _layoutSlurs();
    _layoutDynamics();
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
    _layoutTempoMarks();
    _layoutJazzArticulations();
    _layoutPalmMuteLetRing();
    _layoutBarres();
    _layoutNotationVibrato();
    _layoutBreathMarks();
    _layoutChordDiagrams();
    _layoutBeatNumbers();
    _layoutMeasureNumbers();
    _layoutStaffFingerings();
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
      LinePrimitive(
        from,
        to,
        thickness: thickness,
        elementId: elementId,
        round: round,
      ),
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
    // Register the curve's real shape as a chain of small boxes, not its
    // control polygon. The control points overshoot the curve, and marks laid
    // out later cleared that phantom ink: a slur nested inside another was
    // pushed outside the outer slur's control box.
    const segments = 8;
    final h = thickness / 2;
    var prev = start;
    for (var i = 1; i <= segments; i++) {
      final p = _cubicPoint(start, control1, control2, end, i / segments);
      _expand(
        null,
        min(prev.x, p.x) - h,
        min(prev.y, p.y) - h,
        max(prev.x, p.x) + h,
        max(prev.y, p.y) + h,
      );
      prev = p;
    }
  }

  void _expand(
    String? elementId,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    _ink.expand(left, top, right, bottom);
    final index = _inkRects.length;
    _inkRects.add((left, top, right, bottom));
    final first = (left / _inkBucketWidth).floor();
    final last = (right / _inkBucketWidth).floor();
    if (last - first >= _maxBucketsPerRect) {
      _wideInk.add(index);
    } else {
      for (var k = first; k <= last; k++) {
        (_inkBuckets[k] ??= []).add(index);
      }
    }
    if (elementId != null) {
      _elementBounds
          .putIfAbsent(elementId, _Bounds.new)
          .expand(left, top, right, bottom);
    }
  }

  /// Highest ink (smallest y) whose x-range overlaps `[xL, xR)`, or null when
  /// that column is empty. Only ink placed so far is considered, so the pass
  /// order determines what a mark clears.
  ///
  /// With [skipBarlines], thin ink spanning the whole staff height is ignored.
  /// A slur crosses barlines freely, so it must not arch over one; counting
  /// them sent a cross-bar slur on low notes over the top of the staff.
  double? _skylineTop(double xL, double xR, {bool skipBarlines = false}) {
    double? best;
    for (final i in _inkNear(xL, xR)) {
      final (l, t, r, b) = _inkRects[i];
      if (r <= xL || l >= xR) continue;
      if (skipBarlines && _isBarlineInk(l, t, r, b)) continue;
      if (best == null || t < best) best = t;
    }
    return best;
  }

  /// Lowest ink (largest y) whose x-range overlaps `[xL, xR)`, or null.
  double? _skylineBottom(double xL, double xR, {bool skipBarlines = false}) {
    double? best;
    for (final i in _inkNear(xL, xR)) {
      final (l, t, r, b) = _inkRects[i];
      if (r <= xL || l >= xR) continue;
      if (skipBarlines && _isBarlineInk(l, t, r, b)) continue;
      if (best == null || b > best) best = b;
    }
    return best;
  }

  /// Thin vertical ink from the top staff line to the bottom one: a barline.
  bool _isBarlineInk(double l, double t, double r, double b) =>
      r - l <= 0.6 && t <= 0.05 && b >= staffLineCount - 1.05;

  /// Indices of every ink rect that MAY overlap `[xL, xR)` (a superset; the
  /// callers apply the exact test). A rect may be yielded more than once —
  /// harmless for the min/max the skyline takes.
  Iterable<int> _inkNear(double xL, double xR) sync* {
    yield* _wideInk;
    if (xR < xL) return;
    final first = (xL / _inkBucketWidth).floor();
    final last = (xR / _inkBucketWidth).floor();
    for (var k = first; k <= last; k++) {
      final bucket = _inkBuckets[k];
      if (bucket != null) yield* bucket;
    }
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
      _layoutMultiRest(measure);
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
      start: _metricStart(measure),
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
      final pendingClefs =
          _applyInlineClefs(measure, onset, defer: columnX != null);
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
                    (cm != null ? _crossBeamStemsDown[cm] : element.stemsDown)),
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
          _advance(
            result.noteX,
            result.inkRight,
            element.duration,
            log2Adjust,
            lyricReserve: _lyricReserveFor(element.id),
            optical: columns == null && i + 1 < measure.elements.length
                ? _opticalGap(
                    element, group, measure.elements[i + 1], beamedIndex[i + 1])
                : 0,
          );
        case RestElement():
          final result = _layoutRest(element);
          _advance(result.noteX, result.inkRight, element.duration, log2Adjust);
      }
      if (pendingClefs.isNotEmpty) {
        _drawClefChangesBefore(pendingClefs,
            _elementBounds[element.id]?.minX ?? (columnNoteX ?? _x));
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
        _layoutBeamGroup(
          notes,
          stemsDown: group.stemsDown,
          onsets: group.onsets,
          feather: group.feather,
          forcedSlant: group.forcedSlant,
        );
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
    // `Measure.voices` is a COMPACTING view — it drops empty voices — while
    // `effectiveDurationAt` and `TupletSpan.voice` take the ABSOLUTE voice
    // number. The two disagree the moment a voice is empty: with nothing in
    // voice 2 and notes in voice 3, display slot 1 holds voice 3's elements but
    // the lookup reads voice 2's, which is empty — a RangeError, i.e. the score
    // does not render at all. Codecs produce exactly that shape (MEI names its
    // layers, so `<layer n="4">` can arrive with no layer 3).
    final absoluteVoice = [
      0,
      if (measure.voice2.isNotEmpty) 1,
      if (measure.voice3.isNotEmpty) 2,
      if (measure.voice4.isNotEmpty) 3,
    ];
    Fraction effectiveAt(int voice, int index) =>
        measure.effectiveDurationAt(index, voice: absoluteVoice[voice]);

    // Stems: the upper voice up, the lower down (Gould). Voice order alone
    // does not say which is upper — a piano part's left hand often reads its
    // lower voice into the first slot — and the stems then crossed the other
    // voice's heads. Two voices whose order is upside down swap directions.
    final stemsDownOf = [for (var v = 0; v < n; v++) v.isOdd];
    if (n == 2) {
      double? meanOf(List<MusicElement> voice) {
        var sum = 0, count = 0;
        for (final e in voice) {
          if (e is! NoteElement) continue;
          for (final p in e.pitches) {
            sum += _writtenPosition(p, e.id);
            count++;
          }
        }
        return count == 0 ? null : sum / count;
      }

      final first = meanOf(voices[0]), second = meanOf(voices[1]);
      if (first != null && second != null && first < second) {
        stemsDownOf[0] = true;
        stemsDownOf[1] = false;
      }
    }

    final groupsPerVoice = [
      for (var v = 0; v < n; v++)
        _computeBeamGroups(
          voices[v],
          effectiveAt: (i) => effectiveAt(v, i),
          tuplets: measure.tupletsForVoice(v),
          forcedStemsDown: stemsDownOf[v],
          start: _metricStart(measure),
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
    final columns = <Fraction>[for (final onsets in onsetsPerVoice) ...onsets]
      ..sort();
    final distinct = <Fraction>[];
    var lastInkEnd = _x; // the last column's ink end, plus the minimum gap
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
      // On the shared grid a column's x is its noteheads' x (accidentals hang
      // left of it), as in the single-voice path. Setting the accidentals at
      // the column and the heads after them put every chord with an
      // accidental an accidental's width right of the other staves.
      final forcedHere = forced != null && forced[onset] != null;
      // A clef change here is drawn left of the column's ink once it is
      // placed; drawn at the column, it pushed this staff's notes right.
      final pendingClefs = _applyInlineClefs(measure, onset, defer: forcedHere);
      final columnX = _x;
      final placedIds = <String>[];
      final nextOnset = c + 1 < distinct.length ? distinct[c + 1] : measureEnd;
      final delta = nextOnset - onset;
      var idealEnd = columnX;
      var inkRight = columnX;

      // Head positions of higher voices already placed in this column, for
      // collision checks.
      final placedPositions = <int>[];
      var placedHeadsRight = columnX;
      // Each placed element's head positions and stem direction.
      final placedStems = <(List<int>, bool)>[];

      // The notes sounding at this onset across all voices.
      final sounding = <NoteElement>[];
      final restsHere = <RestElement>[];
      for (var v = 0; v < n; v++) {
        final i = cursor[v];
        if (i < voices[v].length && onsetsPerVoice[v][i] == onset) {
          final el = voices[v][i];
          if (el is NoteElement) sounding.add(el);
          if (el is RestElement && !el.hidden) restsHere.add(el);
        }
      }
      // Every voice resting alike here: one rest, in the middle, as an
      // engraver writes it — not one per voice stacked above and below.
      final sharedRest = sounding.isEmpty &&
          restsHere.length >= 2 &&
          restsHere.every((r) => r.duration == restsHere.first.duration);
      var sharedRestDrawn = false;

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
            if (posPerNote[a].any(
              (x) => posPerNote[b].any((y) => (x - y).abs() <= 1),
            )) {
              collides = true;
            }
          }
        }
        if (!collides) {
          final jointShown = <(Pitch, int, String?)>[];
          for (final el in sounding) {
            final ps = [...el.pitches]..sort(
                (a, b) =>
                    a.staffPosition(_clef).compareTo(b.staffPosition(_clef)),
              );
            for (final pitch in ps) {
              final key = (pitch.step, pitch.octave);
              final implied = written[key] ?? _key.alterFor(pitch.step);
              final show = el.showAccidental ??
                  (!_heldOver(el.id, pitch) &&
                      (pitch.microtone != null || pitch.alter != implied));
              if (show) {
                jointShown.add((pitch, _writtenPosition(pitch, el.id), el.id));
                if (pitch.microtone == null) written[key] = pitch.alter;
              }
            }
          }
          if (jointShown.isNotEmpty) {
            final acc = _accidentalColumns(jointShown);
            columnNoteX = forcedHere ? columnX : columnX + acc.preWidth;
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
        if (element.id case final id?) placedIds.add(id);
        tieIndexPerVoice[v][i] = _tieInfos.length;
        _x = columnX;
        var displaced = false;
        // The stem this element will take: its beam's, else the source's,
        // else the voice's.
        final effectiveDown = beamedIndexPerVoice[v][i]?.stemsDown ??
            (element is NoteElement ? element.stemsDown : null) ??
            stemsDownOf[v];
        if (element is NoteElement && placedPositions.isNotEmpty) {
          final myPositions = [
            for (final pitch in element.pitches)
              _writtenPosition(pitch, element.id),
          ];
          // A second or unison between voices collides; so do interlocking
          // voices — a head inside the other voice's chord span sits on that
          // chord's stem (a song's inner-voice E drawn through a piano
          // chord's stem), and the reverse.
          final placedLo = placedPositions.reduce(min);
          final placedHi = placedPositions.reduce(max);
          final myLo = myPositions.reduce(min);
          final myHi = myPositions.reduce(max);
          // Crossed voices: the stem-up voice's stem rises through the
          // stem-down voice's heads above it, or the stem-down voice's stem
          // falls through heads below it.
          final myDown = effectiveDown;
          bool crossed(List<int> up, List<int> down) =>
              down.any((p) => p > up.reduce(max)) ||
              up.any((p) => p < down.reduce(min));
          final collides = placedPositions.any(
                (p1) => myPositions.any((p2) => (p1 - p2).abs() <= 1),
              ) ||
              myPositions.any((p) => p > placedLo && p < placedHi) ||
              placedPositions.any((p) => p > myLo && p < myHi) ||
              placedStems.any((placed) =>
                  // Stems the same way (as a source may state them): one
                  // voice's stem runs through the other's heads.
                  placed.$2 == myDown ||
                  (myDown
                      ? crossed(placed.$1, myPositions)
                      : crossed(myPositions, placed.$1)));
          if (collides) {
            // Beside the heads already placed here — measured from them, not
            // the column: a head pushed right by its accidental left a fixed
            // offset short, and unisons of different lengths still overlapped.
            // A notehead's width aside, heads nearly touching, as engravers
            // set a displaced voice (a whole head and a half more read as a
            // note between beats).
            // Ledger lines reach past a head on both sides: clear the placed
            // ink (its ledger lines included) and this note's own.
            final ledger = myPositions.any((p) => p < -1 || p > 9)
                ? s.legerLineExtension
                : 0.0;
            _x = max(columnX + _glyphWidth(SmuflGlyph.noteheadBlack),
                placedHeadsRight + 0.12 + ledger);
            displaced = true;
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
                      (cm != null
                          ? _crossBeamStemsDown[cm]
                          : element.stemsDown ?? stemsDownOf[v])),
              deferStem: crossStaff || cm != null || group != null,
              voice: v,
              noteXOverride: displaced
                  ? null
                  : columnNoteX ?? (forcedHere ? columnX : null),
              accidentalsDrawn: columnNoteX != null,
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
            placedStems.add((
              [
                for (final pitch in element.pitches)
                  _writtenPosition(pitch, element.id),
              ],
              effectiveDown,
            ));
            // The placed head's right edge — and its ledger line's, which
            // reaches past the head (not its flag or dots).
            final placedLedger = element.pitches.any((p) {
              final pos = _writtenPosition(p, element.id);
              return pos < -1 || pos > 9;
            })
                ? s.legerLineExtension
                : 0.0;
            placedHeadsRight = max(
                placedHeadsRight,
                result.noteX +
                    _glyphWidth(_noteheadGlyph(
                        element.notehead, element.duration.base)) +
                    placedLedger);
            idealEnd = max(idealEnd, result.noteX + _idealAdvance(delta));
            inkRight = max(inkRight, result.inkRight);
          case RestElement():
            // Stagger rests away from the staff centre: voice 1 up, 2 down,
            // 3 further up, 4 further down — unless every voice rests alike,
            // when the first draws one rest in place and the rest are kept
            // (time, anchors) but not drawn again.
            final magnitude = (v ~/ 2 + 1).toDouble();
            final shared = sharedRest && !element.hidden;
            final result = _layoutRest(
              shared && sharedRestDrawn
                  ? RestElement(element.duration, id: element.id, hidden: true)
                  : element,
              voice: v,
              // Above for the upper voice, below for the lower one.
              yOffset: shared
                  ? 0
                  : (v < 2 ? !stemsDownOf[v] : v.isEven)
                      ? -magnitude
                      : magnitude,
            );
            if (shared) sharedRestDrawn = true;
            idealEnd = max(idealEnd, result.noteX + _idealAdvance(delta));
            inkRight = max(inkRight, result.inkRight);
        }
      }
      if (pendingClefs.isNotEmpty) {
        var left = columnX;
        for (final id in placedIds) {
          final b = _elementBounds[id];
          if (b != null && b.minX < left) left = b.minX;
        }
        _drawClefChangesBefore(pendingClefs, left);
      }
      _x = max(idealEnd, inkRight + s.minNoteGap);
      lastInkEnd = inkRight + s.minNoteGap;
    }

    // The shared closing column (the table's last) fixes the trailing width
    // so barlines align: the bar ends there, pushed further only by ink. This
    // staff's own spacing after its last note does not count — measured from
    // an earlier onset than another staff's, it ran past the shared column
    // and the staves' barlines drifted apart (10,213 bars in the corpus).
    if (forced != null && forced.isNotEmpty) {
      final closing = forced.keys.reduce((a, b) => a > b ? a : b);
      _x = max(lastInkEnd, measureContentStart + forced[closing]!);
    }

    for (var v = 0; v < n; v++) {
      for (final group in groupsPerVoice[v]) {
        final notes = deferred[group];
        if (notes != null && notes.length >= 2) {
          _layoutBeamGroup(
            notes,
            stemsDown: group.stemsDown,
            onsets: group.onsets,
            feather: group.feather,
          );
        }
      }
      _layoutArticulations(voices[v], tieIndexPerVoice[v]);
      _layoutFingerings(voices[v], tieIndexPerVoice[v]);
      _layoutArpeggios(voices[v], tieIndexPerVoice[v]);
    }
    _layoutTuplets(measure, tieIndexPerVoice[0]);
  }

  /// Ideal advance for an onset gap of [delta] (fraction of a whole note).
  /// The optical correction between [here] and the [next] element: an
  /// up-stem followed by a down-stem sets the stems close together, so the
  /// gap opens a little; a down-stem then an up-stem sets them far apart, so
  /// it closes a little (Gould). A beamed note counts with its beam's stems
  /// where the beam ends or begins; inside one beam the stems are joined and
  /// nothing changes.
  double _opticalGap(MusicElement here, _BeamGroup? hereGroup,
      MusicElement next, _BeamGroup? nextGroup) {
    if (hereGroup != null && identical(hereGroup, nextGroup)) return 0;
    final a = _stemDownFor(here, hereGroup);
    final b = _stemDownFor(next, nextGroup);
    if (a == null || b == null || a == b) return 0;
    return a ? -0.2 : 0.3;
  }

  /// Whether [element]'s stem points down, for optical spacing: its beam's
  /// ([group]) direction, else its own — null when it has no stem to count
  /// (a rest, a whole note, a note crossing staves).
  bool? _stemDownFor(MusicElement element, _BeamGroup? group) {
    if (element is! NoteElement || _isCrossStaff(element)) return null;
    final base = element.duration.base;
    if (base == DurationBase.whole ||
        base == DurationBase.breve ||
        base == DurationBase.long) {
      return null;
    }
    if (group != null) return group.stemsDown;
    if (element.stemsDown case final down?) return down;
    final positions = [
      for (final p in element.pitches) _writtenPosition(p, element.id),
    ];
    final top = positions.reduce(max), bottom = positions.reduce(min);
    return (top - _middlePosition) >= (_middlePosition - bottom);
  }

  double _idealAdvance(Fraction delta) {
    if (delta.numerator <= 0) return 0;
    final log2Delta = log(delta.numerator / delta.denominator) / ln2;
    return (s.spacingBase + s.spacingPerLog2 * (4 + log2Delta)) *
        spacingStretch;
  }

  /// v0.6.3: multi-measure rest — an H-bar on the middle line spanning a
  /// fixed-width measure, with the measure count in time-signature
  /// digits centered above the staff.
  void _layoutMultiRest(Measure measure) {
    final count = measure.multiRest!;
    const barWidth = 8.0;
    const capHalf = 1.0; // vertical end caps span the middle two spaces
    final left = _x + 1.0;
    final right = _x + 1.0 + barWidth;
    // The bar's own rest, if it kept one, is the anchor for marks set on the
    // silent stretch (a tempo text, a dynamic): the H-bar stands for it, so
    // it is tappable and text over it lands above the bar (#11).
    final anchor = measure.elements.whereType<RestElement>().firstOrNull?.id;
    _addLine(Point(left, 2), Point(right, 2), 0.5, elementId: anchor);
    for (final rest in measure.elements.whereType<RestElement>()) {
      _tieInfos.add(_TieInfo(
        note: null,
        id: rest.id,
        stemsDown: false,
        left: left,
        right: right,
        heads: const [],
      ));
    }
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
        (list) => list.every((p) => (p - position).abs() >= clearance),
      );
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
      _addGlyph(
        glyph,
        accX - meta.bBoxOf(glyph).swX,
        _yOf(position),
        elementId: id,
      );
    }
  }

  ({double noteX, double inkRight, _BeamedNote? beamed}) _layoutNote(
    NoteElement element,
    Map<(Step, int), int> written, {
    bool? stemsDownOverride,
    bool deferStem = false,
    int voice = 0,
    double? noteXOverride,
    bool accidentalsDrawn = false,
  }) {
    if (element.pitches.isEmpty) {
      throw ArgumentError('NoteElement.pitches must not be empty');
    }
    final id = element.id;
    final pitches = [...element.pitches]
      ..sort((a, b) => a.staffPosition(_clef) - b.staffPosition(_clef));
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
          (!_heldOver(id, pitch) &&
              (pitch.microtone != null || pitch.alter != implied));
      if (show && !accidentalsDrawn) {
        shown.add((pitch, positions[i], id));
        if (pitch.microtone == null) written[key] = pitch.alter;
      }
    }
    // Rule 9b (v0.6.1): accidental stacking in zigzag columns. In a two-voice
    // column both voices' accidentals were computed jointly and drawn by the
    // caller ([accidentalsDrawn]), so only the shared [noteXOverride] applies
    // here; a single note lays out its own. An accidental the source states
    // (`showAccidental`) was drawn a second time before that flag.
    final acc = _accidentalColumns(shown);
    // A stem-down chord with a second puts a head LEFT of the stem (rule 11
    // below): reserve that head's width, and set the accidentals left of it.
    // Unreserved, the head overlapped whatever came before — the time
    // signature, a barline, the previous note.
    var hasSecond = false;
    for (var i = 1; i < positions.length; i++) {
      if (positions[i] - positions[i - 1] <= 1) hasSecond = true;
    }
    final leftHead =
        stemsDown && hasStem && hasSecond ? headWidth - s.stemThickness : 0.0;
    final noteX = noteXOverride ?? (_x + acc.preWidth + leftHead);
    _drawAccidentalColumns(acc, noteX - leftHead);

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
      // A second — or a unison of two spellings (B and B half-sharp), which
      // drew one head over the other — goes to the other side of the stem.
      if ((positions[current] - positions[previous]).abs() <= 1 &&
          columnX[previous] == noteX) {
        columnX[current] = hasStem ? flippedX : noteX + headWidth;
      }
    }

    for (var i = 0; i < positions.length; i++) {
      if (useText) {
        // Draw the pitch letter / solfège syllable centered in the head slot.
        final textSize = 1.25 * scale;
        _primitives.add(
          TextPrimitive(
            _noteheadLabel(pitches[i], scheme),
            Point(
              columnX[i] + headWidth / 2,
              _yOf(positions[i]) + 0.34 * textSize,
            ),
            size: textSize,
            elementId: id,
          ),
        );
        continue;
      }
      final glyph =
          useShapes ? _shapeNoteGlyph(pitches[i], base, scheme) : headGlyph;
      _addGlyph(
        glyph,
        columnX[i],
        _yOf(positions[i]),
        elementId: id,
        scale: scale,
      );
    }
    _tieInfos.add(
      _TieInfo(
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
      ),
    );

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
        _addGlyph(
          flagGlyph,
          stemX - stemThickness / 2,
          stemTipY,
          elementId: id,
          scale: scale,
        );
      }
    }

    // v0.7.2: single-note tremolo — strokes centered on the stem, biased
    // toward the notehead. Only unbeamed, stemmed notes (deferred/beamed
    // stems and whole notes carry none).
    final tremolo = element.tremolo;
    if (tremolo != null && stemTipY != null) {
      final glyph = SmuflGlyph.tremoloStrokes(tremolo);
      final box = meta.bBoxOf(glyph);
      // The stem's free length starts at the chord's OUTERMOST head on the
      // stem side: the lowest note for a down-stem, the highest for an
      // up-stem. Measuring from the other end put a chord's strokes over its
      // own noteheads (#14). A single note has top == bottom, so it never
      // showed there.
      final noteSideY = stemsDown ? _yOf(bottom) : _yOf(top);
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
      // Top down, each head takes a space: its own, or for a head on a line
      // the space above — the space below when the head above holds that one
      // (a second's two dots otherwise landed on one spot, drawn twice).
      final spaces = <int>{};
      for (final position in positions.toSet().toList()
        ..sort((a, b) => b.compareTo(a))) {
        var space = position.isOdd ? position : position + 1;
        if (position.isEven && spaces.contains(space)) space = position - 1;
        if (!spaces.add(space)) continue;
        final dotY = _yOf(space);
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
      _addGlyph(
        SmuflGlyph.noteheadBlack,
        _x,
        y,
        scale: graceScale,
        elementId: id,
      );
      final stemX = _x + anchor.x * graceScale - s.stemThickness / 2;
      final tipY = y - 2.2;
      _addLine(
        Point(stemX, y - anchor.y * graceScale),
        Point(stemX, tipY),
        s.stemThickness,
        elementId: id,
      );
      _addGlyph(
        SmuflGlyph.flag8thUp,
        stemX - s.stemThickness / 2,
        tipY,
        scale: graceScale,
        elementId: id,
      );
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
        _addLine(
          Point(_x - 0.25, _yOf(q)),
          Point(_x + graceHeadWidth + 0.25, _yOf(q)),
          s.legerLineThickness,
          elementId: id,
        );
      }
      for (var q = 10; q <= position; q += 2) {
        _addLine(
          Point(_x - 0.25, _yOf(q)),
          Point(_x + graceHeadWidth + 0.25, _yOf(q)),
          s.legerLineThickness,
          elementId: id,
        );
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
    // A spacer takes its time (the advance) but has no ink to draw or hit.
    // It stays an anchor, with no width: text or a dynamic set on it (a
    // LilyPond `s1^"Fine"`) lands where it falls, and it breaks tie chains as
    // any rest does.
    if (element.hidden) {
      _tieInfos.add(_TieInfo(
        note: null,
        id: element.id,
        stemsDown: false,
        voice: voice,
        left: _x,
        right: _x,
        heads: const [],
      ));
      return (noteX: _x, inkRight: _x);
    }
    final (glyph, baseY) = switch (element.duration.base) {
      // The breve rest fills the space between the middle and fourth
      // staff lines.
      // The longa rest hangs like the breve's, two staff spaces deep.
      DurationBase.long => (SmuflGlyph.restLonga, 1.0),
      DurationBase.breve => (SmuflGlyph.restDoubleWhole, 2.0),
      DurationBase.oneHundredTwentyEighth => (SmuflGlyph.rest128th, 2.0),
      DurationBase.twoHundredFiftySixth => (SmuflGlyph.rest256th, 2.0),
      DurationBase.fiveHundredTwelfth => (SmuflGlyph.rest512th, 2.0),
      DurationBase.oneThousandTwentyFourth => (SmuflGlyph.rest1024th, 2.0),
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
    _tieInfos.add(
      _TieInfo(
        note: null,
        id: id,
        stemsDown: false,
        voice: voice,
        left: _x,
        right: _x + _glyphWidth(glyph),
        heads: const [],
      ),
    );

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
  /// [minNoteGap] after this element's ink ([inkRight]). [optical] adds the
  /// stem-direction correction ([_opticalGap]).
  void _advance(
    double fromX,
    double inkRight,
    NoteDuration duration,
    double log2Adjust, {
    double lyricReserve = 0,
    double optical = 0,
  }) {
    final baseLog2 = duration.base.log2Value.toDouble();
    final log2Duration = baseLog2 + _dotLog2[duration.dots] + log2Adjust;
    final ideal =
        (s.spacingBase + s.spacingPerLog2 * (4 + log2Duration) + optical) *
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

  /// The slur from ([x1], [y1]) to ([x2], [y2]) that best clears the ink
  /// between them, scored as LilyPond scores its candidates: each end lifted
  /// off its note by up to four spaces, the arc up to six spaces deeper than
  /// its natural depth, its control points following the line of the ends.
  /// A shape that touches ink under it is all but ruled out; among the rest
  /// the ends stay close to their notes, the arc stays shallow, and the slur
  /// slopes with the notes rather than steeply.
  (Point<double>, Point<double>, Point<double>, Point<double>) _scoredSlur(
    double x1,
    double x2,
    double y1,
    double y2, {
    required bool above,
    required double span,
  }) {
    final away = above ? -1.0 : 1.0;
    final width = x2 - x1;
    final arch = _slurArchDepth(span);
    (Point<double>, Point<double>, Point<double>, Point<double>) shape(
        double e1, double e2, double depth) {
      final lift = away * depth;
      return (
        Point(x1, e1),
        Point(x1 + width * 0.3, e1 + (e2 - e1) * 0.3 + lift),
        Point(x1 + width * 0.7, e1 + (e2 - e1) * 0.7 + lift),
        Point(x2, e2),
      );
    }

    if (width.abs() < 1) return shape(y1, y2, arch);
    // The ink under the arc, sampled once across its inner span: the ends
    // sit on their own notes, so the first and last 0.7 spaces are left out.
    const samples = 24;
    final sky = <double?>[
      for (var i = 0; i <= samples; i++)
        () {
          final x = x1 + width * i / samples;
          if ((x - x1).abs() < 0.7 || (x2 - x).abs() < 0.7) return null;
          return above
              ? _skylineTop(x - 0.3, x + 0.3, skipBarlines: true)
              : _skylineBottom(x - 0.3, x + 0.3, skipBarlines: true);
        }(),
    ];
    const clearance = 0.5;
    double violation(
        (Point<double>, Point<double>, Point<double>, Point<double>) c) {
      var worst = 0.0;
      for (var i = 1; i < 32; i++) {
        final p = _cubicPoint(c.$1, c.$2, c.$3, c.$4, i / 32);
        final k = ((p.x - x1) / width * samples).round().clamp(0, samples);
        final ink = sky[k];
        if (ink == null) continue;
        worst = max(
            worst, above ? p.y - (ink - clearance) : (ink + clearance) - p.y);
      }
      return worst;
    }

    final noteSlope = (y2 - y1) / width;
    (Point<double>, Point<double>, Point<double>, Point<double>)? best;
    var bestScore = double.infinity;
    // Up to four spaces: an end may have to rise to its stem or beam.
    const lifts = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0];
    for (final d1 in lifts) {
      for (final d2 in lifts) {
        final e1 = y1 + away * d1, e2 = y2 + away * d2;
        final slope = (e2 - e1) / width;
        final base = 6 * (d1 + d2) +
            2 * (d1 - d2).abs() +
            12 * (slope - noteSlope).abs() +
            (slope.abs() > 0.35 ? 20 * (slope.abs() - 0.35) : 0);
        if (base >= bestScore) continue;
        for (var extra = 0.0; extra <= 6; extra += 0.25) {
          final score = base + 3 * extra;
          if (score >= bestScore) break;
          final c = shape(e1, e2, arch + extra);
          final v = violation(c);
          final total = v > 0 ? score + 1000 + 100 * v : score;
          if (total < bestScore) {
            bestScore = total;
            best = c;
          }
          if (v <= 0) break; // deeper only costs more
        }
      }
    }
    return best!;
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

  /// A BARRE: the fret in Roman numerals above the chord it is held for.
  ///
  /// `CIII` is the classical-guitar convention (C for *ceja* / *barré*), which
  /// is what a player expects over the chord rather than a repeated "1" in the
  /// fingering digits. Drawn with the same label+bracket primitive as P.M. and
  /// let-ring, so it clears whatever ink is already above the staff and renders
  /// on tab as well as notation.
  ///
  /// ⚠ A barre is anchored to ONE chord, so the bracket is a self-span. It is
  /// deliberately NOT drawn as a half-barre even when the file names a string:
  /// `TabBarre.lowestString` is Guitar Pro's value preserved verbatim, and
  /// inferring "half" from it would be exactly the reinterpretation the model
  /// refuses to make.
  void _layoutBarres() {
    if (score.tabBarres.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final barre in score.tabBarres) {
      // Skip rather than throw: a barre can reference a note this system does
      // not contain (multi-system layout splits the score), and a mark is never
      // worth failing a page over.
      if (!infoOf.containsKey(barre.noteId)) continue;
      _textBracketAbove('C${barre.roman}', barre.noteId, barre.noteId, infoOf);
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
        _primitives.add(
          CurvePrimitive(
            Point(px, baseY),
            Point(px + half * 0.4, peakY),
            Point(px + half * 0.6, peakY),
            Point(px + half, baseY),
            thickness: vib.wide ? 0.16 : 0.13,
          ),
        );
        px += half;
      }
      _ink.expand(
        centerX - count * half / 2,
        baseY - amp - 0.2,
        centerX + count * half / 2,
        baseY + amp + 0.2,
      );
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
          // The same positions the signature was drawn at — derived for the
          // clefs without a hand-tuned table, which indexing the tables with
          // `!` crashed on (a soprano/baritone/French-violin key change).
          : _keyAccidentalPositions(_clef, sharp: _key.fifths > 0);
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

  /// The clef changes at [onset] take effect. Drawn here, in the flow, unless
  /// [defer] (the shared grid): then they are returned, to be drawn left of
  /// the column's notes once those are placed.
  List<Clef> _applyInlineClefs(Measure measure, Fraction onset,
      {bool defer = false}) {
    final pending = <Clef>[];
    for (final change in measure.inlineClefs) {
      if (change.onset == onset && change.clef != _clef) {
        if (defer) {
          _clef = change.clef;
          pending.add(change.clef);
        } else {
          _layoutClefChange(change.clef);
        }
      }
    }
    return pending;
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
    Pitch pitch,
    DurationBase base,
    NoteheadScheme scheme,
  ) {
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
    List<Fraction> onsets,
    Fraction? sub,
    int a,
    int b,
  ) =>
      sub != null &&
      _windowIndex(onsets[a], sub) != _windowIndex(onsets[b], sub);
}
