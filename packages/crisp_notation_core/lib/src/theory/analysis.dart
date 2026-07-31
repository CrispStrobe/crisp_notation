// Automatic harmonic analysis of a [Score].
//
// This ties the theory toolkit together into a single pass over a score:
// it slices the music into vertical sonorities, identifies each as a chord
// ([identifyChord]), spells it as a roman numeral in the detected key
// ([keyOf] + [romanNumeralFor]), classifies its harmonic function
// (tonic/subdominant/dominant), flags the non-chord tones, and spots the
// cadences. It is the engine behind an "analysis view" — colour a score by
// function, print roman numerals under it, mark the cadences.
//
// Segmentation is a sweep across all four voices: at every distinct onset the
// sounding pitches form a sonority, consecutive equal chords are merged, and a
// measure whose notes are purely melodic (an arpeggio, say) falls back to a
// single implied chord for the bar. Non-chord tones are found by removing one
// pitch and re-identifying (so a suspension or passing tone over a clean triad
// is recovered). Phrase/form detection is deliberately out of scope here.

import '../layout/multi_part.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import 'chord_analysis.dart';
import 'key.dart';
import 'key_finding.dart';
import 'pitch.dart';
import 'roman_numeral.dart';

/// The harmonic function a roman numeral plays, derived from its scale degree.
/// Secondary dominants/leading-tone chords count as [HarmonicFunction.dominant].
/// Returns null for a numeral with no clear degree.
HarmonicFunction? functionOf(RomanNumeral rn) {
  if (rn.applied != null) return HarmonicFunction.dominant;
  switch (rn.degree) {
    case 1:
    case 3:
    case 6:
      return HarmonicFunction.tonic;
    case 2:
    case 4:
      return HarmonicFunction.subdominant;
    case 5:
    case 7:
      return HarmonicFunction.dominant;
    default:
      return null;
  }
}

/// One analysed harmonic region: the sounding [pitches] and, when they form a
/// recognisable chord, its [chord]/[roman]/[function] and the [nonChordTones]
/// left over. A region with a null [chord] is a passage no chord could be read
/// from (a scale run, a bare interval).
class HarmonicSegment {
  /// Creates a harmonic segment.
  const HarmonicSegment({
    required this.measureIndex,
    required this.pitches,
    this.elementIds = const [],
    this.chord,
    this.roman,
    this.function,
    this.nonChordTones = const [],
  });

  /// Index into [Score.measures] where this region begins.
  final int measureIndex;

  /// The sounding sonority (chord tones and any non-chord tones).
  final List<Pitch> pitches;

  /// Ids of the [NoteElement]s that contribute to this segment (those that set
  /// an id). Lets a caller colour or highlight the notes belonging to a chord.
  final List<String> elementIds;

  /// The chord read from these [pitches], or null if none was recognisable.
  final ChordAnalysis? chord;

  /// The roman numeral of [chord] in the analysis key, or null.
  final RomanNumeral? roman;

  /// The harmonic function of [chord] (tonic/subdominant/dominant), or null.
  final HarmonicFunction? function;

  /// Sounding pitches that are not members of [chord].
  final List<Pitch> nonChordTones;

  /// Whether a chord was identified for this segment.
  bool get hasChord => chord != null;
}

/// The kind of cadence closing a phrase.
enum CadenceType {
  /// Dominant → tonic (V–I / vii°–I): a full stop.
  authentic,

  /// …ending on the dominant (–V): a question left open.
  half,

  /// Subdominant → tonic (IV–I): the "amen" ending.
  plagal,

  /// Dominant → submediant (V–vi): the surprise ending.
  deceptive,
}

/// A cadence: which [CadenceType] and where its resolving chord sits.
class Cadence {
  /// Creates a cadence of [type] resolving at [segmentIndex] / [measureIndex].
  const Cadence(this.type, this.segmentIndex, this.measureIndex);

  /// The kind of cadence.
  final CadenceType type;

  /// Index into [ScoreAnalysis.segments] of the resolving (second) chord.
  final int segmentIndex;

