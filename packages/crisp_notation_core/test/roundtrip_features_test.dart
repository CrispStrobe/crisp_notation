// Systematic feature round-trip regression tests across five interchange
// codecs (MusicXML, MEI, kern, ABC, MuseScore). Complements
// roundtrip_property_test.dart,
// which checks NOTE CONTENT over 150 random scores: this file pins the specific
// musical MARKINGS a hand-authored score carries — meter/clef/key changes,
// articulations, ornaments, grace notes, ties, slurs, dynamics, tuplets, chords,
// dotted values, repeats, voltas, navigation, second voices, lyrics, tremolo —
// through each write→read cycle.
//
// The support matrix below was established empirically (see the `droppedBy` set
// on each feature). Each SUPPORTED cell is a regression lock. Each DROPPED cell
// documents a known codec/format limitation with an explicit expectation, so if
// support is ever added the test fails loudly — the message tells you to remove
// that codec from `droppedBy`. Gaps today:
//   • MuseScore  — grace, dynamics, repeats/voltas, navigation, lyrics, tremolo
//     (the `.mscx` codec is a documented note-content subset — the format does
//     support all of these, so these are extendable like MEI/kern were)
//   • kern / ABC — tremolo (not part of standard kern or ABC; carried only in
//     MusicXML via <tremolo> and MEI via @stem.mod)
// MusicXML and MEI carry every marking here; ABC carries all but tremolo.
// (kern voltas/navigation ride a `*>N` section label / `!!nav:` comment — a
// crisp_notation round-trip convention, not interoperable Humdrum endings.)
//
// Two recently-fixed ABC drops are locked here as regressions: the mid-score
// clef change and grace notes on an id-less note. The focused versions live in
// abc_followups_test.dart; the GPIF meter round-trip (a fifth codec, not in the
// matrix above) is in gpif_test.dart.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// One musical marking, a score that carries it, and a predicate that reports
/// whether it survived a round-trip.
class _Feature {
  _Feature(this.name, this.build, this.survived, {this.droppedBy = const {}});

  final String name;
  final Score Function() build;
  final bool Function(Score) survived;

  /// Codecs that legitimately do NOT carry this marking today (documented
  /// limitations, not failures). Anything not listed here MUST round-trip.
  final Set<String> droppedBy;
}

NoteElement _n(
  Step s, {
  int octave = 4,
  String? id,
  DurationBase d = DurationBase.quarter,
  int dots = 0,
  List<Pitch>? chord,
  Set<Articulation> art = const {},
  Ornament? ornament,
  List<Pitch> grace = const [],
  bool tie = false,
  int? tremolo,
}) =>
    NoteElement(
      pitches: chord ?? [Pitch(s, octave: octave)],
      duration: NoteDuration(d, dots: dots),
      id: id,
      articulations: art,
      ornament: ornament,
      graceNotes: grace,
      tieToNext: tie,
      tremolo: tremolo,
    );

List<NoteElement> _notes(Score s) =>
    s.measures.expand((m) => m.elements.whereType<NoteElement>()).toList();

const _whole = DurationBase.whole;
const _half = DurationBase.half;
const _eighth = DurationBase.eighth;

/// A single-marking score for an articulation.
Score _artScore(Articulation a) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          _n(Step.c, d: _whole, art: {a})
        ]),
      ],
    );

/// A single-marking score for an ornament.
Score _ornScore(Ornament o) => Score(
      clef: Clef.treble,
      measures: [
        Measure([_n(Step.c, d: _whole, ornament: o)]),
      ],
    );

