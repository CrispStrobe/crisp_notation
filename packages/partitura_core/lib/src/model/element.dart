/// Score elements: notes, chords and rests.
library;

import '../internal/util.dart';
import '../theory/duration.dart';
import '../theory/pitch.dart';

/// Articulation marks attachable to a [NoteElement].
enum Articulation {
  /// Short, detached (dot).
  staccato,

  /// Held for full value (dash).
  tenuto,

  /// Emphasized (horizontal wedge).
  accent,

  /// Strongly emphasized (vertical wedge).
  marcato,

  /// Held beyond its value (fermata; always drawn above the element).
  fermata,
}

/// Arpeggio (rolled chord) direction, drawn as a vertical wavy line to the
/// left of the chord (v0.7.2). The arrow points the way the roll travels.
enum Arpeggio {
  /// Rolled low → high; arrowhead at the top.
  up,

  /// Rolled high → low; arrowhead at the bottom.
  down,
}

/// Ornaments drawn above a note (v0.6.2).
enum Ornament {
  /// Trill (tr).
  trill,

  /// Short trill / upper mordent (squiggle without a line).
  shortTrill,

  /// Mordent / lower mordent (squiggle with a vertical line).
  mordent,

  /// Turn (Doppelschlag).
  turn,
}

/// A single rhythmic event in a measure: a note/chord or a rest.
///
/// Elements are value types; treat their lists as immutable. The optional
/// [id] tags the element for the interaction layer (hit testing,
/// highlighting) — ids should be unique within a score.
sealed class MusicElement {
  /// Identifier for hit testing and highlighting; null = not addressable.
  final String? id;

  /// The element's rhythmic duration.
  final NoteDuration duration;

  /// Creates an element with [duration] and an optional interaction [id].
  const MusicElement({required this.duration, this.id});
}

/// The shape of a note's head, overriding the default oval. Applies to the
/// whole element (all pitches of a chord); the duration still selects the
/// filled/open/whole/double-whole variant of the shape.
enum NoteheadShape {
  /// The normal oval notehead (default).
  normal,

  /// An "x" head — unpitched / percussion, or a dead note.
  x,

  /// A diamond head — harmonics and some unpitched notation.
  diamond,

  /// An upward triangle head — a common shape-note / percussion head.
  triangleUp,

  /// A slash head — rhythm-only ("play the chord") notation.
  slash,

  /// A circled-x head — for special effects and cue markings.
  circleX,
}

/// A note (one pitch) or chord (several pitches) sharing one duration and,
/// when rendered, one stem.
class NoteElement extends MusicElement {
  /// The sounding pitches; length 1 = single note, more = chord.
  final List<Pitch> pitches;

  /// Accidental override: `true` forces an accidental (courtesy accidental),
  /// `false` hides it, `null` (default) shows one exactly when the pitch
  /// deviates from what the key signature and earlier accidentals in the
  /// measure imply.
  final bool? showAccidental;

  /// Ties this note/chord to the **next** note element (also across a
  /// barline). Only pitches present identically in both elements are
  /// tied; a tie into a rest or nothing draws no curve.
  final bool tieToNext;

  /// Articulation marks: drawn on the notehead side (opposite the stem),
  /// stacked outward in enum order; a fermata always goes above.
  final Set<Articulation> articulations;

  /// Grace notes (acciaccatura group) played before this element, drawn
  /// as small slashed eighths to its left.
  final List<Pitch> graceNotes;

  /// Ornament drawn above the element (above a fermata when both exist).
  final Ornament? ornament;

  /// Fingering digits (0–9) stacked above the note, in list order from the
  /// notehead upward. Usually one per pitch of a chord, but the length is
  /// not tied to [pitches]; an empty list draws nothing.
  final List<int> fingerings;

  /// Arpeggio (rolled chord) sign drawn as a vertical wavy line to the left
  /// of the chord, or null. Model-only (no DSL shorthand).
  final Arpeggio? arpeggio;

