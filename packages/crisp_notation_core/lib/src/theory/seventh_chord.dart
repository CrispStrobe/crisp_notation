/// Seventh chords (Septakkorde) — the four-note counterpart to [Triad].
library;

import 'chord_analysis.dart';
import 'interval.dart';
import 'pitch.dart';

/// A four-note seventh chord built in thirds on a [root], optionally inverted.
///
/// The counterpart to [Triad] for the seventh-chord [ChordType]s: dominant,
/// major, minor, half-diminished, fully-diminished, minor-major and augmented
/// sevenths. Spelled with real intervals (not just semitones) so accidentals
/// engrave correctly and [identifyChord] / `romanNumeralOf` recognize the
/// result — e.g. `SeventhChord(Pitch(Step.g, octave: 4),
/// ChordType.dominantSeventh)` is G4–B4–D5–F5, read as `V7` in C.
class SeventhChord {
  /// The chord's root (its octave anchors the returned pitches).
  final Pitch root;

  /// The seventh-chord quality; must be one of the four-note seventh types.
  final ChordType type;

  /// Inversion: 0 root position, 1 first (third in the bass), 2 second (fifth),
  /// 3 third (seventh in the bass).
  final int inversion;

  /// Creates a seventh chord of [type] on [root]. [type] must be a seventh
  /// chord (see [isSeventhType]).
  SeventhChord(this.root, this.type, {this.inversion = 0})
      : assert(inversion >= 0 && inversion <= 3, 'inversion must be 0..3'),
        assert(isSeventhType(type), 'type must be a seventh chord');

  /// Whether [type] is one of the seventh-chord qualities this builds.
  static bool isSeventhType(ChordType type) =>
      _spelling.containsKey(type);

  /// Spelled (third, fifth, seventh) intervals above the root per seventh type.
  static const Map<ChordType, (Interval, Interval, Interval)> _spelling = {
    ChordType.dominantSeventh: (
      Interval.majorThird,
      Interval.perfectFifth,
      Interval.minorSeventh
    ),
    ChordType.majorSeventh: (
      Interval.majorThird,
      Interval.perfectFifth,
      Interval.majorSeventh
    ),
    ChordType.minorSeventh: (
      Interval.minorThird,
      Interval.perfectFifth,
      Interval.minorSeventh
    ),
    ChordType.halfDiminishedSeventh: (
      Interval.minorThird,
      Interval.diminishedFifth,
      Interval.minorSeventh
    ),
    ChordType.diminishedSeventh: (
      Interval.minorThird,
      Interval.diminishedFifth,
      Interval.diminishedSeventh
    ),
    ChordType.minorMajorSeventh: (
      Interval.minorThird,
      Interval.perfectFifth,
      Interval.majorSeventh
    ),
    ChordType.augmentedSeventh: (
      Interval.majorThird,
      Interval.augmentedFifth,
      Interval.minorSeventh
    ),
  };

  /// The chord tones from the bass upward. Root position returns
  /// root–third–fifth–seventh; inversions move the lowest notes up an octave,
  /// e.g. first inversion of G7 is B4–D5–F5–G5.
  List<Pitch> get pitches {
    final (third, fifth, seventh) = _spelling[type]!;
    final rootPosition = [
      root,
      root.transposeBy(third),
      root.transposeBy(fifth),
      root.transposeBy(seventh),
    ];
    return [
      ...rootPosition.sublist(inversion),
      ...rootPosition
          .sublist(0, inversion)
          .map((p) => p.transposeBy(Interval.perfectOctave)),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is SeventhChord &&
      other.root == root &&
      other.type == type &&
      other.inversion == inversion;

  @override
  int get hashCode => Object.hash(root, type, inversion);

  @override
  String toString() =>
      'SeventhChord($root ${type.name}${inversion == 0 ? '' : ', inv $inversion'})';
}