  /// Measure where the resolving chord sits.
  final int measureIndex;
}

/// The result of [analyze]: the detected [key], the harmonic [segments] in
/// order, and the [cadences] found between them.
class ScoreAnalysis {
  /// Creates a score analysis.
  const ScoreAnalysis({
    required this.key,
    required this.segments,
    required this.cadences,
  });

  /// The detected (or supplied) key.
  final Key key;

  /// The harmonic regions, in order.
  final List<HarmonicSegment> segments;

  /// The cadences found between segments.
  final List<Cadence> cadences;
}

/// Analyse a multi-part score's harmony, slicing ACROSS the parts.
///
/// 🔴 **This exists because [analyze] on a single [Score] silently mis-reads
/// multi-staff music.** Those readers collapse staves into a Score's four voice
/// slots, so a two-staff chorale arrives with soprano and alto interleaved in
/// voice 1 — measured on a real file as 6 notes in voice 1 against 4 in voice 2 —
/// and the slices then mix parts into sonorities of six or more pitches that
/// identify as things like `Gmaj13/E`. Every reading is plausible and wrong.
///
/// Here each part keeps its own voices and a slice is taken across all of them,
/// which is what a vertical sonority actually is.
ScoreAnalysis analyzeParts(
  MultiPartScore score, {
  Key? key,
  HarmonicWeighting weighting = HarmonicWeighting.perSlice,
  int maxWeightedTones = 4,
  double minWeightRatio = 0.25,
}) {
  final parts = score.parts;
  if (parts.isEmpty) {
    return ScoreAnalysis(
      key: key ?? Key.major(const Pitch(Step.c)),
      segments: const [],
      cadences: const [],
    );
  }
  if (parts.length == 1) {
    return analyze(
      parts.first,
      key: key,
      weighting: weighting,
      maxWeightedTones: maxWeightedTones,
      minWeightRatio: minWeightRatio,
    );
  }

  // Key finding sees every part, duration-weighted, exactly as the single-score
  // path does — a key read from the top line alone would miss the harmony.
  final allPitches = <Pitch>[];
  final weights = <double>[];
  for (final part in parts) {
    for (final m in part.measures) {
      for (final voice in _voicesOf(m)) {
        for (final e in voice) {
          if (e is NoteElement) {
            final w = e.duration.toFraction().toDouble();
            for (final p in e.pitches) {
              allPitches.add(p);
              weights.add(w);
            }
          }
        }
      }
    }
  }
  final k = key ??
      keyOf(allPitches, durations: weights) ??
      Key.major(const Pitch(Step.c));

  // Several parts ARE polyphony, so `auto` never needs to guess here.
  final mode = weighting == HarmonicWeighting.auto
      ? HarmonicWeighting.perSlice
      : weighting;

  final bars =
      parts.map((p) => p.measures.length).reduce((a, b) => a > b ? a : b);
  final raw = <HarmonicSegment>[];
  for (var mi = 0; mi < bars; mi++) {
    final voices = <List<MusicElement>>[];
    for (final part in parts) {
      if (mi < part.measures.length) {
        voices.addAll(_voicesOf(part.measures[mi]));
      }
    }
    if (voices.isEmpty) continue;

    if (mode == HarmonicWeighting.durationWeightedPerBar) {
      final merged = Measure([for (final v in voices) ...v]);
      final seg = _weightedBar(mi, merged, k, maxWeightedTones, minWeightRatio);
      if (seg != null) raw.add(seg);
      continue;
    }
    for (final slice in _slicesOfVoices(voices)) {
      raw.add(_segmentFor(mi, slice, k));
    }
  }

  final segments = _merge(raw);
  return ScoreAnalysis(
    key: k,
    segments: segments,
    cadences: _cadences(segments),
  );
}

/// How [analyze] decides which pitches a chord reading is built from.
enum HarmonicWeighting {
  /// Identify every onset-to-onset sonority independently, then merge equal
  /// neighbours. Faithful to the vertical detail of the music, and the default
  /// because it is what every existing caller already gets.
  perSlice,

