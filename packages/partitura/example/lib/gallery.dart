import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart';

/// One entry of the gallery corpus.
class GalleryItem {
  final String title;
  final Score score;
  final PartituraTheme theme;
  final Set<String> highlightedIds;

  const GalleryItem(
    this.title,
    this.score, {
    this.theme = PartituraTheme.standard,
    this.highlightedIds = const {},
  });
}

/// The golden-test corpus, browsable on a device. Doubles as manual QA.
final List<GalleryItem> galleryItems = [
  GalleryItem(
    'C major scale (treble)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
    ),
  ),
  GalleryItem(
    'C major scale (bass)',
    Score.simple(
      clef: Clef.bass,
      timeSignature: TimeSignature.fourFour,
      notes: 'c3:q d3 e3 f3 | g3 a3 b3 c4',
    ),
  ),
  GalleryItem(
    'Durations: whole to quarter',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:w | c5:h c5:h | c5:q c5 c5 c5',
    ),
  ),
  GalleryItem(
    'Dotted notes',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:h. e5:q | a4:q. b4:e c5:h | g4:h..  g4:s g4:s',
    ),
  ),
  GalleryItem(
    'Rests',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'r:w | r:h r:q r:e r:s r:s | c5:q r:q. c5:e r:h',
    ),
  ),
  GalleryItem(
    'Accidentals & measure memory',
    Score.simple(notes: 'f#4:q bb4 cn5 g##4 | dbb5:q f#4 f4 f#5'),
  ),
  GalleryItem(
    'C# major: 7 sharps',
    Score.simple(
      keySignature: const KeySignature(7),
      notes: 'c#4:q d#4 e#4 f#4',
    ),
  ),
  GalleryItem(
    'Cb major: 7 flats',
    Score.simple(
      keySignature: const KeySignature(-7),
      notes: 'cb5:q bb4 ab4 gb4',
    ),
  ),
  GalleryItem(
    'Ab major in bass clef',
    Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(-4),
      notes: 'ab2:q bb2 c3 db3',
    ),
  ),
  GalleryItem(
    'Waltz time (3/4)',
    Score.simple(
      timeSignature: TimeSignature.threeFour,
      notes: 'g4:q b4 d5 | c5:h.',
    ),
  ),
  GalleryItem(
    '12/8 (two-digit numerator)',
    Score.simple(
      timeSignature: const TimeSignature(12, 8),
      notes: 'c5:h. c5:h.',
    ),
  ),
  GalleryItem(
    'Triads & inversions',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4+e4+g4:h e4+g4+c5:h | d4+f4:q f4+a4 g4+b4 d5+f5+a5',
    ),
  ),
  GalleryItem(
    'Seconds cluster across the stem',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4+d4:h e5+f5:h | b3+c4+d4:w',
    ),
  ),
  GalleryItem(
    'Beamed eighths (2 beams in 4/4)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
    ),
  ),
  GalleryItem(
    'Sixteenths & secondary beams',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:s d5 e5 f5 g5:e a5:s b5:s c6:q c5:q',
    ),
  ),
  GalleryItem(
    'Beam slant clamp',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:e c5 g4 c5 c4:e e4 g4 c5',
    ),
  ),
  GalleryItem(
    'Ledger lines',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'a3:q c4 a5 c6 | e6:h g3:h',
    ),
  ),
  GalleryItem(
    'Alle meine Entchen (G major)',
    Score.simple(
      keySignature: const KeySignature(1),
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:e a4 b4 c5 d5:q d5 | e5:e e5 e5 e5 d5:h',
    ),
  ),
  GalleryItem(
    'Highlights & element colors',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q e4 g4 c5',
    ),
    theme: const PartituraTheme(elementColors: {'e0': Color(0xFF43A047)}),
    highlightedIds: const {'e2'},
  ),
  GalleryItem(
    'Kids theme',
    Score.simple(
      timeSignature: TimeSignature.twoFour,
      notes: 'g4:q b4 | c5:e d5 e5 f5 | g5:h',
    ),
    theme: PartituraTheme.kids,
    highlightedIds: const {'e1'},
  ),
  GalleryItem(
    'Two voices (soprano/alto on one staff)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 ; c4:h e4:h | '
          'g5:e f5 e5 d5 e5:h ; c4:q r b3 c4 | '
          'e5:w ; c4:q c4 c4:h',
    ),
  ),
  GalleryItem(
    'Repeats, voltas & mid-score changes',
    Score.simple(
      keySignature: const KeySignature(2),
      timeSignature: TimeSignature.fourFour,
      notes: '!repeat d4:q f#4 a4 d5 | '
          '!endrepeat !volta=1 !key=-1 !time=3/4 bb4:q c5 d5 | '
          '!volta=2 !clef=bass d3:h.',
    ),
  ),
  GalleryItem(
    '32nds, 64ths & breve',
    Score.simple(
      notes: 'c5:t d5 e5 f5 g5:x a5 b5 c6 g5:t r:t a4:x r:x | c5:b',
    ),
  ),
  GalleryItem(
    'Grace notes (acciaccatura)',
    Score.simple(
      timeSignature: TimeSignature.threeFour,
      notes: '{g4}a4:q {f4,g4}a4:q {b4}c5:q | {c4}g4:h.',
    ),
  ),
  GalleryItem(
    'Dynamics & hairpins',
    () {
      final base = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 | g5:h e5:h',
      );
      return Score(
        clef: base.clef,
        timeSignature: base.timeSignature,
        measures: base.measures,
        dynamics: const [
          DynamicMarking('e0', DynamicLevel.p),
          DynamicMarking('e4', DynamicLevel.ff),
          DynamicMarking('e5', DynamicLevel.mp),
        ],
        hairpins: const [
          Hairpin('e0', 'e3', HairpinType.crescendo),
          Hairpin('e4', 'e5', HairpinType.diminuendo),
        ],
      );
    }(),
  ),
  GalleryItem(
    'Articulations & fermata',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: "c5:q' a4_ g4> c5^ | c4+e4:q' d5>' f4:h@",
    ),
  ),
  GalleryItem(
    'Tuplets (triplet, rest inside, quintuplet)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: '3[c5:e d5 e5] 3[c4:e r e4] 5[g4:s a4 b4 c5 d5] e5:q',
    ),
  ),
  GalleryItem(
    'Slurs (phrasing over any pitches)',
    Score.simple(
      timeSignature: TimeSignature.threeFour,
      notes: 'c4:q( d4 e4) | g5:e( a5 g5 f5 e5 d5) | c5:q( c6 g4) ',
    ),
  ),
  GalleryItem(
    'Ties (within and across measures)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:h~ c5:q a4:q~ | a4:h c4+e4:h~ | c4+e4:w~ | c4+e4:w',
    ),
  ),
  GalleryItem(
    'Alto clef: viola line (F major)',
    Score.simple(
      clef: Clef.alto,
      keySignature: const KeySignature(-1),
      timeSignature: TimeSignature.threeFour,
      notes: 'f3:q a3 c4 | c4:e d4 e4 f4 g4:q | a4+c4:h.',
    ),
  ),
  GalleryItem(
    'Tenor clef: cello line (D major)',
    Score.simple(
      clef: Clef.tenor,
      keySignature: const KeySignature(2),
      timeSignature: TimeSignature.fourFour,
      notes: 'd3:q f#3 a3 d4 | c#4:e b3 a3 g3 f#3:h',
    ),
  ),
  GalleryItem(
    'Unmetered bass chords (D major)',
    Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(2),
      notes: 'd3:q f#3+a3 d3+f#3+a3:h | g2+b2+d3:w',
    ),
  ),
  GalleryItem(
    'Chord symbols (annotations above the staff)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4+e4+g4:h a3+c4+e4:h | f3+a3+c4:h g3+b3+d4:h | c4+e4+g4:w',
      annotations: 'C Am F G7 C',
    ),
  ),
  GalleryItem(
    'Lyrics (hyphens, melisma extender)',
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q c4 g4 g4 | a4:q a4 g4:q g4 | f4:q f4 e4 e4 |'
          'd4:q d4 c4:h',
      lyrics: 'Twin- kle twin- kle lit- tle star_ * how I won- der '
          'what you are',
    ),
  ),
  GalleryItem(
    'Accidental stacking (dense chords)',
    Score.simple(
      notes: 'f#4+f#5:h c#4+d#4+e#4:h | c#4+f#4+a#4+c#5+f#5:w |'
          'bb3+eb4+ab4+db5:w',
    ),
  ),
];

