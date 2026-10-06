/// Measures (Takte) and tuplet spans.
library;

import '../internal/util.dart';
import '../theory/clef.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';
import 'element.dart';

/// A tuplet: [actual] notes played in the time of [normal], covering the
/// contiguous element range [startIndex]..[endIndex] of one measure.
///
/// A triplet of eighths is `TupletSpan(i, i+2, actual: 3, normal: 2)`:
/// each spanned element sounds `normal/actual` of its notated duration.
/// Spans must not overlap and cannot cross barlines.
class TupletSpan {
  /// Index of the first spanned element in the measure (inclusive).
  final int startIndex;

  /// Index of the last spanned element in the measure (inclusive).
  final int endIndex;

  /// Number of notated notes in the group (the printed digit).
  final int actual;

  /// The number of notes of the same value the group squeezes into.
  final int normal;

  /// Which voice the span's indices address: 0 = [elements] (voice 1),
  /// 1 = [voice2], 2 = [voice3], 3 = [voice4]. Indices are relative to that
  /// voice's own element list.
  final int voice;

  /// Creates a tuplet span.
  const TupletSpan(
    this.startIndex,
    this.endIndex, {
    required this.actual,
    required this.normal,
    this.voice = 0,
  })  : assert(startIndex >= 0, 'startIndex must be >= 0'),
        assert(endIndex >= startIndex, 'endIndex must be >= startIndex'),
        assert(actual >= 2, 'actual must be >= 2'),
        assert(normal >= 1, 'normal must be >= 1'),
        assert(voice >= 0 && voice <= 3, 'voice must be 0..3');

  /// Whether [index] lies inside this span.
  bool contains(int index) => index >= startIndex && index <= endIndex;

  @override
  bool operator ==(Object other) =>
      other is TupletSpan &&
      other.startIndex == startIndex &&
      other.endIndex == endIndex &&
      other.actual == actual &&
      other.normal == normal &&
      other.voice == voice;

  @override
  int get hashCode => Object.hash(startIndex, endIndex, actual, normal, voice);

  @override
  String toString() =>
      'TupletSpan($startIndex..$endIndex, $actual:$normal${voice == 0 ? '' : ', v${voice + 1}'})';
}

/// A clef change that takes effect inside a measure at [onset], expressed as a
/// fraction of a whole note from the measure start.
class InlineClefChange {
  /// The onset where the new clef should be drawn and become current.
  final Fraction onset;

  /// The clef in force after [onset].
  final Clef clef;

  /// Creates an inline clef change.
  const InlineClefChange(this.onset, this.clef);

  @override
  bool operator ==(Object other) =>
      other is InlineClefChange && other.onset == onset && other.clef == clef;

  @override
  int get hashCode => Object.hash(onset, clef);

  @override
  String toString() => 'InlineClefChange($onset, ${clef.name})';
}

/// A navigation / repeat-structure mark drawn above the staff (v0.7.1).
///
/// Targets ([segno], [coda]) sit at the **start** of their measure; every
/// jump instruction sits at the measure's **end**. A measure carries at
/// most one, via [Measure.navigation]; the pair that a real score needs on
/// the *same* bar (e.g. a coda target that is also a jump-from point) is
/// modelled by putting the target on the bar and the instruction on the
/// preceding one, as engravers do.
///
/// The layout engine draws the marks; `playbackTimeline` *executes* the jumps
/// (D.C. / D.S. / To Coda / al Fine / al Coda) when linearizing the score into
/// performance order.
enum NavigationMark {
  /// Segno sign (𝄋) — the target of a *dal segno* jump.
  segno,

  /// Coda sign (𝄌) — the target of a *to coda* jump.
  coda,

  /// "To Coda" — on the repeat, jump from here to the [coda].
  toCoda,

  /// "D.C." (da capo) — repeat from the beginning.
  daCapo,

  /// "D.C. al Fine" — repeat from the beginning, then stop at [fine].
  daCapoAlFine,

  /// "D.C. al Coda" — repeat from the beginning, then jump to the coda.
  daCapoAlCoda,

  /// "D.S." (dal segno) — repeat from the [segno].
  dalSegno,

  /// "D.S. al Fine" — repeat from the [segno], then stop at [fine].
  dalSegnoAlFine,

  /// "D.S. al Coda" — repeat from the [segno], then jump to the coda.
  dalSegnoAlCoda,