final _features = <_Feature>[
  // ---- Structural changes mid-score (the class of bug the sweep found) -------
  _Feature(
    'mid-score meter change',
    () => Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([_n(Step.g, d: _whole)]),
          Measure([_n(Step.a, d: _half, dots: 1)],
              timeChange: const TimeSignature(3, 4)),
          Measure([_n(Step.b, d: _half, dots: 1)]),
        ]),
    (b) =>
        b.measures[1].timeChange == const TimeSignature(3, 4) &&
        b.measures[2].timeChange == null,
  ),
  _Feature(
    'mid-score clef change',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.g, d: _whole)]),
      Measure([_n(Step.c, octave: 3, d: _whole)], clefChange: Clef.bass),
      Measure([_n(Step.d, octave: 3, d: _whole)]),
    ]),
    (b) =>
        b.measures[1].clefChange == Clef.bass &&
        b.measures[2].clefChange == null,
  ),
  _Feature(
    'mid-score key change',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.g, d: _whole)]),
      Measure([_n(Step.a, d: _whole)], keyChange: const KeySignature(2)),
      Measure([_n(Step.b, d: _whole)]),
    ]),
    (b) =>
        b.measures[1].keyChange == const KeySignature(2) &&
        b.measures[2].keyChange == null,
  ),
  _Feature(
    'non-treble initial clef',
    () => Score(clef: Clef.bass, measures: [
      Measure([_n(Step.c, octave: 3, d: _whole)]),
    ]),
    (b) => b.clef == Clef.bass,
  ),

  // ---- Articulations (all four codecs carry these) ---------------------------
  for (final a in const [
    Articulation.staccato,
    Articulation.accent,
    Articulation.tenuto,
    Articulation.marcato,
    Articulation.fermata,
  ])
    _Feature(
      'articulation ${a.name}',
      () => _artScore(a),
      (b) => _notes(b).first.articulations.contains(a),
    ),

  // ---- Ornaments (all four codecs carry these) -------------------------------
  for (final o in const [Ornament.trill, Ornament.mordent, Ornament.turn])
    _Feature(
      'ornament ${o.name}',
      () => _ornScore(o),
      (b) => _notes(b).first.ornament == o,
    ),

  // ---- Note-level markings ---------------------------------------------------
  _Feature(
    'grace notes (id-less note)',
    () => Score(clef: Clef.treble, measures: [
      Measure([
        _n(Step.g, grace: [Pitch(Step.f, octave: 4)]),
        _n(Step.a, d: _half, dots: 1),
      ]),
    ]),
    (b) => _notes(b).first.graceNotes.length == 1,
  ),
  _Feature(
    'tie to next',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.c, d: _whole, tie: true)]),
      Measure([_n(Step.c, d: _whole)]),
    ]),
    (b) => _notes(b).first.tieToNext,
  ),
  _Feature(
    'slur',
    () => Score(clef: Clef.treble, slurs: [
      const Slur('a', 'b')
    ], measures: [
      Measure([_n(Step.c, id: 'a', d: _half), _n(Step.d, id: 'b', d: _half)]),
    ]),
    (b) => b.slurs.length == 1,
  ),
  _Feature(
    'dynamic marking',
    () => Score(
      clef: Clef.treble,
      dynamics: [const DynamicMarking('a', DynamicLevel.ff)],
      measures: [
        Measure([_n(Step.c, id: 'a', d: _whole)]),
      ],
    ),
    (b) => b.dynamics.any((d) => d.level == DynamicLevel.ff),
  ),
  _Feature(
    'triplet',
    () => Score(clef: Clef.treble, measures: [
      Measure([
        _n(Step.c, d: _eighth),
        _n(Step.d, d: _eighth),
        _n(Step.e, d: _eighth),
        _n(Step.f),
        _n(Step.g),
      ], tuplets: [
        const TupletSpan(0, 2, actual: 3, normal: 2)
      ]),
    ]),
    (b) => b.measures.first.tuplets.any((t) => t.actual == 3 && t.normal == 2),
  ),
  _Feature(
    'chord (three pitches)',
    () => Score(clef: Clef.treble, measures: [
      Measure([
        _n(Step.c, d: _whole, chord: [
          Pitch(Step.c, octave: 4),
          Pitch(Step.e, octave: 4),
          Pitch(Step.g, octave: 4),
        ]),
      ]),
    ]),
    (b) => _notes(b).first.pitches.length == 3,
  ),
  _Feature(
    'double-dotted value',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.c, d: _half, dots: 2), _n(Step.d, d: _eighth)]),
    ]),
    (b) => _notes(b).first.duration.dots == 2,
  ),
  _Feature(
    'tremolo',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.c, d: _whole, tremolo: 3)]),
    ]),
    (b) => _notes(b).first.tremolo == 3,
    // Tremolo is not part of standard kern or ABC (this library emits it in
    // MusicXML via <tremolo> and MEI via @stem.mod only).
    droppedBy: const {'kern', 'ABC'},
  ),

  // ---- Structural / layout markings ------------------------------------------
  _Feature(
    'start/end repeat',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.c, d: _whole)], startRepeat: true),
      Measure([_n(Step.d, d: _whole)], endRepeat: true),
    ]),
    (b) => b.measures[0].startRepeat && b.measures[1].endRepeat,
  ),
  _Feature(
    'volta (1st ending)',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.c, d: _whole)], volta: 1, endRepeat: true),
      Measure([_n(Step.d, d: _whole)]),
    ]),
    (b) => b.measures[0].volta == 1,
    droppedBy: const {'MuseScore'},
  ),
  _Feature(
    'navigation (D.C.)',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.c, d: _whole)]),
      Measure([_n(Step.d, d: _whole)], navigation: NavigationMark.daCapo),
    ]),
    (b) => b.measures[1].navigation == NavigationMark.daCapo,
  ),
  _Feature(
    'second voice',
    () => Score(clef: Clef.treble, measures: [
      Measure([_n(Step.e, d: _whole)], voice2: [_n(Step.c, d: _whole)]),
    ]),
    (b) => b.measures.first.voice2.isNotEmpty,
  ),
  _Feature(
    'lyrics',
    () => Score(
      clef: Clef.treble,
      lyrics: const [Lyric('a', 'la'), Lyric('b', 'le')],
      measures: [
        Measure([_n(Step.c, id: 'a', d: _half), _n(Step.d, id: 'b', d: _half)]),
      ],
    ),
    (b) => b.lyrics.length == 2,
  ),
];

final _codecs = <String, Score Function(Score)>{
  'MusicXML': (s) => scoreFromMusicXml(scoreToMusicXml(s)),
  'MEI': (s) => scoreFromMei(scoreToMei(s)),
  'kern': (s) => scoreFromKern(scoreToKern(s)),
  'ABC': (s) => scoreFromAbc(scoreToAbc(s)),
  'MuseScore': (s) => scoreFromMscx(scoreToMscx(s)),
};

void main() {
  for (final feat in _features) {
    group('round-trip: ${feat.name}', () {
      _codecs.forEach((codec, roundTrip) {
        final isGap = feat.droppedBy.contains(codec);
        test(
            '$codec ${isGap ? 'does not carry it (known gap)' : 'preserves it'}',
            () {
          final back = roundTrip(feat.build());
          if (isGap) {
            expect(
              feat.survived(back),
              isFalse,
              reason: '$codec is documented as NOT carrying "${feat.name}". '
                  'If it now round-trips, remove "$codec" from this feature\'s '
                  'droppedBy set — the support has improved.',
            );
          } else {
            expect(
              feat.survived(back),
              isTrue,
              reason: '$codec must preserve "${feat.name}" across write→read.',
            );
          }
        });
      });
    });
  }
}