  /// Read ONE chord per bar from the bar's duration-weighted pitch content.
  ///
  /// 🔴 **Measured to matter far more than the matcher does.** On real annotated
  /// material, holding the chord identifier fixed and changing only which notes
  /// it is given moved maj/min agreement over a 32-point range, and
  /// duration-weighting was the top of it (see `BB-H9` in the app's PLAN.md).
  /// The intuition is simple: a passing note that sounds for a sixteenth should
  /// not outvote a chord tone held for a half, and a per-slice reading gives them
  /// equal say.
  ///
  /// This is the mode a LEAD SHEET wants — one symbol per bar — so it is the
  /// primitive for deriving chord charts from a score. It deliberately discards
  /// mid-bar harmonic detail; use [perSlice] when that detail is the point.
  durationWeightedPerBar,

  /// Measure the music's HARMONIC RHYTHM and pick the other two accordingly.
  ///
  /// 🔴 **Neither fixed mode is right for everything, and testing Bach proved
  /// it.** On folk song — one chord per bar — the per-bar reading is worth about
  /// thirty points of agreement, because a passing sixteenth should not outvote a
  /// chord tone held for a half. On a chorale, which changes harmony every BEAT,
  /// the same reading folds a bar's worth of harmony into one chord and invents
  /// suspensions: 60 Bach chorales came back full of `Dsus4`, `F#sus4` and
  /// `Cm11/D`, none of which Bach wrote.
  ///
  /// So the mode is chosen from the music's TEXTURE: music with more than one
  /// sounding voice has a real vertical sonority to read, and gets [perSlice];
  /// a single line has none — the harmony is only implied — and gets the per-bar
  /// pooling. See [_isPolyphonic].
  auto,
}

/// Analyse [score]'s harmony. Pass [key] to fix the key (otherwise it's inferred
/// from the notes, duration-weighted, via Krumhansl–Schmuckler).
///
/// [weighting] chooses how the pitches behind each reading are selected; see
/// [HarmonicWeighting]. The default preserves existing behaviour exactly.
ScoreAnalysis analyze(
  Score score, {
  Key? key,
  HarmonicWeighting weighting = HarmonicWeighting.perSlice,
  int maxWeightedTones = 4,
  double minWeightRatio = 0.25,
}) {
  // Gather every pitch (duration-weighted) for key finding.
  final allPitches = <Pitch>[];
  final weights = <double>[];
  for (final m in score.measures) {
    for (final voice in _voicesOf(m)) {
      for (final e in voice) {
        if (e is NoteElement) {
          final w = e.duration.toFraction().toDouble();
          for (final p in e.pitches) {
            allPitches.add(p);
            weights.add(w);
          }
        }
      }
    }
  }
  final k = key ??
      keyOf(allPitches, durations: weights) ??
      Key.major(const Pitch(Step.c));

  // `auto` resolves to one of the real modes before anything else happens.
  var mode = weighting;
  if (mode == HarmonicWeighting.auto) {
    mode = _isPolyphonic(score)
        ? HarmonicWeighting.perSlice
        : HarmonicWeighting.durationWeightedPerBar;
  }

  // Sweep each measure into sonorities → segments.
  final raw = <HarmonicSegment>[];
  for (var mi = 0; mi < score.measures.length; mi++) {
    if (mode == HarmonicWeighting.durationWeightedPerBar) {
      final seg = _weightedBar(
        mi,
        score.measures[mi],
        k,
        maxWeightedTones,
        minWeightRatio,
      );
      if (seg != null) raw.add(seg);
      continue;
    }
    final slices = _slicesOf(score.measures[mi]);
    final segs = <HarmonicSegment>[];
    var anyChord = false;
    for (final s in slices) {
      final seg = _segmentFor(mi, s, k);
      if (seg.chord != null) anyChord = true;
      segs.add(seg);
    }
    // Melodic bar (an arpeggio, a broken chord): read one implied chord for it.
    if (!anyChord && slices.isNotEmpty) {
      final distinct = _dedupe(slices.expand((s) => s.pitches).toList());
      final ids = [for (final s in slices) ...s.ids];
      final implied = _identify(distinct);
      if (implied != null) {
        final rn = romanNumeralFor(implied.chord, k);
        segs
          ..clear()
          ..add(
            HarmonicSegment(
              measureIndex: mi,
              pitches: distinct,
              elementIds: ids,
              chord: implied.chord,
              roman: rn,
              function: functionOf(rn),
              nonChordTones: implied.ncts,
            ),
          );
      }
    }
    raw.addAll(segs);
  }

  final segments = _merge(raw);
  return ScoreAnalysis(
    key: k,
    segments: segments,
    cadences: _cadences(segments),
  );
}