  /// "Fine" — the stopping point of a *da capo / dal segno al fine*.
  fine;

  /// Whether the mark is a jump *target* ([segno]/[coda]), drawn at the
  /// start of its measure. The rest are instructions, drawn at the end.
  bool get isTarget => this == segno || this == coda;
}

/// The barline drawn on a measure's **right** edge (the closing barline).
/// [BarlineStyle.normal] is a single thin line. A start/end repeat barline is
/// handled separately (see [Measure.startRepeat]/[Measure.endRepeat]) and
/// takes precedence over this style.
enum BarlineStyle {
  /// A single thin line (the default).
  normal,

  /// Two thin lines — a section division (`‖`).
  doubleBar,

  /// Thin + thick — end of a piece or movement (`𝄂`).
  finalBar,

  /// A single thick (heavy) line.
  heavy,

  /// A single dashed thin line.
  dashed,

  /// A single dotted thin line.
  dotted,

  /// A short thin stroke crossing only the top staff line (`tick`) — a
  /// breath/phrase divider common in hymn and chant notation.
  tick,

  /// A short thin stroke spanning only the middle of the staff (`short`) —
  /// a lighter phrase divider than a full barline.
  short,

  /// Thick + thin — a mirror of [finalBar] (`heavy-light`), used at the start
  /// of a section or as a reverse final barline.
  reverseFinal,

  /// No barline drawn at all.
  none;
}

/// One measure: an ordered list of notes, chords and rests, with optional
/// tuplet spans over contiguous element ranges and optional mid-score
/// changes taking effect at this measure.
class Measure {
  /// The measure's elements in temporal order (voice 1 — the upper voice
  /// when [voice2] is non-empty).
  final List<MusicElement> elements;

  /// Optional second (lower) voice. When non-empty, voice 1 stems are
  /// forced up and voice 2 stems down; elements sharing an onset align in
  /// one column. Tuplets may address any voice (see [TupletSpan.voice]).
  final List<MusicElement> voice2;

  /// Optional third voice (stems up, like voice 1). Carried through the model,
  /// interchange (MusicXML/MEI/MuseScore) and playback; the layout engine draws
  /// voices 1–2 today, so a third/fourth voice round-trips but is not yet
  /// engraved.
  final List<MusicElement> voice3;

  /// Optional fourth voice (stems down, like voice 2). See [voice3].
  final List<MusicElement> voice4;

  /// Tuplet spans (immutable, non-overlapping within a voice). Each addresses
  /// the voice named by [TupletSpan.voice] — voice 1 ([elements]) by default.
  final List<TupletSpan> tuplets;

  /// Clef change taking effect at this measure (drawn small at its start).
  final Clef? clefChange;

  /// Clef changes inside the measure, drawn at their onsets and applied to
  /// following elements.
  final List<InlineClefChange> inlineClefs;

  /// Key change taking effect at this measure (cancellation naturals are
  /// drawn for steps the new signature no longer alters).
  final KeySignature? keyChange;

  /// Time signature change taking effect at this measure.
  final TimeSignature? timeChange;

  /// Tempo (metronome) change taking effect at this measure's start, or null.
  /// The initial tempo lives on `Score.tempo`; `tempoMapOf` collects both into
  /// a `TempoMap` for variable-tempo playback.
  final Tempo? tempoChange;

  /// Whether a start-repeat barline (`|:`) opens this measure.
  final bool startRepeat;

  /// Whether an end-repeat barline (`:|`) closes this measure.
  final bool endRepeat;

  /// Volta (ending) number drawn as a bracket over this measure, or null.
  final int? volta;

  /// Multi-measure rest: this measure stands for [multiRest] measures of
  /// silence, drawn as an H-bar with the count above (v0.6.3). Must be
  /// ≥ 2. It holds no notes; its [elements] may keep the bar's rest as the
  /// anchor for marks set on the silent stretch (tempo text, a dynamic).
  final int? multiRest;

  /// Measure-repeat (simile) sign: this measure repeats the previous
  /// [measureRepeat] bar(s) — 1, 2 or 4 — drawn as the SMuFL repeat-bar glyph
  /// centred in the measure. Requires empty [elements] (the repeated content
  /// lives in the earlier bars). Null = an ordinary measure.
  final int? measureRepeat;

  /// Navigation / repeat-structure mark drawn above the staff (v0.7.1), or
  /// null. Targets sit at the measure start, instructions at its end.
  final NavigationMark? navigation;

