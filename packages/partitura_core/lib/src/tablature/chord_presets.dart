/// Ready-made [ChordDiagram]s for the fretted instruments whose tunings ship
/// as presets — ukulele, 5-string banjo (open G) and mandolin. Frets are given
/// in the instrument's tuning order (low string first), matching how
/// `layoutChordDiagram` reads a [ChordDiagram.frets] list.
library;

import '../model/element.dart';

/// Common open-position chord diagrams for the preset fretted instruments.
///
/// These are conveniences for lead sheets and teaching material; each matches
/// its instrument's string count so it renders directly with `TabStaffView` /
/// `placeChordDiagram`.
abstract final class ChordPresets {
  // --- Ukulele (standard reentrant g-C-E-A, 4 strings) --------------------

  /// Ukulele C major (A string, 3rd fret).
  static const ukuleleC =
      ChordDiagram([0, 0, 0, 3], name: 'C', fingers: [null, null, null, 3]);

  /// Ukulele F major.
  static const ukuleleF =
      ChordDiagram([2, 0, 1, 0], name: 'F', fingers: [2, null, 1, null]);

  /// Ukulele G major.
  static const ukuleleG =
      ChordDiagram([0, 2, 3, 2], name: 'G', fingers: [null, 1, 3, 2]);

  /// Ukulele A minor.
  static const ukuleleAm =
      ChordDiagram([2, 0, 0, 0], name: 'Am', fingers: [2, null, null, null]);

  /// Every ukulele preset, in a stable order.
  static const ukulele = [ukuleleC, ukuleleF, ukuleleG, ukuleleAm];

  // --- 5-string banjo (open G: g-D-G-B-D) ---------------------------------

  /// Banjo G major — every string open in open-G tuning.
  static const banjoG = ChordDiagram([0, 0, 0, 0, 0], name: 'G');

  /// Banjo C major (open G tuning).
  static const banjoC = ChordDiagram([0, 2, 0, 1, 2],
      name: 'C', fingers: [null, 2, null, 1, 3]);

  /// Banjo D7 (open G tuning).
  static const banjoD7 = ChordDiagram([0, 0, 0, 2, 0], name: 'D7',
      fingers: [null, null, null, 1, null]);

  /// Every banjo preset, in a stable order.
  static const banjo = [banjoG, banjoC, banjoD7];

  // --- Mandolin (G-D-A-E, 4 courses) --------------------------------------

  /// Mandolin G major.
  static const mandolinG =
      ChordDiagram([0, 0, 2, 3], name: 'G', fingers: [null, null, 1, 2]);

  /// Mandolin D major.
  static const mandolinD =
      ChordDiagram([2, 0, 0, 2], name: 'D', fingers: [1, null, null, 2]);

  /// Mandolin C major.
  static const mandolinC =
      ChordDiagram([0, 2, 3, 0], name: 'C', fingers: [null, 1, 2, null]);

  /// Every mandolin preset, in a stable order.
  static const mandolin = [mandolinG, mandolinD, mandolinC];
}
