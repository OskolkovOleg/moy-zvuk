import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import 'widgets.dart';

Future<void> openShuffle(BuildContext context, AppController app) async {
  if (app.tracks.isEmpty) return;
  final count = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ShuffleSheet(
      tracks: List.of(app.tracks),
      ratings: Map.of(app.ratings),
      title: app.listTitle,
    ),
  );
  if (count == null) return;
  try {
    await app.playShuffled(bestCount: count == 0 ? null : count);
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
  bool best = false;
  late int count = math.min(50, widget.tracks.length);

  @override
  Widget build(BuildContext context) {
    final total = widget.tracks.length;
    final scheme = Theme.of(context).colorScheme;
    final ranked = rankedTracks(widget.tracks, widget.ratings);
    final cutoff = count > 0
        ? widget.ratings[ranked[count - 1].id]?.score ?? 0
        : 0;
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Все треки')),
                  ButtonSegment(value: true, label: Text('Лучшие по баллам')),
                ],
                selected: {best},
                onSelectionChanged: (s) => setState(() => best = s.first),
              ),
            ),
            const SizedBox(height: 24),
            if (best) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Сколько лучших',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '$count',
                    key: const Key('shuffle-count'),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                key: const Key('shuffle-count-slider'),
                min: 1,
                max: math.max(2, total).toDouble(),
                divisions: math.max(1, total - 1),
                value: math.max(1, count).toDouble(),
                label: 'Треков: $count',
                onChanged: total > 1
                    ? (v) => setState(() => count = v.round())
                    : null,
              ),
              Text(
                '$count из $total · от ${scoreLabel(cutoff)} баллов',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              const Text(
                'Сначала выберем песни с наибольшими баллами, затем перемешаем их. У песен без оценок — 0 баллов.',
              ),
            ] else
              Text(
                'Треков в списке: $total. Все прозвучат в случайном порядке.',
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('start-shuffle'),
                onPressed: total == 0
                    ? null
                    : () => Navigator.pop(context, best ? count : 0),
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Перемешать и слушать'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