  /// Single-note tremolo: 1–5 strokes drawn through the stem, or null. Model
  /// only. Requires a stemmed note (ignored on whole notes and breves).
  final int? tremolo;

  /// The notehead shape for this element (default [NoteheadShape.normal]).
  final NoteheadShape notehead;

  /// Creates a note or chord from [pitches] and a [duration].
  ///
  /// [pitches] must be non-empty. (Not asserted: list lengths cannot be
  /// checked in a const constructor.)
  const NoteElement({
    required this.pitches,
    required super.duration,
    this.showAccidental,
    this.tieToNext = false,
    this.articulations = const {},
    this.graceNotes = const [],
    this.ornament,
    this.fingerings = const [],
    this.arpeggio,
    this.tremolo,
    this.notehead = NoteheadShape.normal,
    super.id,
  });

  /// Convenience for a single-pitch note.
  NoteElement.note(
    Pitch pitch,
    NoteDuration duration, {
    bool? showAccidental,
    bool tieToNext = false,
    Set<Articulation> articulations = const {},
    List<Pitch> graceNotes = const [],
    Ornament? ornament,
    List<int> fingerings = const [],
    Arpeggio? arpeggio,
    int? tremolo,
    NoteheadShape notehead = NoteheadShape.normal,
    String? id,
  }) : this(
          pitches: [pitch],
          duration: duration,
          showAccidental: showAccidental,
          tieToNext: tieToNext,
          articulations: articulations,
          graceNotes: graceNotes,
          ornament: ornament,
          fingerings: fingerings,
          arpeggio: arpeggio,
          tremolo: tremolo,
          notehead: notehead,
          id: id,
        );

  @override
  bool operator ==(Object other) =>
      other is NoteElement &&
      other.duration == duration &&
      other.showAccidental == showAccidental &&
      other.tieToNext == tieToNext &&
      other.ornament == ornament &&
      other.id == id &&
      other.arpeggio == arpeggio &&
      other.tremolo == tremolo &&
      other.notehead == notehead &&
      listEquals(other.pitches, pitches) &&
      setEquals(other.articulations, articulations) &&
      listEquals(other.graceNotes, graceNotes) &&
      listEquals(other.fingerings, fingerings);

  @override
  int get hashCode => Object.hash(
      duration,
      showAccidental,
      tieToNext,
      ornament,
      arpeggio,
      tremolo,
      notehead,
      id,
      Object.hashAll(pitches),
      Object.hashAllUnordered(articulations),
      Object.hashAll(graceNotes),
      Object.hashAll(fingerings));

  @override
  String toString() =>
      'NoteElement(${pitches.join('+')}, $duration${tieToNext ? ', tied' : ''}'
      '${articulations.isEmpty ? '' : ', ${articulations.map((a) => a.name).join('+')}'}'
      '${graceNotes.isEmpty ? '' : ', grace: ${graceNotes.join('+')}'}'
      '${fingerings.isEmpty ? '' : ', fingers: ${fingerings.join(',')}'}'
      '${arpeggio == null ? '' : ', ${arpeggio!.name} arpeggio'}'
      '${tremolo == null ? '' : ', tremolo $tremolo'}'
      '${notehead == NoteheadShape.normal ? '' : ', ${notehead.name} head'}'
      '${id == null ? '' : ', id: $id'})';
}

/// A slur between two note elements, referenced by their ids.
///
/// The start element must come before the end element in reading order;
/// both ids must exist in the score (the layout engine throws an
/// [ArgumentError] otherwise). Use ties ([NoteElement.tieToNext]) for
/// same-pitch connections; slurs are phrasing marks over any pitches.
class Slur {
  /// Id of the note element the slur starts on.
  final String startId;

  /// Id of the note element the slur ends on.
  final String endId;

  /// Creates a slur from [startId] to [endId].
  const Slur(this.startId, this.endId);