  /// The style of this measure's closing (right) barline. Ignored when
  /// [endRepeat] is set (the repeat barline wins).
  final BarlineStyle barline;

  /// Whether this is a pickup (anacrusis) — an intentionally incomplete
  /// measure that is not counted in bar numbering. Conventionally the first
  /// measure of a tune when it is shorter than the meter; maps to MusicXML's
  /// `implicit="yes"`.
  final bool pickup;

  /// An explicit *intended* length for this bar (as a fraction of a whole
  /// note), overriding the prevailing time signature — for a mid-piece
  /// irregular bar (a cadenza, an inserted 5/4 bar in 4/4, a written-out
  /// upbeat) that intentionally holds a different amount than the meter without
  /// a full meter change. Null = use the meter's capacity. It marks the bar as
  /// intentional so pickup auto-detection and "fill the measure" checks don't
  /// flag it; see [capacityGiven].
  final Fraction? actualDuration;

  /// Creates a measure from [elements] (treat the lists as immutable).
  const Measure(
    this.elements, {
    this.voice2 = const [],
    this.voice3 = const [],
    this.voice4 = const [],
    this.tuplets = const [],
    this.clefChange,
    this.inlineClefs = const [],
    this.keyChange,
    this.timeChange,
    this.tempoChange,
    this.startRepeat = false,
    this.endRepeat = false,
    this.volta,
    this.multiRest,
    this.measureRepeat,
    this.navigation,
    this.barline = BarlineStyle.normal,
    this.pickup = false,
    this.actualDuration,
  })  : assert(volta == null || volta >= 1, 'volta must be >= 1'),
        assert(multiRest == null || multiRest >= 2, 'multiRest must be >= 2'),
        // Its rest may stay as an anchor for marks; it must hold no notes,
        // which the readers ensure (a const constructor cannot check that).
        assert(multiRest == null || voice2.length == 0,
            'a multi-measure rest holds no second voice'),
        assert(
            measureRepeat == null ||
                measureRepeat == 1 ||
                measureRepeat == 2 ||
                measureRepeat == 4,
            'measureRepeat must be 1, 2 or 4'),
        assert(measureRepeat == null || elements.length == 0,
            'a measure-repeat holds no elements');

  /// A copy of this measure with the given fields replaced.
  Measure copyWith({
    List<MusicElement>? elements,
    List<MusicElement>? voice2,
    List<MusicElement>? voice3,
    List<MusicElement>? voice4,
    List<TupletSpan>? tuplets,
    Clef? clefChange,
    List<InlineClefChange>? inlineClefs,
    KeySignature? keyChange,
    TimeSignature? timeChange,
    Tempo? tempoChange,
    bool? startRepeat,
    bool? endRepeat,
    int? volta,
    int? multiRest,
    int? measureRepeat,
    NavigationMark? navigation,
    BarlineStyle? barline,
    bool? pickup,
    Fraction? actualDuration,
  }) =>
      Measure(
        elements ?? this.elements,
        voice2: voice2 ?? this.voice2,
        voice3: voice3 ?? this.voice3,
        voice4: voice4 ?? this.voice4,
        tuplets: tuplets ?? this.tuplets,
        clefChange: clefChange ?? this.clefChange,
        inlineClefs: inlineClefs ?? this.inlineClefs,
        keyChange: keyChange ?? this.keyChange,
        timeChange: timeChange ?? this.timeChange,
        tempoChange: tempoChange ?? this.tempoChange,
        startRepeat: startRepeat ?? this.startRepeat,
        endRepeat: endRepeat ?? this.endRepeat,
        volta: volta ?? this.volta,
        multiRest: multiRest ?? this.multiRest,
        measureRepeat: measureRepeat ?? this.measureRepeat,
        navigation: navigation ?? this.navigation,
        barline: barline ?? this.barline,
        pickup: pickup ?? this.pickup,
        actualDuration: actualDuration ?? this.actualDuration,
      );

  /// The sounding duration of the element at [index] as an exact fraction
  /// of a whole note, scaled by its tuplet span if any: a triplet eighth
  /// sounds 1/12.
  Fraction effectiveDurationAt(int index, {int voice = 0}) {
    final list = voiceAt(voice);
    var fraction = list[index].duration.toFraction();
    for (final span in tuplets) {
      if (span.voice == voice && span.contains(index)) {
        fraction = fraction * Fraction(span.normal, span.actual);
        break;
      }
    }
    return fraction;
  }