/// True when more than one voice sounds — the signal that a vertical sonority
/// exists to be read.
///
/// ⚠️ **This decides the MODE correctly and cannot rescue a badly-read score.**
/// [analyze] takes a single [Score], so a multi-staff work read through the
/// single-score readers arrives with its staves collapsed into voices — a
/// two-staff chorale comes back with soprano and alto interleaved in voice 1 —
/// and the slices then mix parts into sonorities of six or more pitches, which
/// identify as things like `Gmaj13/E`. Choosing [perSlice] for such a score is
/// right and still yields nonsense, because the input was already wrong. Reading
/// multi-part music properly needs a `MultiPartScore` entry point, which does not
/// exist yet.
///
/// ❌ **A chord-rate heuristic was tried first and FAILED; do not retry it.**
/// Counting successfully-named segments per bar measures how often chord
/// IDENTIFICATION SUCCEEDS, not how often the harmony changes — and Bach scores
/// *low* on it precisely because his suspensions defeat the identifier. Measured:
/// Bach chorales 0.63 named-chords/bar against folk song 0.11, so both fell on
/// the same side of any threshold and the chorales would have been read per bar,
/// which is the error the whole mode exists to prevent.
///
/// Texture separates them cleanly and needs no identification at all: the
/// chorales use 2+ voices, the folk songs 1. And it is the musically right
/// question — with several voices the slice IS the chord, with one line there is
/// nothing vertical to read and the bar must be pooled.
bool _isPolyphonic(Score score) {
  for (final m in score.measures) {
    var voices = 0;
    for (final v in [m.elements, m.voice2, m.voice3, m.voice4]) {
      if (v.whereType<NoteElement>().isNotEmpty) voices++;
    }
    if (voices > 1) return true;
    // A single voice can still be homophonic if its "notes" are chords.
    for (final e in m.elements) {
      if (e is NoteElement && e.pitches.length > 1) return true;
    }
  }
  return false;
}

