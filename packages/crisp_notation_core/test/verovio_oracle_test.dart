@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Verovio onset oracle: the first staff's note onsets as crisp_notation
/// reads them, against Verovio's timing map of the same file.
///
/// Opt-in: `CRISP_NOTATION_CORPUS` names the corpus, and
/// `$CRISP_NOTATION_CORPUS/verovio-oracle/oracle.json` holds, per file,
/// `[qstamp, midi pitch, staff]` (quarter notes, repeats not expanded,
/// grace notes left out) — built by `tool/verovio_oracle/make_oracle.py`.
///
/// A file agrees when 98% of Verovio's staff-1 notes find a crisp_notation
/// note within 1/64 quarter at the same pitch, allowing one constant pitch
/// offset per file (a transposing part written at sounding pitch). Set
/// `CRISP_ORACLE_REPORT` to a path to get every disagreeing file listed.
///
/// Where the two differ with nothing misread, the comparison allows for it:
/// bars start together across the system ([_systemShifts]); a note Verovio
/// lists on staff 1 may be found on the part's other staves (cross-staff), at
/// an unprinted note's spacer ([_spacerOnsets]), or, unpitched (pitch 0), at
/// any pitch. Files Verovio itself misreads are set aside, each with its
/// reason ([_verovioMisreads]), and counted apart from those that agree.
void main() {
  final root = Platform.environment['CRISP_NOTATION_CORPUS'];
  final oracleFile =
      root == null ? null : File('$root/verovio-oracle/oracle.json');
  final skip = root == null || !Directory(root).existsSync()
      ? 'set CRISP_NOTATION_CORPUS to the corpus directory'
      : (!oracleFile!.existsSync()
          ? 'no verovio-oracle/oracle.json in the corpus'
          : null);

  test('note onsets agree with Verovio', () {
    final oracle =
        jsonDecode(oracleFile!.readAsStringSync()) as Map<String, dynamic>;
    final paths = oracle.keys.toList()..sort();
    var agree = 0;
    var excused = 0;
    final disagreements = <String>[];
    for (final path in paths) {
      final expected = [
        for (final e in (oracle[path] as List).cast<List<dynamic>>())
          if ((e[2] as num).toInt() == 1)
            _Event((e[0] as num).toDouble(), (e[1] as num).toInt()),
      ];
      if (expected.isEmpty) {
        agree++;
        continue;
      }
      final List<_Event> actual;
      final List<_Event> otherStaves;
      final List<double> spacers;
      try {
        final file = File('$root/$path');
        final xml = path.endsWith('.mxl')
            ? readMusicXmlFromMxl(file.readAsBytesSync())
            : file.readAsStringSync();
        final system = staffSystemFromMusicXml(xml);
        final staves = system.staves;
        if (staves.isEmpty) throw const FormatException('no staves');
        final shift = _systemShifts(staves);
        actual = _onsets(staves.first, shift[0]);
        spacers = _hiddenNote.hasMatch(xml)
            ? _spacerOnsets(staves.first, shift[0])
            : const [];
        // The other staves of the first part (a brace from staff 0): Verovio
        // reports a note written on its voice's other staff under the voice's
        // home staff, so a staff-1 note it lists may be a crisp note there.
        final braced = system.brackets
            .where((b) => b.kind == StaffBracketKind.brace && b.first == 0)
            .fold(0, (last, b) => max(last, b.last));
        otherStaves = [
          for (var s = 1; s <= braced && s < staves.length; s++)
            ..._onsets(staves[s], shift[s]),
        ]..sort((a, b) => a.q.compareTo(b.q));
      } on Object catch (e) {
        disagreements.add('$path: read failed: $e');
        continue;
      }
      final need = (expected.length * 0.98).ceil();
      var best = _match(expected, actual, 0, otherStaves, spacers);
      var bestDelta = 0;
      for (var delta = -24; best.matches < need && delta <= 24; delta++) {
        if (delta == 0) continue;
        final m = _match(expected, actual, delta, otherStaves, spacers);
        if (m.matches > best.matches) (best, bestDelta) = (m, delta);
      }
      final excuse = _verovioMisreads[path];
      if (excuse != null) {
        excused++;
        if (best.matches >= need) {
          disagreements.add('$path: excused, but agrees now: take it off the '
              'list');
        }
      } else if (best.matches >= need) {
        agree++;
      } else {
        final miss = best.firstMiss!;
        disagreements.add('$path: ${best.matches}/${expected.length} '
            '(crisp ${actual.length}), first miss at quarter '
            '${miss.q.toStringAsFixed(3)} pitch ${miss.pitch}'
            '${bestDelta == 0 ? '' : ' (offset $bestDelta)'}');
      }
    }
    // ignore: avoid_print
    print('verovio onsets: $agree / ${paths.length} files agree '
        '($excused that Verovio misreads set aside)');
    final report = Platform.environment['CRISP_ORACLE_REPORT'];
    if (report != null) {
      File(report).writeAsStringSync(disagreements.join('\n'));
    }

    // A ratchet: raise it as fixes land, never lower it.
    // 2026-10-16: 1501 / 1745 at the first measurement; 1645 once grace
    // notes may start on the beat; 1678 after whole-bar rests fill the bar;
    // 1685 once a bar's types win over durations that cannot fill it; 1689
    // once Verovio's rolled arpeggios and tremolo strokes are allowed for.
    // 2026-10-18: 1709 with bars aligned across the system, cross-staff and
    // unprinted notes and unpitched pitch 0 allowed for, 22 files Verovio
    // misreads set aside (none counted as agreeing), and nine MusicXML timing
    // fixes (voice slots past 4, unbracketed time-modifications, hidden
    // notes, bar and typeless rests, unpitched notes, quarter tones).
    const floor = 1709;
    expect(agree, greaterThanOrEqualTo(floor),
        reason: disagreements.take(20).join('\n'));
  }, skip: skip);
}

