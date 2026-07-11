/// Measures (Takte) and tuplet spans.
library;

import '../internal/util.dart';
import '../theory/clef.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
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

  /// Creates a tuplet span.
  const TupletSpan(
    this.startIndex,
    this.endIndex, {
    required this.actual,
    required this.normal,
  })  : assert(startIndex >= 0, 'startIndex must be >= 0'),
        assert(endIndex >= startIndex, 'endIndex must be >= startIndex'),
        assert(actual >= 2, 'actual must be >= 2'),
        assert(normal >= 1, 'normal must be >= 1');

  /// Whether [index] lies inside this span.
  bool contains(int index) => index >= startIndex && index <= endIndex;

  @override
  bool operator ==(Object other) =>
      other is TupletSpan &&
      other.startIndex == startIndex &&
      other.endIndex == endIndex &&
      other.actual == actual &&
      other.normal == normal;

  @override
  int get hashCode => Object.hash(startIndex, endIndex, actual, normal);

  @override
  String toString() => 'TupletSpan($startIndex..$endIndex, $actual:$normal)';
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

/// One measure: an ordered list of notes, chords and rests, with optional
/// tuplet spans over contiguous element ranges and optional mid-score
/// changes taking effect at this measure.
class Measure {
  /// The measure's elements in temporal order (voice 1 — the upper voice
  /// when [voice2] is non-empty).
  final List<MusicElement> elements;

  /// Optional second (lower) voice. When non-empty, voice 1 stems are
  /// forced up and voice 2 stems down; elements sharing an onset align in
  /// one column. Tuplets are voice-1 only in v0.4.
  final List<MusicElement> voice2;

  /// Tuplet spans over [elements] (treat as immutable, non-overlapping).
  final List<TupletSpan> tuplets;

  /// Clef change taking effect at this measure (drawn small at its start).
  final Clef? clefChange;

  /// Key change taking effect at this measure (cancellation naturals are
  /// drawn for steps the new signature no longer alters).
  final KeySignature? keyChange;

  /// Time signature change taking effect at this measure.
  final TimeSignature? timeChange;

  /// Whether a start-repeat barline (`|:`) opens this measure.
  final bool startRepeat;

  /// Whether an end-repeat barline (`:|`) closes this measure.
  final bool endRepeat;

  /// Volta (ending) number drawn as a bracket over this measure, or null.
  final int? volta;

  /// Multi-measure rest: this measure stands for [multiRest] measures of
  /// silence, drawn as an H-bar with the count above (v0.6.3). Must be
  /// ≥ 2 and requires empty [elements]/[voice2].
  final int? multiRest;

  /// Navigation / repeat-structure mark drawn above the staff (v0.7.1), or
  /// null. Targets sit at the measure start, instructions at its end.
  final NavigationMark? navigation;

  /// Creates a measure from [elements] (treat the lists as immutable).
  const Measure(
    this.elements, {
    this.voice2 = const [],
    this.tuplets = const [],
    this.clefChange,
    this.keyChange,
    this.timeChange,
    this.startRepeat = false,
    this.endRepeat = false,
    this.volta,
    this.multiRest,
    this.navigation,
  })  : assert(volta == null || volta >= 1, 'volta must be >= 1'),
        assert(multiRest == null || multiRest >= 2, 'multiRest must be >= 2'),
        assert(multiRest == null || elements.length == 0,
            'a multi-measure rest holds no elements');

  /// The sounding duration of the element at [index] as an exact fraction
  /// of a whole note, scaled by its tuplet span if any: a triplet eighth
  /// sounds 1/12.
  Fraction effectiveDurationAt(int index) {
    var fraction = elements[index].duration.toFraction();
    for (final span in tuplets) {
      if (span.contains(index)) {
        fraction = fraction * Fraction(span.normal, span.actual);
        break;
      }
    }
    return fraction;
  }

  /// The exact sum of the (tuplet-adjusted) voice-1 element durations as
  /// a fraction of a whole note. Games compare this against
  /// `TimeSignature.measureCapacity` ("fill the measure" exercises); the
  /// layout engine does not enforce it.
  Fraction get totalDuration => [
        for (var i = 0; i < elements.length; i++) effectiveDurationAt(i),
      ].fold(Fraction.zero, (sum, f) => sum + f);

  /// The exact sum of the voice-2 element durations.
  Fraction get voice2Duration => voice2.fold(
        Fraction.zero,
        (sum, element) => sum + element.duration.toFraction(),
      );

  @override
  bool operator ==(Object other) =>
      other is Measure &&
      listEquals(other.elements, elements) &&
      listEquals(other.voice2, voice2) &&
      listEquals(other.tuplets, tuplets) &&
      other.clefChange == clefChange &&
      other.keyChange == keyChange &&
      other.timeChange == timeChange &&
      other.startRepeat == startRepeat &&
      other.endRepeat == endRepeat &&
      other.volta == volta &&
      other.multiRest == multiRest &&
      other.navigation == navigation;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(elements),
      Object.hashAll(voice2),
      Object.hashAll(tuplets),
      clefChange,
      keyChange,
      timeChange,
      startRepeat,
      endRepeat,
      volta,
      multiRest,
      navigation);

  @override
  String toString() => 'Measure(${elements.length} elements'
      '${voice2.isEmpty ? '' : ' + ${voice2.length} in voice 2'}'
      '${tuplets.isEmpty ? '' : ', ${tuplets.length} tuplets'})';
}