  @override
  bool operator ==(Object other) =>
      other is Slur && other.startId == startId && other.endId == endId;

  @override
  int get hashCode => Object.hash(startId, endId);

  @override
  String toString() => 'Slur($startId -> $endId)';
}

/// A string bend on a tab note, referenced by its id. [steps] is the bend
/// amount in whole steps: 1.0 = full (a whole tone), 0.5 = half, 1.5 = one
/// and a half, 0.25 = quarter. Rendered as an upward bend arrow with the
/// amount label; ignored by standard-notation rendering.
class Bend {
  /// Id of the bent note.
  final String noteId;

  /// Bend amount in whole steps (1.0 = full).
  final double steps;

  /// Creates a bend on [noteId] (default a full-step bend).
  const Bend(this.noteId, {this.steps = 1.0});

  @override
  bool operator ==(Object other) =>
      other is Bend && other.noteId == noteId && other.steps == steps;

  @override
  int get hashCode => Object.hash(noteId, steps);

  @override
  String toString() => 'Bend($noteId, ${steps}st)';
}

/// A vibrato on a tab note, referenced by its id: a horizontal wavy line
/// drawn above the fret. [wide] selects a larger-amplitude (whammy-bar/
/// exaggerated) wave. Rendered by the tab engine only; ignored by
/// standard-notation rendering.
class Vibrato {
  /// Id of the vibrato'd note.
  final String noteId;

  /// Whether to draw a wide (large-amplitude) wave rather than a normal one.
  final bool wide;

  /// Creates a vibrato on [noteId] (default a normal-width wave).
  const Vibrato(this.noteId, {this.wide = false});

  @override
  bool operator ==(Object other) =>
      other is Vibrato && other.noteId == noteId && other.wide == wide;

  @override
  int get hashCode => Object.hash(noteId, wide);

  @override
  String toString() => 'Vibrato($noteId${wide ? ', wide' : ''})';
}

/// A palm-mute span over a run of tab notes, referenced by the first and
/// last note's ids (a single note if [startId] == [endId]): a "P.M." label
/// followed by a dashed bracket line above the staff. Rendered by the tab
/// engine only; ignored by standard-notation rendering.
class PalmMute {
  /// Id of the first muted note.
  final String startId;

  /// Id of the last muted note.
  final String endId;

  /// Creates a palm-mute span from [startId] to [endId].
  const PalmMute(this.startId, this.endId);

  @override
  bool operator ==(Object other) =>
      other is PalmMute && other.startId == startId && other.endId == endId;

  @override
  int get hashCode => Object.hash(startId, endId);

  @override
  String toString() => 'PalmMute($startId -> $endId)';
}

/// A let-ring span over a run of tab notes, referenced by the first and last
/// note's ids (a single note if [startId] == [endId]): a "let ring" label
/// followed by a dashed bracket line above the staff. Rendered by the tab
/// engine only; ignored by standard-notation rendering.
class LetRing {
  /// Id of the first note that rings.
  final String startId;

  /// Id of the last note that rings.
  final String endId;

  /// Creates a let-ring span from [startId] to [endId].
  const LetRing(this.startId, this.endId);

  @override
  bool operator ==(Object other) =>
      other is LetRing && other.startId == startId && other.endId == endId;

  @override
  int get hashCode => Object.hash(startId, endId);

  @override
  String toString() => 'LetRing($startId -> $endId)';
}

/// How a tab note's fret digit is presented — for muted, softly-played and
/// harmonic notes (mutually exclusive per note).
enum TabNoteStyle {
  /// Dead (muted): each sounding string shows an "x" instead of a fret.
  dead,

  /// Ghost (played softly): the fret digit is drawn in parentheses, `(3)`.
  ghost,

  /// Natural harmonic: the fret digit is drawn in angle brackets, `<12>`.
  harmonic,

  /// Artificial harmonic: fret in angle brackets with an "A.H." label above.
  artificialHarmonic,