class _Event {
  final double q;
  final int pitch;

  /// How much later Verovio may start this note: a note after grace notes
  /// starts on the beat in crisp_notation (the graces take time before it)
  /// but after the graces in Verovio, which plays them on the beat; and
  /// Verovio rolls an arpeggiated chord's notes out by up to a quarter note.
  final double slack;

  /// When this crisp note carries a tremolo, its sounding length in quarter
  /// notes. Verovio's timemap repeats such a note's pitch once per stroke;
  /// those repeats are the same note, not missing onsets.
  final double tremoloDuration;

  const _Event(this.q, this.pitch, [this.slack = 0, this.tremoloDuration = 0]);
}

/// Per staff, per measure, how much later (in quarter notes) the measure
/// starts in the whole system than in that staff alone.
///
/// A bar is as long as its longest staff: Verovio's timemap starts every
/// staff's next bar together, after the longest. crisp_notation's timeline
/// is per staff, so a part whose bar is written short (a voice in 4/4 over a
/// 12/8 piano, an incomplete bar in one part) would start its next bar early
/// and every later onset would differ, though no note was misread. The bar
/// lengths follow `playbackTimeline`'s.
List<List<double>> _systemShifts(List<Score> staves) {
  final lengths = [for (final staff in staves) _barLengths(staff)];
  final count = lengths.fold(0, (n, l) => max(n, l.length));
  final shifts = [for (final _ in staves) <double>[]];
  var system = 0.0;
  final own = List<double>.filled(staves.length, 0);
  for (var m = 0; m < count; m++) {
    var longest = 0.0;
    for (var s = 0; s < staves.length; s++) {
      if (m < lengths[s].length) {
        shifts[s].add(system - own[s]);
        own[s] += lengths[s][m];
        longest = max(longest, lengths[s][m]);
      }
    }
    system += longest;
  }
  return shifts;
}

/// Each measure's length in quarter notes, as `playbackTimeline` advances.
List<double> _barLengths(Score score) {
  var meter = score.timeSignature;
  final out = <double>[];
  for (final measure in score.measures) {
    meter = measure.timeChange ?? meter;
    final bar = measure.capacityGiven(meter);
    var end = Fraction.zero;
    for (var v = 0; v < 4; v++) {
      final voice = measure.voiceAt(v);
      var clock = Fraction.zero;
      for (var i = 0; i < voice.length; i++) {
        final e = voice[i];
        final barRest = bar != null &&
            voice.length == 1 &&
            e is RestElement &&
            !e.hidden &&
            e.duration.base == DurationBase.whole &&
            e.duration.dots == 0;
        clock =
            clock + (barRest ? bar : measure.effectiveDurationAt(i, voice: v));
      }
      if (clock.compareTo(end) > 0) end = clock;
    }
    if (measure.multiRest != null && meter != null) {
      end = Fraction(meter.beats * measure.multiRest!, meter.beatUnit);
    } else if (end == Fraction.zero && meter != null) {
      end = Fraction(meter.beats, meter.beatUnit);
    }
    out.add((end * Fraction(4, 1)).toDouble());
  }
  return out;
}

