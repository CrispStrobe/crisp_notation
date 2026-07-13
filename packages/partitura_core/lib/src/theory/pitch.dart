/// Pitch fundamentals: diatonic steps and pitches in scientific notation.
///
/// Binding conventions (see docs/DESIGN.md): scientific pitch notation with
/// middle C = C4 (MIDI 60), and staff positions counted from the bottom
/// staff line (0) upward, one step per line/space.
library;

import 'clef.dart';
import 'interval.dart';

/// The seven diatonic letter names.
enum Step {
  /// C — 0 semitones above C.
  c(0),

  /// D — 2 semitones above C.
  d(2),

  /// E — 4 semitones above C.
  e(4),

  /// F — 5 semitones above C.
  f(5),

  /// G — 7 semitones above C.
  g(7),

  /// A — 9 semitones above C.
  a(9),

  /// B — 11 semitones above C (German: H).
  b(11);

  const Step(this.semitonesFromC);

  /// Semitones above C (within one octave) of this step's natural note.
  final int semitonesFromC;
}

/// A quarter-tone (microtonal) accidental beyond the standard semitone
/// [Pitch.alter]. Each names its cents offset from the natural note and its
/// default SMuFL glyph; the drawn glyph is remappable (for Arabic, Turkish and
/// other systems) via the layout settings.
enum MicrotonalAccidental {
  /// Quarter-tone flat, −50 cents (Stein half-flat).
  halfFlat(-50, 'accidentalQuarterToneFlatStein'),

  /// Quarter-tone sharp, +50 cents (Stein half-sharp).
  halfSharp(50, 'accidentalQuarterToneSharpStein'),

  /// Three-quarter-tone flat, −150 cents (Zimmermann).
  sesquiFlat(-150, 'accidentalThreeQuarterTonesFlatZimmermann'),

  /// Three-quarter-tone sharp, +150 cents (Stein-Zimmermann).
  sesquiSharp(150, 'accidentalThreeQuarterTonesSharpStein');

  const MicrotonalAccidental(this.cents, this.defaultGlyph);

  /// Offset from the natural note, in cents (±50, ±150).
  final int cents;

  /// The default SMuFL glyph name for this accidental.
  final String defaultGlyph;
}

/// A pitch in scientific pitch notation (middle C = C4).
class Pitch {
  /// Diatonic letter name.
  final Step step;

  /// Chromatic alteration in semitones: -2 (double flat) to 2 (double sharp).
  final int alter;

  /// Octave in scientific pitch notation; octaves change at C.
  final int octave;

  /// An optional microtonal (quarter-tone) accidental. When set, [alter] must
  /// be 0 — the microtonal accidental fully describes the alteration — and the
  /// pitch sounds [centsOffset] cents from its natural note.
  final MicrotonalAccidental? microtone;

  /// Creates a pitch; defaults to the natural note in octave 4.
  const Pitch(this.step, {this.alter = 0, this.octave = 4, this.microtone})
      : assert(alter >= -2 && alter <= 2, 'alter must be -2..2'),
        assert(microtone == null || alter == 0,
            'a microtonal accidental requires alter == 0');

  /// Parses notations like `c4`, `f#3`, `bb2` (B♭2), `ebb5` (E𝄫5) or `gn4`
  /// (G natural). Case-insensitive. The accidental is one of `##`, `#`,
  /// `bb`, `b`, `n` (explicit natural) or absent; the octave is a decimal
  /// integer. Throws a [FormatException] on anything else.
  static Pitch parse(String input) {
    final match =
        RegExp(r'^([a-gA-G])(##|bb|#|b|n)?(-?\d+)$').firstMatch(input.trim());
    if (match == null) {
      throw FormatException('Invalid pitch: "$input"');
    }
    const alters = {'##': 2, '#': 1, 'b': -1, 'bb': -2, 'n': 0, null: 0};
    return Pitch(
      Step.values.byName(match[1]!.toLowerCase()),
      alter: alters[match[2]]!,
      octave: int.parse(match[3]!),
    );
  }

  /// MIDI note number; C4 == 60, A4 == 69. A microtonal accidental does not
  /// change the (integer) MIDI number — see [centsOffset] for its tuning.
  int get midiNumber => (octave + 1) * 12 + step.semitonesFromC + alter;

  /// Cents this pitch sounds away from [midiNumber] (0 unless [microtone] is
  /// set): +50 for a half-sharp, −150 for a three-quarter-tone flat, etc. Use
  /// it to drive a pitch bend when playing a microtonal note.
  int get centsOffset => microtone?.cents ?? 0;

  /// Absolute diatonic index used for staff arithmetic (C0 == 0), ignoring
  /// alteration: one unit per letter name.
  int get diatonicIndex => octave * 7 + step.index;

  /// Diatonic staff position for [clef]: 0 = bottom staff line, +1 per
  /// line/space upward. Values below 0 or above 8 imply ledger lines.
  /// Treble: E4 == 0 (bottom line). Bass: G2 == 0.
  int staffPosition(Clef clef) => diatonicIndex - clef.bottomLineDiatonicIndex;

  /// The pitch [interval] above this one (below when [descending]), spelled
  /// diatonically: C4 up a major third is E4, C4 up a minor third is E♭4.
  ///
  /// Throws an [ArgumentError] if the result would need an alteration
  /// beyond a double sharp/flat.
  Pitch transposeBy(Interval interval, {bool descending = false}) {
    final direction = descending ? -1 : 1;
    final targetDiatonic = diatonicIndex + direction * (interval.number - 1);
    final targetStep = Step.values[targetDiatonic % 7];
    final targetOctave = (targetDiatonic - targetDiatonic % 7) ~/ 7;
    final naturalSemitones = targetOctave * 12 + targetStep.semitonesFromC;
    final targetSemitones = octave * 12 +
        step.semitonesFromC +
        alter +
        direction * interval.semitones;
    final targetAlter = targetSemitones - naturalSemitones;
    if (targetAlter < -2 || targetAlter > 2) {
      throw ArgumentError(
        'Transposing $this ${descending ? 'down' : 'up'} by $interval needs '
        'an alteration of $targetAlter semitones, beyond double sharp/flat',
      );
    }
    return Pitch(targetStep, alter: targetAlter, octave: targetOctave);
  }

  /// Whether this pitch sounds identical to [other] (same MIDI number) even
  /// if spelled differently, e.g. C♯4 and D♭4.
  bool isEnharmonicWith(Pitch other) => midiNumber == other.midiNumber;

  @override
  bool operator ==(Object other) =>
      other is Pitch &&
      other.step == step &&
      other.alter == alter &&
      other.octave == octave &&
      other.microtone == microtone;

  @override
  int get hashCode => Object.hash(step, alter, octave, microtone);

  @override
  String toString() {
    const accidentals = {-2: 'bb', -1: 'b', 0: '', 1: '#', 2: '##'};
    const micro = {
      MicrotonalAccidental.halfFlat: 'd', // half-flat
      MicrotonalAccidental.halfSharp: 't', // half-sharp (¼-tone)
      MicrotonalAccidental.sesquiFlat: 'db',
      MicrotonalAccidental.sesquiSharp: 't#',
    };
    final acc = microtone != null ? micro[microtone] : accidentals[alter];
    return '${step.name.toUpperCase()}$acc$octave';
  }
}
