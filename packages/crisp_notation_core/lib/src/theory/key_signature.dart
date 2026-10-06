/// Key signatures on the circle of fifths, plus non-standard signatures.
library;

import 'interval.dart';
import 'pitch.dart';

/// One accidental in a non-standard [KeySignature]: the [step] it alters and
/// by how much ([alter]: 1 sharp, -1 flat, ±2 double, 0 explicit natural).
class KeyAccidental {
  /// The diatonic step this accidental applies to (in every octave).
  final Step step;

  /// The alteration in semitones: -2..2.
  final int alter;

  /// Creates a key-signature accidental on [step] of [alter] semitones.
  const KeyAccidental(this.step, this.alter)
      : assert(alter >= -2 && alter <= 2, 'alter must be -2..2');

  @override
  bool operator ==(Object other) =>
      other is KeyAccidental && other.step == step && other.alter == alter;

  @override
  int get hashCode => Object.hash(step, alter);

  @override
  String toString() => 'KeyAccidental(${step.name}, $alter)';
}

/// A key signature.
///
/// A **standard** signature is a count of [fifths] on the circle of fifths:
/// positive = sharps (1 = G major/E minor), negative = flats (-1 = F major/
/// D minor), 0 = C major/A minor. A **non-standard** signature ([custom] set,
/// via [KeySignature.custom]) carries an explicit list of accidentals in the
/// order they are written — for modal, atonal or otherwise irregular
/// signatures (e.g. one sharp and one flat, or a non-traditional order) that
/// the circle of fifths cannot express.
class KeySignature {
  /// Sharps (positive) or flats (negative) in a standard signature, -7..7.
  /// Always 0 for a non-standard ([custom]) signature.
  final int fifths;

  /// The explicit accidentals of a non-standard signature, in writing order,
  /// or null for a standard circle-of-fifths signature.
  final List<KeyAccidental>? custom;

  /// Creates a standard key signature with [fifths] sharps (positive) or
  /// flats (negative).
  const KeySignature(this.fifths)
      : custom = null,
        assert(fifths >= -7 && fifths <= 7, 'fifths must be -7..7');

  /// Creates a non-standard key signature from explicit [accidentals], in the
  /// order they are written on the staff.
  const KeySignature.custom(List<KeyAccidental> accidentals)
      : fifths = 0,
        custom = accidentals;

  /// Whether this is a standard circle-of-fifths signature (as opposed to a
  /// [KeySignature.custom] one).
  bool get isStandard => custom == null;

  /// This key moved by [interval] (up, or down when [descending]): its major
  /// tonic moves along the line of fifths, and a result beyond ±7 wraps to
  /// the enharmonic key (G-sharp major becomes A-flat major). A non-standard
  /// signature has no tonic to move and is returned as written.
  KeySignature transposedBy(Interval interval, {bool descending = false}) {
    if (!isStandard) return this;
    const stepOfFifth = {
      0: Step.c,
      1: Step.g,
      2: Step.d,
      3: Step.a,
      4: Step.e,
      5: Step.b,
    };
    // F (-1) is the one natural tonic below C on the circle.
    final base = ((fifths % 7) + 7) % 7;
    final step = base == 6 ? Step.f : stepOfFifth[base]!;
    final baseIndex = base == 6 ? -1 : base;
    final tonic = Pitch(step, alter: (fifths - baseIndex) ~/ 7);
    final moved = tonic.transposeBy(interval, descending: descending);
    const indexOfStep = {
      Step.c: 0,
      Step.d: 2,
      Step.e: 4,
      Step.f: -1,
      Step.g: 1,
      Step.a: 3,
      Step.b: 5,
    };
    var f = indexOfStep[moved.step]! + 7 * moved.alter;
    while (f > 7) {
      f -= 12;
    }
    while (f < -7) {
      f += 12;
    }
    return KeySignature(f);
  }

  /// Standard order of sharps: F C G D A E B. Flats use the reverse.
  static const List<Step> _sharpOrder = [
    Step.f,
    Step.c,
    Step.g,
    Step.d,
    Step.a,
    Step.e,
    Step.b,
  ];

  /// The steps altered by this signature, in the order they are written on
  /// the staff: sharps F C G D A E B, flats B E A D G C F, or a custom
  /// signature's own order.
  List<Step> get alteredSteps {
    final c = custom;
    if (c != null) return [for (final acc in c) acc.step];
    return fifths >= 0
        ? _sharpOrder.sublist(0, fifths)
        : _sharpOrder.reversed.toList().sublist(0, -fifths);
  }

  /// The alteration this signature applies to [step]: 1 (sharp), -1 (flat),
  /// ±2 (double) or 0. A custom signature returns the first matching
  /// accidental's alter, or 0 if [step] is unaltered.
  int alterFor(Step step) {
    final c = custom;
    if (c != null) {
      for (final acc in c) {
        if (acc.step == step) return acc.alter;
      }
      return 0;
    }
    if (fifths > 0 && _sharpOrder.indexOf(step) < fifths) return 1;
    if (fifths < 0 && _sharpOrder.indexOf(step) >= 7 + fifths) return -1;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is KeySignature &&
      other.fifths == fifths &&
      _sameAccidentals(other.custom, custom);

  static bool _sameAccidentals(List<KeyAccidental>? a, List<KeyAccidental>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        fifths,
        custom == null ? null : Object.hashAll(custom!),
      );

  @override
  String toString() {
    final c = custom;
    if (c != null) return 'KeySignature.custom($c)';
    return 'KeySignature(${fifths >= 0 ? '+' : ''}$fifths)';
  }
}