/// One chord for [m], chosen from its duration-weighted pitch content.
///
/// Keeps the longest-sounding pitch classes — those sounding at least
/// [minWeightRatio] of the strongest tone's duration, capped at [maxTones] — and
/// identifies those. If that names nothing it widens, first to every significant
/// tone and then to the whole bar, rather than giving up.
HarmonicSegment? _weightedBar(
  int mi,
  Measure m,
  Key k,
  int maxTones,
  double minWeightRatio,
) {
  final weight = <int, double>{}; // pitch class → sounding time
  final byPc = <int, Pitch>{}; // a representative spelling per class
  final ids = <String>[];
  for (final voice in _voicesOf(m)) {
    for (final e in voice) {
      if (e is! NoteElement) continue;
      final w = e.duration.toFraction().toDouble();
      if (e.id != null) ids.add(e.id!);
      for (final p in e.pitches) {
        final pc = ((p.step.semitonesFromC + p.alter) % 12 + 12) % 12;
        weight[pc] = (weight[pc] ?? 0) + w;
        byPc.putIfAbsent(pc, () => p);
      }
    }
  }
  if (weight.isEmpty) return null;

  final ranked = weight.entries.toList()
    ..sort((a, b) {
      final byWeight = b.value.compareTo(a.value);
      // Deterministic: equal weights resolve by pitch class, never by map order.
      return byWeight != 0 ? byWeight : a.key.compareTo(b.key);
    });

  // 🔴 A THRESHOLD RELATIVE TO THE STRONGEST TONE, not a fixed top-N. Taking the
  // N heaviest pitches sounds equivalent and is not: when a bar holds a triad and
  // decorates it with three sixteenths, top-4 admits one arbitrary passing note,
  // and the non-chord-tone recovery below can then discard a REAL chord tone to
  // make the intruder fit. A held C-E-G with a C# grace note read as `C#dim`,
  // having dropped the root. Requiring a tone to sound for a meaningful fraction
  // of the strongest one excludes decoration by construction.
  final maxWeight = ranked.first.value;
  final significant = [
    for (final e in ranked)
      if (e.value >= maxWeight * minWeightRatio) e,
  ];

  List<Pitch> take(List<MapEntry<int, double>> es, int n) =>
      [for (final e in es.take(n)) byPc[e.key]!];

  var picked = take(significant, maxTones);
  var got = _identify(picked);
  // Widen only if the confident set names nothing: first every significant tone,
  // then everything in the bar.
  if (got == null && significant.length > maxTones) {
    picked = take(significant, significant.length);
    got = _identify(picked);
  }
  if (got == null && ranked.length > significant.length) {
    picked = take(ranked, ranked.length);
    got = _identify(picked);
  }
  if (got == null) {
    return HarmonicSegment(
      measureIndex: mi,
      pitches: picked,
      elementIds: ids,
      chord: null,
      roman: null,
      function: null,
      nonChordTones: const [],
    );
  }
  final rn = romanNumeralFor(got.chord, k);
  return HarmonicSegment(
    measureIndex: mi,
    pitches: picked,
    elementIds: ids,
    chord: got.chord,
    roman: rn,
    function: functionOf(rn),
    nonChordTones: got.ncts,
  );
}

// ---- segmentation -----------------------------------------------------------

List<List<MusicElement>> _voicesOf(Measure m) => [
      m.elements,
      m.voice2,
      m.voice3,
      m.voice4,
    ];

class _Event {
  _Event(this.start, this.end, this.pitches, this.id);
  final double start;
  final double end;
  final List<Pitch> pitches;
  final String? id;
}

/// One onset-to-onset sonority: the sounding pitches and the ids of the note
/// elements that produced them.
class _Slice {
  _Slice(this.pitches, this.ids);
  final List<Pitch> pitches;
  final List<String> ids;
}

/// The vertical sonorities of one measure (in whole-note time), across voices.
List<_Slice> _slicesOf(Measure m) => _slicesOfVoices(_voicesOf(m));

/// Onset-to-onset sonorities across ANY set of concurrent voices.
///
/// Split out from [_slicesOf] so a multi-part score can be sliced across its
/// PARTS as well as its voices. Reading each part separately, or flattening
/// several staves into one Score's voices, both destroy the vertical sonority
/// that harmonic analysis is about.
List<_Slice> _slicesOfVoices(List<List<MusicElement>> voices) {
  final events = <_Event>[];
  var maxEnd = 0.0;
  for (final voice in voices) {
    var t = 0.0;
    for (final e in voice) {
      final len = e.duration.toFraction().toDouble();
      if (e is NoteElement) events.add(_Event(t, t + len, e.pitches, e.id));
      t += len;
    }
    if (t > maxEnd) maxEnd = t;
  }
  if (events.isEmpty) return const [];
  const eps = 1e-6;
  final bounds = <double>{for (final e in events) e.start, maxEnd}.toList()
    ..sort();
  final slices = <_Slice>[];
  for (var i = 0; i < bounds.length - 1; i++) {
    final b = bounds[i];
    final pitches = <Pitch>[];
    final ids = <String>[];
    for (final e in events) {
      if (e.start <= b + eps && e.end > b + eps) {
        pitches.addAll(e.pitches);
        if (e.id != null) ids.add(e.id!);
      }
    }
    if (pitches.isNotEmpty) slices.add(_Slice(pitches, ids));
  }
  return slices;
}