  /// Pinch (pick) harmonic: fret in angle brackets with a "P.H." label above.
  pinchHarmonic,
}

/// Whether a [TabNoteStyle] is one of the harmonic variants (natural,
/// artificial or pinch) — all drawn with the angle-bracketed fret.
bool isHarmonicStyle(TabNoteStyle style) =>
    style == TabNoteStyle.harmonic ||
    style == TabNoteStyle.artificialHarmonic ||
    style == TabNoteStyle.pinchHarmonic;

/// Marks a tab note with a [TabNoteStyle] — [TabNoteStyle.dead] (muted "x"),
/// [TabNoteStyle.ghost] (parenthesized) or [TabNoteStyle.harmonic]
/// (angle-bracketed) — referenced by the note's id. Rendered by the tab engine only;
/// ignored by standard-notation rendering. (Named to avoid clashing with the
/// rendering layer's drag-preview `GhostNote`.)
class TabNoteMark {
  /// Id of the marked note.
  final String noteId;

  /// Whether the note is dead or ghosted.
  final TabNoteStyle style;

  /// Marks [noteId] with [style].
  const TabNoteMark(this.noteId, this.style);

  @override
  bool operator ==(Object other) =>
      other is TabNoteMark && other.noteId == noteId && other.style == style;

  @override
  int get hashCode => Object.hash(noteId, style);

  @override
  String toString() => 'TabNoteMark($noteId, ${style.name})';
}

/// Pins a tab note/chord to explicit strings, overriding the tab engine's
/// default lowest-fret placement. [strings] gives the string index for each
/// pitch of the note **in the note's pitch order** (`0` = top tab line). An
/// entry whose fret would be negative or out of range is ignored (the engine
/// falls back to lowest-fret for that pitch). Rendered by the tab engine only.
class TabVoicing {
  /// Id of the note whose string placement is pinned.
  final String noteId;

  /// String index per pitch, in the note's pitch order (0 = top line).
  final List<int> strings;

  /// Pins [noteId]'s pitches to [strings].
  const TabVoicing(this.noteId, this.strings);

  @override
  bool operator ==(Object other) =>
      other is TabVoicing &&
      other.noteId == noteId &&
      _listEquals(other.strings, strings);

  @override
  int get hashCode => Object.hash(noteId, Object.hashAll(strings));

  @override
  String toString() => 'TabVoicing($noteId, $strings)';

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A chord fretboard diagram.
///
/// [frets] gives the fret for each string in **tuning order** — index 0 is the
/// top tab line (the highest-sounding string), matching `Tuning`. A value of
/// `0` is an open string, `-1` a muted (x) string, and `n > 0` the fretted
/// number. The diagram draws the lowest string on the left. [baseFret] is the
/// fret of the top row (1 draws the nut); [fretSpan] the number of rows shown.
/// Optional [name] labels it, [fingers] annotates finger numbers per string
/// (parallel to [frets]; a null entry draws none), and [barreFret] draws a
/// barre across all strings at that fret.
class ChordDiagram {
  /// Fret per string in tuning order (0 = open, -1 = muted, n = fretted).
  final List<int> frets;

  /// Chord name drawn above the grid, or null.
  final String? name;

  /// Finger numbers per string (parallel to [frets]; null entry = none).
  final List<int?>? fingers;

  /// Fret of the top row (1 = at the nut).
  final int baseFret;

  /// Number of fret rows drawn.
  final int fretSpan;

  /// Fret of a barre across all strings, or null.
  final int? barreFret;

  /// Creates a chord diagram.
  const ChordDiagram(
    this.frets, {
    this.name,
    this.fingers,
    this.baseFret = 1,
    this.fretSpan = 4,
    this.barreFret,
  });

