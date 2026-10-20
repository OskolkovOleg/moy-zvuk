import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../playback/shuffle_tracks.dart';
import 'widgets.dart';

Future<void> openShuffle(BuildContext context, AppController app) async {
  if (app.tracks.isEmpty) return;
  final account = app.account?.id, list = app.listId;
  final tracks = List<Track>.of(app.tracks),
      ratings = Map<String, Rating>.of(app.ratings);
  final range = await showModalBottomSheet<ScoreRange>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) =>
        ShuffleSheet(tracks: tracks, ratings: ratings, title: app.listTitle),
  );
  if (range == null || account != app.account?.id || list != app.listId) return;
  try {
    await app.playShuffled(
      minScore: range.min,
      maxScore: range.max,
      source: tracks,
      scores: ratings,
    );
  } catch (_) {
    if (context.mounted) notify(context, 'Не удалось запустить очередь.');
  }
}

class ShuffleSheet extends StatefulWidget {
  const ShuffleSheet({
    super.key,
    required this.tracks,
    required this.ratings,
    required this.title,
  });
  final List<Track> tracks;
  final Map<String, Rating> ratings;
  final String title;
  @override
  State<ShuffleSheet> createState() => _ShuffleSheetState();
}

class _ShuffleSheetState extends State<ShuffleSheet> {
  late final int lowest, highest;
  late ScoreRange range;
  @override
  void initState() {
    super.initState();
    final scores = widget.tracks
        .map((t) => trackScore(t.id, widget.ratings))
        .toList();
    lowest = scores.isEmpty ? initialTrackScore : scores.reduce(math.min);
    highest = scores.isEmpty ? initialTrackScore : scores.reduce(math.max);
    range = ScoreRange(lowest, highest);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matches = widget.tracks.where((t) {
      final score = trackScore(t.id, widget.ratings);
      return score >= range.min && score <= range.max;
    }).length;
    Widget bound(String title, int value, Key key) => Expanded(
      child: Column(
        crossAxisAlignment: title == 'От'
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(title, style: TextStyle(color: scheme.onSurfaceVariant)),
          Text(
            '$value',
            key: key,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Перемешать',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              widget.title,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text(
              'Диапазон баллов',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                bound('От', range.min, const Key('shuffle-min')),
                bound('До', range.max, const Key('shuffle-max')),
              ],
            ),
            RangeSlider(
              key: const Key('shuffle-score-slider'),
              min: lowest.toDouble(),
              max: (highest == lowest ? highest + 1 : highest).toDouble(),
              divisions: (highest - lowest).clamp(1, 200),
              values: RangeValues(range.min.toDouble(), range.max.toDouble()),
              labels: RangeLabels('${range.min}', '${range.max}'),
              onChanged: highest == lowest
                  ? null
                  : (v) => setState(
                      () => range = ScoreRange(v.start.round(), v.end.round()),
                    ),
            ),
            Text(
              matches == 0
                  ? 'В этом диапазоне нет песен'
                  : 'Подходит ${trackCountLabel(matches)}',
              key: const Key('shuffle-matches'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('start-shuffle'),
                onPressed: matches == 0
                    ? null
                    : () => Navigator.pop(context, range),
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Слушать'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