HarmonicSegment _segmentFor(int mi, _Slice slice, Key key) {
  final pitches = slice.pitches;
  final res = _identify(pitches);
  if (res == null) {
    return HarmonicSegment(
      measureIndex: mi,
      pitches: pitches,
      elementIds: slice.ids,
    );
  }
  final rn = romanNumeralFor(res.chord, key);
  return HarmonicSegment(
    measureIndex: mi,
    elementIds: slice.ids,
    pitches: pitches,
    chord: res.chord,
    roman: rn,
    function: functionOf(rn),
    nonChordTones: res.ncts,
  );
}

class _ChordResult {
  _ChordResult(this.chord, this.ncts);
  final ChordAnalysis chord;
  final List<Pitch> ncts;
}

/// Identify a chord in [pitches], recovering one non-chord tone if a direct
/// read fails (a suspension/passing tone over an otherwise clean chord).
_ChordResult? _identify(List<Pitch> pitches) {
  final direct = identifyChord(pitches);
  if (direct != null) return _ChordResult(direct, _nctsOf(pitches, direct));
  final distinct = _dedupe(pitches);
  if (distinct.length >= 4) {
    for (var i = 0; i < distinct.length; i++) {
      final sub = [
        for (var j = 0; j < distinct.length; j++)
          if (j != i) distinct[j],
      ];
      final c = identifyChord(sub);
      if (c != null) return _ChordResult(c, _nctsOf(pitches, c));
    }
  }
  return null;
}

List<Pitch> _nctsOf(List<Pitch> pitches, ChordAnalysis chord) {
  final rootPc = chord.root.midiNumber % 12;
  final chordPcs = {for (final i in chord.type.intervals) (rootPc + i) % 12};
  final out = <Pitch>[];
  final seen = <int>{};
  for (final p in pitches) {
    final pc = p.midiNumber % 12;
    if (!chordPcs.contains(pc) && seen.add(pc)) out.add(p);
  }
  return out;
}

List<Pitch> _dedupe(List<Pitch> pitches) {
  final seen = <int>{};
  final out = <Pitch>[];
  for (final p in pitches) {
    if (seen.add(p.midiNumber % 12)) out.add(p);
  }
  return out;
}

// ---- merging + cadences -----------------------------------------------------

bool _sameChord(ChordAnalysis? a, ChordAnalysis? b) =>
    a != null &&
    b != null &&
    a.root.midiNumber % 12 == b.root.midiNumber % 12 &&
    a.type == b.type;

List<HarmonicSegment> _merge(List<HarmonicSegment> raw) {
  final out = <HarmonicSegment>[];
  for (final seg in raw) {
    if (out.isNotEmpty &&
        ((seg.chord == null && out.last.chord == null) ||
            _sameChord(seg.chord, out.last.chord))) {
      final prev = out.removeLast();
      out.add(
        HarmonicSegment(
          measureIndex: prev.measureIndex,
          pitches: [...prev.pitches, ...seg.pitches],
          elementIds: [...prev.elementIds, ...seg.elementIds],
          chord: prev.chord,
          roman: prev.roman,
          function: prev.function,
          nonChordTones: [...prev.nonChordTones, ...seg.nonChordTones],
        ),
      );
    } else {
      out.add(seg);
    }
  }
  return out;
}

List<Cadence> _cadences(List<HarmonicSegment> segments) {
  final out = <Cadence>[];
  HarmonicSegment? prev;
  var prevIndex = -1;
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    if (!s.hasChord) continue;
    if (prev != null) {
      final pf = prev.function;
      final degree = s.roman?.degree;
      if (pf == HarmonicFunction.dominant && degree == 1) {
        out.add(Cadence(CadenceType.authentic, i, s.measureIndex));
      } else if (pf == HarmonicFunction.dominant && degree == 6) {
        out.add(Cadence(CadenceType.deceptive, i, s.measureIndex));
      } else if (pf == HarmonicFunction.subdominant && degree == 1) {
        out.add(Cadence(CadenceType.plagal, i, s.measureIndex));
      }
    }
    prev = s;
    prevIndex = i;
  }
  // A piece that ends on the dominant closes with a half cadence.
  if (prev != null && prev.function == HarmonicFunction.dominant) {
    final alreadyAuthentic = out.any(
      (c) => c.segmentIndex == prevIndex && c.type != CadenceType.half,
    );
    if (!alreadyAuthentic) {
      out.add(Cadence(CadenceType.half, prevIndex, prev.measureIndex));
    }
  }
  return out;
}