/// Scrollable gallery of the corpus (plus grand-staff and multi-system
/// showcase cards).
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: galleryItems.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == galleryItems.length + 1) {
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Line breaking (multi-system)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  MultiSystemView(
                    score: Score.simple(
                      keySignature: const KeySignature(1),
                      timeSignature: TimeSignature.fourFour,
                      notes: 'g4:q a4 b4 c5 | d5:e c5 b4 a4 g4:h |'
                          'e4:q g4 b4 d5 | c5:q a4 f#4 d4 |'
                          'g4:e a4 b4 c5 d5:q g5 | f#5:q e5 d5 c5 | g4:w',
                    ),
                    staffSpace: 10,
                  ),
                ],
              ),
            ),
          );
        }
        if (index == galleryItems.length) {
          return Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grand staff (piano system)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  GrandStaffView(
                    grandStaff: GrandStaff(
                      upper: Score.simple(
                        keySignature: const KeySignature(1),
                        timeSignature: TimeSignature.fourFour,
                        notes: 'd5:q b4 g4 b4 | c5:e d5 e5 c5 d5:h',
                      ),
                      lower: Score.simple(
                        clef: Clef.bass,
                        keySignature: const KeySignature(1),
                        timeSignature: TimeSignature.fourFour,
                        notes: 'g2:h d3:h | c3:q e3 g3+b3:h',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final item = galleryItems[index];
        return Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                StaffView(
                  score: item.score,
                  theme: item.theme,
                  highlightedIds: item.highlightedIds,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