  /// The element list for [voice] (0 = voice 1 / [elements], … 3 = [voice4]).
  List<MusicElement> voiceAt(int voice) => switch (voice) {
        1 => voice2,
        2 => voice3,
        3 => voice4,
        _ => elements,
      };

  /// The tuplet spans addressing [voice], with indices relative to that voice.
  List<TupletSpan> tupletsForVoice(int voice) => [
        for (final t in tuplets)
          if (t.voice == voice) t
      ];

  /// The exact sum of the (tuplet-adjusted) voice-1 element durations as
  /// a fraction of a whole note. Games compare this against
  /// `TimeSignature.measureCapacity` ("fill the measure" exercises); the
  /// layout engine does not enforce it.
  Fraction get totalDuration => [
        for (var i = 0; i < elements.length; i++) effectiveDurationAt(i),
      ].fold(Fraction.zero, (sum, f) => sum + f);

  /// This bar's intended capacity as a fraction of a whole note: the explicit
  /// [actualDuration] if set, else the prevailing [meter]'s length (or null
  /// when unmetered). Use this — not the raw meter — when checking whether the
  /// bar is full or intentionally irregular.
  Fraction? capacityGiven(TimeSignature? meter) =>
      actualDuration ?? meter?.toFraction();

  /// The exact sum of the voice-2 element durations.
  Fraction get voice2Duration => voice2.fold(
        Fraction.zero,
        (sum, element) => sum + element.duration.toFraction(),
      );

  /// All non-empty voices in order (voice 1 first). Convenient for codecs and
  /// playback that iterate every voice.
  List<List<MusicElement>> get voices => [
        elements,
        if (voice2.isNotEmpty) voice2,
        if (voice3.isNotEmpty) voice3,
        if (voice4.isNotEmpty) voice4,
      ];

  @override
  bool operator ==(Object other) =>
      other is Measure &&
      listEquals(other.elements, elements) &&
      listEquals(other.voice2, voice2) &&
      listEquals(other.voice3, voice3) &&
      listEquals(other.voice4, voice4) &&
      listEquals(other.tuplets, tuplets) &&
      other.clefChange == clefChange &&
      listEquals(other.inlineClefs, inlineClefs) &&
      other.keyChange == keyChange &&
      other.timeChange == timeChange &&
      other.tempoChange == tempoChange &&
      other.startRepeat == startRepeat &&
      other.endRepeat == endRepeat &&
      other.volta == volta &&
      other.multiRest == multiRest &&
      other.measureRepeat == measureRepeat &&
      other.navigation == navigation &&
      other.barline == barline &&
      other.pickup == pickup &&
      other.actualDuration == actualDuration;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(elements),
      Object.hashAll(voice2),
      Object.hashAll(voice3),
      Object.hashAll(voice4),
      Object.hashAll(tuplets),
      clefChange,
      Object.hashAll(inlineClefs),
      keyChange,
      timeChange,
      tempoChange,
      startRepeat,
      endRepeat,
      volta,
      multiRest,
      measureRepeat,
      navigation,
      barline,
      pickup,
      actualDuration);

  @override
  String toString() => 'Measure(${elements.length} elements'
      '${voice2.isEmpty ? '' : ' + ${voice2.length} in voice 2'}'
      '${tuplets.isEmpty ? '' : ', ${tuplets.length} tuplets'}'
      '${pickup ? ', pickup' : ''})';
}

/// Returns [measures] with the first flagged as a [Measure.pickup] anacrusis
/// when the [meter] is known, there is more than one measure, and the first is
/// a non-empty measure shorter than a full bar. Returns the input unchanged
/// otherwise (so it is safe to call unconditionally). Encodes the universal
/// engraving convention: a short opening bar is an upbeat, uncounted.
List<Measure> withDetectedPickup(List<Measure> measures, TimeSignature? meter) {
  if (meter == null || measures.length < 2) return measures;
  final first = measures.first;
  if (first.pickup ||
      first.multiRest != null ||
      first.elements.isEmpty ||
      first.actualDuration != null) {
    // An explicit actual length means the bar is intentionally sized — don't
    // second-guess it as an anacrusis.
    return measures;
  }
  if (first.totalDuration >= meter.toFraction()) return measures;
  return [first.copyWith(pickup: true), ...measures.skip(1)];
}