/// Every sounding note of [score] as (quarter-note onset, MIDI pitch), in
/// document order (repeats not expanded), sorted by onset; each measure moved
/// by its [shift] (see [_systemShifts]).
List<_Event> _onsets(Score score, List<double> shift) {
  final byId = <String, NoteElement>{
    for (final m in score.measures)
      for (final e in [...m.elements, ...m.voice2, ...m.voice3, ...m.voice4])
        if (e is NoteElement && e.id != null) e.id!: e,
  };
  final out = <_Event>[
    for (final n in playbackTimeline(score, expandRepeats: false))
      if (!n.isRest && byId[n.elementId] != null)
        for (final p in byId[n.elementId]!.pitches)
          _Event(
              (n.start * Fraction(4, 1)).toDouble() + shift[n.measureIndex],
              p.midiNumber,
              max(
                byId[n.elementId]!.graceNotes.isEmpty
                    ? 0.0
                    : (n.duration * Fraction(2, 1)).toDouble(),
                byId[n.elementId]!.arpeggio != null ? _rollSlack : 0.0,
              ),
              byId[n.elementId]!.tremolo != null
                  ? (n.duration * Fraction(4, 1)).toDouble()
                  : 0),
  ]..sort((a, b) => a.q.compareTo(b.q));
  return out;
}

const _tolerance = 1 / 64 + 1e-9;

/// How late Verovio may start a note of a rolled (arpeggiated) chord: it
/// rolls the chord out 15/256 of a quarter per note, upwards, and a roll
/// across both staves of a piano counts the other staff's notes too — seven
/// notes take 3/8 of a quarter.
const _rollSlack = 3 / 8 + _tolerance;

/// A `<note print-object="no">` with a `<pitch>`: an unprinted note.
final _hiddenNote = RegExp(
    r'<note\b[^>]*print-object="no"[^>]*>(?:(?!</note>).)*?<pitch>',
    dotAll: true);

/// The onsets of [score]'s hidden rests, each measure moved by its [shift].
/// Only used for a file with unprinted notes ([_hiddenNote]): elsewhere a
/// hidden rest is a gap no note was written in.
///
/// crisp_notation keeps an unprinted note (`print-object="no"`) only as a
/// silent spacer: it is a playback-only pitch, drawn nowhere. Verovio sounds
/// it. Not a misreading, so a Verovio note at a spacer's onset counts as
/// found.
List<double> _spacerOnsets(Score score, List<double> shift) {
  final lengths = _barLengths(score);
  final out = <double>[];
  var start = 0.0;
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    for (var v = 0; v < 4; v++) {
      final voice = measure.voiceAt(v);
      var clock = Fraction.zero;
      for (var i = 0; i < voice.length; i++) {
        final e = voice[i];
        if (e is RestElement && e.hidden) {
          out.add(start + (clock * Fraction(4, 1)).toDouble() + shift[m]);
        }
        clock = clock + measure.effectiveDurationAt(i, voice: v);
      }
    }
    start += lengths[m];
  }
  return out..sort();
}

