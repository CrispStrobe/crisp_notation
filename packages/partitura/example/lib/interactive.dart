import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart';

/// Interactive demo: tap the staff to place a note (a ghost note previews
/// while dragging), tap a note to select/deselect it. Doubles as manual QA
/// for the interaction layer.
class InteractiveScreen extends StatefulWidget {
  const InteractiveScreen({super.key});

  @override
  State<InteractiveScreen> createState() => _InteractiveScreenState();
}

class _InteractiveScreenState extends State<InteractiveScreen> {
  static const int _measureCount = 2;

  Clef _clef = Clef.treble;
  bool _kidMode = false;
  NoteDuration _duration = NoteDuration.quarter;
  final Set<String> _selected = {};
  final List<List<NoteElement>> _placed = [
    for (var i = 0; i < _measureCount; i++) <NoteElement>[],
  ];
  var _nextId = 0;

  // Copy each measure's list: Score/Measure are value types over their
  // lists, so mutating a list in place would make the "new" score compare
  // equal to the old one and StaffView would skip the relayout.
  Score get _score => Score(
        clef: _clef,
        timeSignature: TimeSignature.fourFour,
        measures: [for (final elements in _placed) Measure(List.of(elements))],
      );

  void _placeNote(StaffTarget target) {
    setState(() {
      _placed[target.measureIndex].add(
        NoteElement.note(
          target.pitchFor(_clef),
          _duration,
          id: 'placed${_nextId++}',
        ),
      );
    });
  }

  void _toggleSelection(String elementId) {
    setState(() {
      if (!_selected.remove(elementId)) _selected.add(elementId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = _kidMode ? PartituraTheme.kids : PartituraTheme.standard;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: InteractiveStaff(
              score: _score,
              theme: theme,
              // Fixed scale: an empty measure fit to the card width would
              // blow the staff up comically large.
              staffSpace: 16,
              highlightedIds: _selected,
              ghostDuration: _duration,
              onStaffTap: _placeNote,
              onElementTap: _toggleSelection,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Tap an empty spot to place a note (drag to preview); '
          'tap a note to select it.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<Clef>(
              segments: const [
                ButtonSegment(value: Clef.treble, label: Text('Treble')),
                ButtonSegment(value: Clef.bass, label: Text('Bass')),
                ButtonSegment(value: Clef.alto, label: Text('Alto')),
                ButtonSegment(value: Clef.tenor, label: Text('Tenor')),
              ],
              selected: {_clef},
              onSelectionChanged: (selection) =>
                  setState(() => _clef = selection.single),
            ),
            SegmentedButton<NoteDuration>(
              segments: const [
                ButtonSegment(value: NoteDuration.whole, label: Text('𝅝')),
                ButtonSegment(value: NoteDuration.half, label: Text('𝅗𝅥')),
                ButtonSegment(value: NoteDuration.quarter, label: Text('♩')),
                ButtonSegment(value: NoteDuration.eighth, label: Text('♪')),
              ],
              selected: {_duration},
              onSelectionChanged: (selection) =>
                  setState(() => _duration = selection.single),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Kid mode'),
                Switch(
                  value: _kidMode,
                  onChanged: (value) => setState(() => _kidMode = value),
                ),
              ],
            ),
            FilledButton.tonal(
              onPressed: () => setState(() {
                for (final measure in _placed) {
                  measure.clear();
                }
                _selected.clear();
              }),
              child: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }
}