// ---- form detection ---------------------------------------------------------

/// One section of a piece's form: a run of measures sharing melodic material,
/// with a repeat-revealing [label] (`A`, `B`, `A` again when the tune returns).
class FormSection {
  /// Creates a form section spanning [startMeasure]..[endMeasure] (inclusive).
  const FormSection(this.startMeasure, this.endMeasure, this.label);

  /// First measure index of the section.
  final int startMeasure;

  /// Last measure index (inclusive).
  final int endMeasure;

  /// The section letter — same letter ⇒ the same melodic material.
  final String label;
}

/// A transpose-invariant fingerprint of a measure's top-voice melody + rhythm,
/// so a phrase that returns (at any pitch) matches its earlier appearance.
String _measureFingerprint(Measure m) {
  final tokens = <String>[];
  int? first;
  for (final e in m.elements) {
    final f = e.duration.toFraction();
    if (e is NoteElement && e.pitches.isNotEmpty) {
      final top =
          e.pitches.map((p) => p.midiNumber).reduce((a, b) => a > b ? a : b);
      first ??= top;
      tokens.add('${top - first}:${f.numerator}/${f.denominator}');
    } else {
      tokens.add('R:${f.numerator}/${f.denominator}');
    }
  }
  return tokens.join(',');
}

/// Detect a piece's form by melodic repetition. Each measure is fingerprinted
/// (transpose-invariant); measures are then grouped into **phrases** — the
/// algorithm tries phrase lengths and picks the one that reveals the most
/// repetition, so a recurring 4-bar phrase reads as one section, not four. Each
/// phrase gets a letter (`A`, `B`, … in first-appearance order), and consecutive
/// equal phrases are merged. Same letter ⇒ the same material came back. An empty
/// score yields no sections.
List<FormSection> detectForm(Score score) {
  final n = score.measures.length;
  if (n == 0) return const [];
  final fps = [for (final m in score.measures) _measureFingerprint(m)];

  // Pick the phrase length L that best exposes repetition (an even division of
  // the piece with the most repeated phrases); fall back to bar-level (L=1).
  var bestL = 1;
  var bestScore = -1.0;
  for (var L = 1; L <= (n ~/ 2).clamp(1, 8); L++) {
    if (n % L != 0) continue;
    final groups = [
      for (var i = 0; i < n; i += L) fps.sublist(i, i + L).join('|'),
    ];
    final distinct = groups.toSet().length;
    if (distinct >= groups.length) continue; // no repetition at this length
    // Reward repetition; nudge toward longer phrases to prefer A-B-A over
    // A-B-C-D-A-B when both repeat.
    final score = (groups.length - distinct) / groups.length + L * 0.01;
    if (score > bestScore) {
      bestScore = score;
      bestL = L;
    }
  }

  final groups = [
    for (var i = 0; i < n; i += bestL) fps.sublist(i, i + bestL).join('|'),
  ];
  final letters = <String, String>{};
  var next = 0;
  final out = <FormSection>[];
  for (var g = 0; g < groups.length; g++) {
    final letter = letters.putIfAbsent(groups[g], () {
      final l = String.fromCharCode(65 + (next < 26 ? next : 25));
      next++;
      return l;
    });
    final start = g * bestL;
    final end = start + bestL - 1;
    if (out.isNotEmpty && out.last.label == letter) {
      out[out.length - 1] = FormSection(out.last.startMeasure, end, letter);
    } else {
      out.add(FormSection(start, end, letter));
    }
  }
  return out;
}
