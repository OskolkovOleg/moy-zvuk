import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import 'track_actions.dart';
export 'track_actions.dart' show openTrackActions;

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
    this.compact = false,
  });
  final int score;
  final ValueChanged<int> onVote;
  final String title;
  final bool compact;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: compact
          ? Colors.transparent
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Минус один: $title',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => onVote(-1),
          icon: Icon(Icons.remove_rounded, size: compact ? 18 : 24),
        ),
        SizedBox(
          width: compact ? 28 : 52,
          child: Semantics(
            label: 'Счёт $score',
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$score',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 14 : 17,
                    fontWeight: FontWeight.w700,
                    color: score > 0
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Плюс один: $title',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => onVote(1),
          icon: Icon(Icons.add_rounded, size: compact ? 18 : 24),
        ),
      ],
    ),
  );
}

class RatingPositionLabel extends StatelessWidget {
  const RatingPositionLabel({
    super.key,
    required this.position,
    required this.listTitle,
    this.compact = false,
  });
  final bool compact;
  final RatingPosition? position;
  final String listTitle;

  @override
  Widget build(BuildContext context) {
    final rank = position;
    final scheme = Theme.of(context).colorScheme;
    final label = Text(
      rank == null
          ? 'Нет в текущем списке'
          : '№ ${rank.position} из ${rank.total} по баллам',
      key: const Key('player-rating-position'),
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.primary,
      ),
    );
    if (compact) {
      return Tooltip(message: 'В «$listTitle»', child: label);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 3),
        Text(
          'В «$listTitle»',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
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

Future<void> voteWithFeedback(
  BuildContext context,
  AppController app,
  Track track,
  int delta,
) async {
  try {
    await app.vote(track, delta);
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
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Действия: ${track.title}',
    icon: const Icon(Icons.more_horiz_rounded),
    onPressed: () => openTrackActions(context, app, track),
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
    this.catalog = false,
    this.onActions,
  });
  final Track track;
  final AppController app;
  final VoidCallback onPlay;
  final int? orderIndex, orderLength;
  final bool catalog;
  final VoidCallback? onActions;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: app.music.revision,
    builder: (context, _, _) {
      final current = app.music.playlist.current?.id == track.id;
      final scheme = Theme.of(context).colorScheme;
      final manual = orderIndex != null && !app.ranked;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: current ? scheme.primary.withValues(alpha: .09) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onPlay,
                onLongPress:
                    onActions ?? () => openTrackActions(context, app, track),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Artwork(track, size: 48),
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                height: 1.25,
                                color: current
                                    ? scheme.primary
                                    : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
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
            if (app.ranked && !catalog)
              RatingControls(
                compact: true,
                score: app.scoreFor(track),
                title: track.title,
                onVote: (delta) => voteWithFeedback(context, app, track, delta),
              )
            else ...[
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
              if (onActions != null)
                IconButton(
                  tooltip: 'Действия: ${track.title}',
                  onPressed: onActions,
                  icon: const Icon(Icons.more_horiz_rounded),
                )
              else
                TrackMenu(app, track),
            ],
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
