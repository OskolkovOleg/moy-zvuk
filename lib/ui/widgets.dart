import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';

String scoreLabel(int score) => score > 0 ? '+$score' : '$score';
String timeLabel(Duration time) =>
    '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';

class Artwork extends StatelessWidget {
  const Artwork(this.track, {super.key, this.size = 48});
  final Track track;
  final double size;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * .4,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 100 ? 20 : 10),
      child: SizedBox.square(
        dimension: size,
        child: track.imageUrl == null
            ? placeholder
            : Image.network(
                track.imageUrl!,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 1024),
                cacheHeight: (size * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 1024),
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, wasSync) =>
                    frame == null ? placeholder : child,
                errorBuilder: (_, error, stack) => placeholder,
              ),
      ),
    );
  }
}

class RatingControls extends StatelessWidget {
  const RatingControls({
    super.key,
    required this.score,
    required this.onVote,
    this.title = 'трек',
  });
  final int score;
  final ValueChanged<int> onVote;
  final String title;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Минус один: $title',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => onVote(-1),
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 52,
          child: Semantics(
            label: 'Счёт $score',
            child: ExcludeSemantics(
              child: Text(
                scoreLabel(score),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: score > 0
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Плюс один: $title',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => onVote(1),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
  );
}

class OrderControls extends StatelessWidget {
  const OrderControls({super.key, required this.title, this.onUp, this.onDown});
  final String title;
  final VoidCallback? onUp, onDown;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Выше: $title',
        onPressed: onUp,
        icon: const Icon(Icons.arrow_upward_rounded, size: 22),
      ),
      IconButton(
        tooltip: 'Ниже: $title',
        onPressed: onDown,
        icon: const Icon(Icons.arrow_downward_rounded, size: 22),
      ),
    ],
  );
}

void notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> moveWithFeedback(
  BuildContext context,
  AppController app,
  int index,
  int delta,
) async {
  try {
    await app.moveTrack(index, delta);
  } catch (_) {
    if (context.mounted) {
      notify(context, 'Порядок не сохранился. Попробуй ещё раз.');
    }
  }
}

Future<void> voteWithUndo(
  BuildContext context,
  AppController app,
  Track track,
  int delta,
) async {
  final accountId = app.account!.id;
  try {
    final event = await app.vote(track, delta);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('${track.title}: ${scoreLabel(delta)}'),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            try {
              await app.undo(accountId, event);
            } catch (_) {
              if (context.mounted) {
                notify(context, 'Не удалось отменить оценку. Попробуй снова.');
              }
            }
          },
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      notify(context, 'Оценка не сохранилась. Попробуй ещё раз.');
    }
  }
}

class TrackMenu extends StatelessWidget {
  const TrackMenu(this.app, this.track, {super.key});
  final AppController app;
  final Track track;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Действия: ${track.title}',
    icon: const Icon(Icons.more_horiz_rounded),
    onSelected: (value) async {
      try {
        await app.music.enqueueTrack(track, next: value == 'next');
        if (context.mounted) {
          notify(
            context,
            value == 'next' ? 'Будет следующей' : 'Добавлено в конец очереди',
          );
        }
      } catch (_) {
        if (context.mounted) notify(context, 'Не удалось сохранить очередь.');
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: 'next',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.playlist_play_rounded),
          title: Text('Следующим'),
        ),
      ),
      PopupMenuItem(
        value: 'last',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.playlist_add_rounded),
          title: Text('В конец очереди'),
        ),
      ),
    ],
  );
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.app,
    required this.onPlay,
    this.orderIndex,
    this.orderLength,
  });
  final Track track;
  final AppController app;
  final VoidCallback onPlay;
  final int? orderIndex, orderLength;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: app.music.revision,
    builder: (context, _, _) {
      final current = app.music.playlist.current?.id == track.id;
      final scheme = Theme.of(context).colorScheme;
      final manual = orderIndex != null && !app.ranked;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: current ? scheme.primary.withValues(alpha: .09) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onPlay,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 0, 12),
                      child: Row(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Artwork(track, size: 46),
                              if (current)
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 14,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    height: 1.25,
                                    color: current
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artists,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (manual)
                  OrderControls(
                    title: track.title,
                    onUp: orderIndex! > 0 && !app.reordering
                        ? () => moveWithFeedback(context, app, orderIndex!, -1)
                        : null,
                    onDown: orderIndex! < orderLength! - 1 && !app.reordering
                        ? () => moveWithFeedback(context, app, orderIndex!, 1)
                        : null,
                  ),
                TrackMenu(app, track),
              ],
            ),
            if (app.ranked)
              Padding(
                padding: const EdgeInsets.only(left: 66, right: 8, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Твой счёт',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    RatingControls(
                      score: app.ratings[track.id]?.score ?? 0,
                      title: track.title,
                      onVote: (delta) =>
                          voteWithUndo(context, app, track, delta),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