/// How many of [expected] find an unused note of [actual] (both sorted by
/// onset) within [_tolerance] (and its slack) at pitch + [delta]; and the
/// first that does not. A note [actual] lacks may be found among [others],
/// the first part's other staves (a cross-staff note, which Verovio lists
/// under its voice's home staff).
///
/// The slack is the file's largest one — a grace cluster's, or an arpeggio's
/// quarter note — and so applies to every expected note: Verovio rolls one
/// file's arpeggiated chords out by the same amount while crisp draws each
/// chord together, so a chord whose own crisp note has no arpeggio (a bracket
/// chord in the same file) is late too.
///
/// Verovio gives an unpitched (percussion) note MIDI pitch 0, where crisp
/// keeps the staff position it is drawn at; such a note matches on its onset.
///
/// A note Verovio sounds where crisp keeps a hidden note's time as a spacer
/// ([spacers]) is found there.
({int matches, _Event? firstMiss}) _match(
    List<_Event> expected, List<_Event> actual, int delta,
    [List<_Event> others = const [], List<double> spacers = const []]) {
  final used = List<bool>.filled(actual.length, false);
  final usedOther = List<bool>.filled(others.length, false);
  final slack = actual.fold<double>(0, (m, a) => max(m, a.slack));
  var matches = 0;
  _Event? firstMiss;
  var low = 0;
  var lowOther = 0;

  bool find(_Event e, List<_Event> pool, List<bool> taken, int from) {
    for (var i = from; i < pool.length && pool[i].q <= e.q + _tolerance; i++) {
      final a = pool[i];
      if (!taken[i] &&
          (a.pitch == e.pitch + delta || e.pitch == 0) &&
          e.q >= a.q - _tolerance &&
          e.q <= a.q + slack + _tolerance) {
        taken[i] = true;
        return true;
      }
    }
    return false;
  }

  for (final e in expected) {
    while (low < actual.length && actual[low].q < e.q - slack - _tolerance) {
      low++;
    }
    while (lowOther < others.length &&
        others[lowOther].q < e.q - slack - _tolerance) {
      lowOther++;
    }
    if (find(e, actual, used, low) ||
        // Verovio repeats a tremolo's pitch once per stroke; the repeat is the
        // same crisp note, so it counts as matched.
        _tremoloRepeat(e, actual, used, delta) ||
        find(e, others, usedOther, lowOther) ||
        spacers.any((q) => (q - e.q).abs() <= _tolerance)) {
      matches++;
    } else {
      firstMiss ??= e;
    }
  }
  return (matches: matches, firstMiss: firstMiss);
}

/// Whether [e] is a stroke repeat of an already-matched crisp tremolo note:
/// the same pitch, inside that note's sounding length.
bool _tremoloRepeat(_Event e, List<_Event> actual, List<bool> used, int delta) {
  for (var i = 0; i < actual.length; i++) {
    final a = actual[i];
    if (!used[i] || a.tremoloDuration <= 0) continue;
    if (a.pitch != e.pitch + delta) continue;
    if (e.q >= a.q - _tolerance &&
        e.q <= a.q + a.tremoloDuration + _tolerance) {
      return true;
    }
  }
  return false;
}