  @override
  bool operator ==(Object other) =>
      other is ChordDiagram &&
      _intListEq(other.frets, frets) &&
      other.name == name &&
      _nIntListEq(other.fingers, fingers) &&
      other.baseFret == baseFret &&
      other.fretSpan == fretSpan &&
      other.barreFret == barreFret;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(frets),
      name,
      fingers == null ? null : Object.hashAll(fingers!),
      baseFret,
      fretSpan,
      barreFret);

  @override
  String toString() => 'ChordDiagram(${name ?? '?'}: $frets'
      '${baseFret == 1 ? '' : ' @$baseFret'})';

  static bool _intListEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _nIntListEq(List<int?>? a, List<int?>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A [ChordDiagram] placed above a note element (by [elementId]) on a staff —
/// the lead-sheet convention of a diagram over the note where the chord
/// changes. [scale] sizes the diagram down for the staff (default 0.6).
class PlacedChordDiagram {
  /// Id of the note the diagram sits above.
  final String elementId;

  /// The diagram to draw.
  final ChordDiagram diagram;

  /// Size factor applied to the standalone diagram (default 0.6).
  final double scale;

  /// Places [diagram] above the note with id [elementId].
  const PlacedChordDiagram(this.elementId, this.diagram, {this.scale = 0.6});

  @override
  bool operator ==(Object other) =>
      other is PlacedChordDiagram &&
      other.elementId == elementId &&
      other.diagram == diagram &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(elementId, diagram, scale);

  @override
  String toString() => 'PlacedChordDiagram($elementId, $diagram)';
}

/// A tapped tab note (left- or right-hand tapping), referenced by its id: a
/// "T" drawn above the fret. Rendered by the tab engine only; ignored by
/// standard-notation rendering.
class Tap {
  /// Id of the tapped note.
  final String noteId;

  /// Marks [noteId] as tapped.
  const Tap(this.noteId);

  @override
  bool operator ==(Object other) => other is Tap && other.noteId == noteId;

  @override
  int get hashCode => noteId.hashCode;

  @override
  String toString() => 'Tap($noteId)';
}

/// A tremolo-bar (whammy) dip/dive on a tab note, referenced by its id. This
/// is a *separate* system from string [Bend]s. [steps] is the pitch change in
/// whole tones at the low point (negative = dive down, positive = up); the bar
/// returns to pitch. Drawn as a V above the fret with the amount label.
/// Rendered by the tab engine only; ignored by standard-notation rendering.
class TremoloBar {
  /// Id of the note the bar acts on.
  final String noteId;

  /// Pitch change in whole tones at the low point (negative = dive down).
  final double steps;

  /// Creates a tremolo-bar dip on [noteId] (default a whole-step dive).
  const TremoloBar(this.noteId, {this.steps = -1.0});

  @override
  bool operator ==(Object other) =>
      other is TremoloBar && other.noteId == noteId && other.steps == steps;

  @override
  int get hashCode => Object.hash(noteId, steps);

  @override
  String toString() => 'TremoloBar($noteId, ${steps}st)';
}

/// A glissando/slide: a straight line drawn from one note to a later one,
/// referenced by their ids (like [Slur]). The start must precede the end in
/// reading order and both ids must exist, or layout throws an
/// [ArgumentError]. Model-only (no DSL shorthand).
class Glissando {
  /// Id of the note the line starts on.
  final String startId;

  /// Id of the note the line ends on.
  final String endId;

  /// Creates a glissando from [startId] to [endId].
  const Glissando(this.startId, this.endId);

  @override
  bool operator ==(Object other) =>
      other is Glissando && other.startId == startId && other.endId == endId;

  @override
  int get hashCode => Object.hash(startId, endId);

  @override
  String toString() => 'Glissando($startId -> $endId)';
}

/// A feathered (fanned) beam over a run of notes, referenced by the first
/// and last note's ids: the beam count fans from [beginBeams] at the start to
/// [endBeams] at the end (unequal → accelerando if growing, ritardando if
/// shrinking). The spanned notes are forced into one beam group regardless of
/// meter. Model-only. Both ids must exist and the start must precede the end,
/// or layout throws an [ArgumentError].
class FeatheredBeam {
  /// Id of the first note in the fan.
  final String startId;

  /// Id of the last note in the fan.
  final String endId;

  /// Number of beams at the start (≥ 1).
  final int beginBeams;

  /// Number of beams at the end (≥ 1).
  final int endBeams;

  /// Creates a feathered beam; defaults fan 1 → 4 (accelerando).
  const FeatheredBeam(
    this.startId,
    this.endId, {
    this.beginBeams = 1,
    this.endBeams = 4,
  })  : assert(beginBeams >= 1, 'beginBeams must be >= 1'),
        assert(endBeams >= 1, 'endBeams must be >= 1'),
        assert(beginBeams != endBeams, 'a feathered beam must change count');

  @override
  bool operator ==(Object other) =>
      other is FeatheredBeam &&
      other.startId == startId &&
      other.endId == endId &&
      other.beginBeams == beginBeams &&
      other.endBeams == endBeams;

  @override
  int get hashCode => Object.hash(startId, endId, beginBeams, endBeams);

  @override
  String toString() =>
      'FeatheredBeam($startId -> $endId, $beginBeams..$endBeams)';
}

/// Forces the beam over a run of notes to a fixed slant (and into one beam
/// group), referenced by the first and last note's ids. [slant] is the beam's
/// total vertical change from the first stem to the last, in staff spaces and
/// layout coordinates (y grows downward): **0 = horizontal**, positive slopes
/// down to the right, negative up to the right. Model-only. Both ids must
/// exist and the start must precede the end, or layout throws an
/// [ArgumentError].
class BeamSlant {
  /// Id of the first note under the beam.
  final String startId;

  /// Id of the last note under the beam.
  final String endId;

  /// Total vertical change (staff spaces, y-down); 0 = horizontal.
  final double slant;

  /// Creates a forced beam slant (default horizontal).
  const BeamSlant(this.startId, this.endId, {this.slant = 0});

  @override
  bool operator ==(Object other) =>
      other is BeamSlant &&
      other.startId == startId &&
      other.endId == endId &&
      other.slant == slant;

  @override
  int get hashCode => Object.hash(startId, endId, slant);

  @override
  String toString() => 'BeamSlant($startId -> $endId, slant $slant)';
}

/// A sustain-pedal span: "Ped." under the start note and a release star
/// under the end note, referenced by their ids. Same id/order rules as
/// [Slur]/[Glissando]. Model-only (no DSL shorthand).
class Pedal {
  /// Id of the note the pedal presses on.
  final String startId;

  /// Id of the note the pedal releases on.
  final String endId;

  /// Creates a pedal span from [startId] to [endId].
  const Pedal(this.startId, this.endId);

  @override
  bool operator ==(Object other) =>
      other is Pedal && other.startId == startId && other.endId == endId;

  @override
  int get hashCode => Object.hash(startId, endId);

  @override
  String toString() => 'Pedal($startId -> $endId)';
}

/// A rest.
class RestElement extends MusicElement {
  /// Creates a rest of [duration].
  const RestElement(NoteDuration duration, {super.id})
      : super(duration: duration);

  @override
  bool operator ==(Object other) =>
      other is RestElement && other.duration == duration && other.id == id;

  @override
  int get hashCode => Object.hash(duration, id);

  @override
  String toString() => 'RestElement($duration${id == null ? '' : ', id: $id'})';
}

/// Dynamic levels supported in v0.3.
enum DynamicLevel {
  /// Pianissimo.
  pp,

  /// Piano.
  p,

  /// Mezzo-piano.
  mp,

  /// Mezzo-forte.
  mf,

  /// Forte.
  f,

  /// Fortissimo.
  ff,
}

/// A dynamic marking attached to a note element (drawn centered below it,
/// under the staff).
class DynamicMarking {
  /// Id of the note element the marking belongs to.
  final String elementId;

  /// The dynamic level.
  final DynamicLevel level;

  /// Creates a dynamic marking.
  const DynamicMarking(this.elementId, this.level);

  @override
  bool operator ==(Object other) =>
      other is DynamicMarking &&
      other.elementId == elementId &&
      other.level == level;

  @override
  int get hashCode => Object.hash(elementId, level);

  @override
  String toString() => 'DynamicMarking($elementId: ${level.name})';
}

/// Direction of a [Hairpin].
enum HairpinType {
  /// Opening wedge (getting louder).
  crescendo,

  /// Closing wedge (getting softer).
  diminuendo,
}

/// A crescendo/diminuendo wedge between two note elements, drawn below
/// the staff on the dynamics line.
class Hairpin {
  /// Id of the note element the wedge starts on.
  final String startId;

  /// Id of the note element the wedge ends on.
  final String endId;

  /// Whether the wedge opens (crescendo) or closes (diminuendo).
  final HairpinType type;

  /// Creates a hairpin.
  const Hairpin(this.startId, this.endId, this.type);

  @override
  bool operator ==(Object other) =>
      other is Hairpin &&
      other.startId == startId &&
      other.endId == endId &&
      other.type == type;

  @override
  int get hashCode => Object.hash(startId, endId, type);

  @override
  String toString() => 'Hairpin($startId -> $endId, ${type.name})';
}

/// One lyric syllable attached to a note element, drawn below the staff.
class Lyric {
  /// Id of the note element the syllable sits under.
  final String elementId;

  /// The syllable text (without hyphen/extender markers).
  final String text;

  /// Whether a hyphen connects this syllable to the next one (the word
  /// continues on a later note).
  final bool hyphenToNext;

  /// Whether an extender (melisma) line follows this word-final syllable
  /// while subsequent notes carry no lyric of their own.
  final bool extender;

  /// Creates a lyric syllable.
  const Lyric(
    this.elementId,
    this.text, {
    this.hyphenToNext = false,
    this.extender = false,
  });

  @override
  bool operator ==(Object other) =>
      other is Lyric &&
      other.elementId == elementId &&
      other.text == text &&
      other.hyphenToNext == hyphenToNext &&
      other.extender == extender;

  @override
  int get hashCode => Object.hash(elementId, text, hyphenToNext, extender);

  @override
  String toString() => 'Lyric($elementId: "$text"'
      '${hyphenToNext ? ' -' : ''}${extender ? ' _' : ''})';
}

/// A text annotation anchored above the staff at a note element: chord
/// symbols, rehearsal marks, tempo text.
class Annotation {
  /// Id of the note element the text sits above.
  final String elementId;

  /// The text to display (e.g. `C`, `G7/B`, `Andante`).
  final String text;

  /// Creates an annotation.
  const Annotation(this.elementId, this.text);

  @override
  bool operator ==(Object other) =>
      other is Annotation && other.elementId == elementId && other.text == text;

  @override
  int get hashCode => Object.hash(elementId, text);

  @override
  String toString() => 'Annotation($elementId: "$text")';
}

/// An ottava bracket: the spanned elements are written an octave off
/// their sounding pitch, with a dashed bracket marking the range.
class Ottava {
  /// Id of the first spanned note element.
  final String startId;

  /// Id of the last spanned note element (inclusive).
  final String endId;

  /// False = 8va (bracket above; written an octave lower than sounding),
  /// true = 8vb (bracket below; written an octave higher).
  final bool down;

  /// Creates an ottava span.
  const Ottava(this.startId, this.endId, {this.down = false});

  @override
  bool operator ==(Object other) =>
      other is Ottava &&
      other.startId == startId &&
      other.endId == endId &&
      other.down == down;

  @override
  int get hashCode => Object.hash(startId, endId, down);

  @override
  String toString() => 'Ottava($startId -> $endId, ${down ? '8vb' : '8va'})';
}