/// Files Verovio misreads (or the oracle mislists), set aside with the
/// reason. Each was read by hand: crisp_notation's onsets follow the file's
/// `<duration>`s, Verovio's do not. One that starts to agree is reported, to
/// be taken off.
const _verovioMisreads = <String, String>{
  'musicxml-testsuite/lilypond/11h-TimeSignatures-SenzaMisura.xml':
      "Verovio gives the unmetered bar's whole-bar rest no time; it lasts the 3 quarters its <duration> says.",
  'musicxml-testsuite/lilypond/23c-Tuplet-Display-NonStandard.xml':
      'Verovio times the groups by their displayed numbers (<tuplet-actual>/<tuplet-normal>, 7:5 and so on); their <time-modification> and <duration>s say 3:2.',
  'musicxml-testsuite/lilypond/23d-Tuplets-Nested.xml':
      "The inner group's <time-modification> (15:4) contradicts its <duration>s (15:8) and Verovio applies neither (5:4); nested groups are also more than TupletSpan holds.",
  'musicxml-testsuite/lilypond/23f-Tuplets-DurationButNoBracket.xml':
      "Verovio ignores a <time-modification> with no <tuplet>; the file's <duration>s make the triplets it is named for.",
  'musicxml-testsuite/lilypond/24b-ChordAsGraceNote.xml':
      "The oracle lists a grace chord's upper tones (it leaves out only the first), and Verovio plays the appoggiatura chord on the beat, delaying the chord it leans on.",
  'musicxml-testsuite/lilypond/24e-GraceNote-StaffChange.xml':
      'Verovio starts each half note a quarter late after a grace note written on the other staff.',
  'musicxml-testsuite/lilypond/32a-Notations.xml':
      "Verovio applies an ornament's <accidental-mark> (a double sharp above the note) to the note's own pitch, and keeps it for the rest of the piece.",
  'musicxml-testsuite/lilypond/33j-Beams-Tremolos.xml':
      'Verovio plays the 3:1 quarter-note tremolos of bar 2 in half their time.',
  'musicxml-testsuite/lilypond/34b-Colors.xml':
      "Verovio plays bar 5's 4:3 eighths as 16ths; their <duration>s agree with the 4:3.",
  'musicxml-testsuite/lilypond/34c-Font-Size.xml':
      "Verovio plays bar 5's 4:3 quarters as eighths; their <duration>s agree with the 4:3.",
  'musicxml-testsuite/lilypond/46j-EmptyMeasure.xml':
      "Verovio gives the empty bar no time; crisp gives it its meter's length, as the file's description says applications do.",
  'raw/Lieder/scores/Brahms,_Johannes/6_Songs,_Op.6/6_Nachtigallen_schwingen_lustig/lc5639135.mxl':
      "Verovio starts bar 34 a triplet eighth late; every part's bars 28-34 last 4 quarters by their <duration>s, as crisp reads them.",
  'raw/Lieder/scores/Brahms,_Johannes/9_Lieder_und_Gesänge,_Op.32/2_Nicht_mehr_zu_dir_zu_gehen/lc5846184.mxl':
      "Verovio makes bar 17 a quarter longer where the piano's third voice is spaced by <forward>s of 1024+768+192+48+12+4 divisions; the bar lasts 6 quarters.",
  'raw/Lieder/scores/Chaminade,_Cécile/_/Le_Noël_des_oiseaux/lc29421629.mxl':
      "Verovio makes bar 34 longer at the piano's nested 9:4 group (three 3-note groups inside it); by its <duration>s the bar lasts 2 quarters.",
  'raw/Lieder/scores/Duchambge,_Pauline/_/Prière_des_laboureurs/lc6593095.mxl':
      "From bar 34 Verovio's voice notes repeat earlier bars' (the second section restarts its measure numbers at 1, opening on a 4-bar <multiple-rest>); crisp's follow the file note for note.",
  'raw/Lieder/scores/Grandval,_Clémence_de/6_Nouvelles_mélodies/5_Rappelle-toi!/lc6614760.mxl':
      'Verovio counts the 5-bar <multiple-rest> of bar 50 as five bars on top of the rest bars the file writes out after it.',
  'raw/Lieder/scores/Holmès,_Augusta_Mary_Anne/Les_Sept_Ivresses/1_L’Amour/lc5646201.mxl':
      'Verovio makes bar 39 longer where the piano is spaced by <forward>s of 256+192+48+12+4 divisions; every bar lasts its 3 quarters.',
  'raw/Lieder/scores/Holmès,_Augusta_Mary_Anne/Les_Sept_Ivresses/7_L’Or/lc5879039.mxl':
      "Verovio drifts in the piano's bars of 2:1 half-note tremolos (bars 17-19); each lasts its 4 quarters.",
  'raw/Lieder/scores/Jaëll,_Marie/Les_Orientales/1_Rêverie/lc6214351.mxl':
      "Verovio drifts in the piano's triplet bars 73-77 (hidden notes, <forward>s); each lasts its 2 quarters.",
  'raw/Lieder/scores/Mahler,_Gustav/Lieder_eines_fahrenden_Gesellen/3_Ich_hab’_ein_glühend_Messer/lc5026306.mxl':
      "Verovio makes the piano's bars 66-69 (10:8 and 9:8 groups, 2:1 tremolos) a quarter longer; each lasts its 4 quarters.",
  'raw/Lieder/scores/Reichardt,_Louise/12_Deutsche_und_Italiänische_Romantische_Gesänge/2_Wenn_ich_ihn_nur_habe/lc5100067.mxl':
      "Bar 6's third quarter lasts a dotted quarter by its <duration> (which then fills the bar; the types do not), and Verovio plays it a quarter.",
  'raw/Lieder/scores/Reichardt,_Louise/6_Lieder_von_Novalis,_Op.4/3a_Geistliches_Lied/lc5092560.mxl':
      "Bar 6's third quarter lasts a dotted quarter by its <duration> (which then fills the bar; the types do not), and Verovio plays it a quarter.",
};
