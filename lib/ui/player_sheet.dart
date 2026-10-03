import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../playback/music_handler.dart';
import 'widgets.dart';

void openPlayer(BuildContext context, AppController app) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PlayerSheet(app),
      ),
    );

class MiniPlayer extends StatelessWidget {
  const MiniPlayer(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([app, app.music.revision, app.music.error]),
    builder: (context, _) {
      final music = app.music, track = music.playlist.current;
      if (track == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final rank = app.positionFor(track);
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => openPlayer(context, app),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
                      child: Row(
                        children: [
                          Hero(
                            tag: 'now-playing-cover',
                            child: Artwork(track, size: 42),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  music.error.value == null
                                      ? track.artists
                                      : 'Не удалось загрузить · открыть',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: music.error.value == null
                                        ? scheme.onSurfaceVariant
                                        : scheme.error,
                                  ),
                                ),
                                if (rank != null) ...[
                                  const SizedBox(height: 3),
                                  Tooltip(
                                    message:
                                        '№ ${rank.position} из ${rank.total} по баллам в «${app.listTitle}»',
                                    child: Text(
                                      '№ ${rank.position} по баллам',
                                      key: const Key('mini-rating-position'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PlayButton(app, compact: true),
                IconButton(
                  tooltip: 'Следующий трек',
                  onPressed: music.playlist.hasNext ? music.skipToNext : null,
                  icon: const Icon(Icons.skip_next_rounded, size: 27),
                ),
                const SizedBox(width: 4),
              ],
            ),
            StreamBuilder<Duration>(
              stream: music.player.positionStream,
              builder: (context, _) {
                final total = music.duration.inMilliseconds;
                return LinearProgressIndicator(
                  value: total <= 0
                      ? 0
                      : (music.position.inMilliseconds / total).clamp(0.0, 1.0),
                  minHeight: 2,
                  backgroundColor: scheme.outlineVariant,
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class PlayButton extends StatelessWidget {
  const PlayButton(this.app, {super.key, this.compact = false});
  final AppController app;
  final bool compact;
  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: app.music.playbackState,
    initialData: app.music.playbackState.value,
    builder: (context, snapshot) {
      final music = app.music;
      final active = snapshot.data?.playing == true || music.loading;
      final loading =
          music.loading ||
          (active &&
              snapshot.data?.processingState == AudioProcessingState.buffering);
      final icon = loading
          ? SizedBox.square(
              dimension: compact ? 21 : 26,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: compact ? null : Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : Icon(active ? Icons.pause_rounded : Icons.play_arrow_rounded);
      return compact
          ? IconButton(
              tooltip: active ? 'Пауза' : 'Воспроизвести',
              iconSize: 32,
              onPressed: active ? music.pause : music.play,
              icon: icon,
            )
          : SizedBox.square(
              dimension: 76,
              child: IconButton.filled(
                tooltip: active ? 'Пауза' : 'Воспроизвести',
                iconSize: 42,
                onPressed: active ? music.pause : music.play,
                icon: icon,
              ),
            );
    },
  );
}

class PositionControl extends StatefulWidget {
  const PositionControl(this.music, {super.key});
  final MusicHandler music;
  @override
  State<PositionControl> createState() => _PositionControlState();
}

class _PositionControlState extends State<PositionControl> {
  double? dragPosition;
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.music.player.positionStream,
    builder: (context, _) {
      final music = widget.music, duration = music.duration;
      final max = math.max(1.0, duration.inMilliseconds.toDouble());
      final value = (dragPosition ?? music.position.inMilliseconds.toDouble())
          .clamp(0.0, max);
      final display = Duration(milliseconds: value.round());
      final style = TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
      return Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context)
                .copyWith(trackShape: const RectangularSliderTrackShape()),
            child: Slider(
              key: const Key('player-seek'),
              value: value,
              max: max,
              semanticFormatterCallback: (v) =>
                  timeLabel(Duration(milliseconds: v.round())),
              onChanged: duration > Duration.zero && !music.loading
                  ? (v) => setState(() => dragPosition = v)
                  : null,
              onChangeEnd: (v) async {
                try {
                  await music.seek(Duration(milliseconds: v.round()));
                } finally {
                  if (mounted) setState(() => dragPosition = null);
                }
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(timeLabel(display), style: style),
              Text(timeLabel(duration), style: style),
            ],
          ),
        ],
      );
    },
  );
}

class PlayerSheet extends StatefulWidget {
  const PlayerSheet(this.app, {super.key});
  final AppController app;
  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  bool showQueue = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.app,
      widget.app.music.revision,
      widget.app.music.error,
    ]),
    builder: (context, _) {
      final app = widget.app, music = app.music;
      final track = music.playlist.current;
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Свернуть плеер',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 30,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            showQueue
                                ? 'Очередь'
                                : music.isShuffled
                                ? 'Вперемешку'
                                : 'Сейчас играет',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            music.sourceTitle,
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
                    IconButton(
                      tooltip: showQueue ? 'Плеер' : 'Очередь',
                      onPressed: () => setState(() => showQueue = !showQueue),
                      icon: Icon(
                        showQueue
                            ? Icons.album_outlined
                            : Icons.queue_music_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              if (track == null)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.queue_music_rounded,
                    title: 'Очередь пуста',
                    message: 'Выбери песню в библиотеке или поиске.',
                  ),
                )
              else if (showQueue)
                Expanded(child: QueueView(app))
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale =
                          MediaQuery.textScalerOf(context).scale(14) / 14;
                      final width = math.min(constraints.maxWidth - 48, 400.0);
                      final cover = (constraints.maxHeight - 440 * scale).clamp(
                        130.0,
                        width,
                      );
                      final ordered = app.visibleTracks;
                      final index = ordered.indexWhere((t) => t.id == track.id);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Hero(
                                    tag: 'now-playing-cover',
                                    child: Artwork(track, size: cover),
                                  ),
                                ),
                                const SizedBox(height: 26),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            track.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 26,
                                              height: 1.2,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            track.artists,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              height: 1.3,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TrackMenu(app, track),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                RatingPositionLabel(
                                  position: app.positionFor(track),
                                  listTitle: app.listTitle,
                                ),
                                const SizedBox(height: 8),
                                PositionControl(
                                  music,
                                  key: ValueKey(
                                    'seek:${track.id}:${music.playlist.index}',
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip: 'Предыдущий трек',
                                      iconSize: 36,
                                      onPressed: music.skipToPrevious,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 28),
                                    PlayButton(app),
                                    const SizedBox(width: 28),
                                    IconButton(
                                      tooltip: 'Следующий трек',
                                      iconSize: 36,
                                      onPressed: music.playlist.hasNext
                                          ? music.skipToNext
                                          : null,
                                      icon: const Icon(Icons.skip_next_rounded),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                if (music.error.value != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      music.error.value!,
                                      style: TextStyle(color: scheme.error),
                                    ),
                                  ),
                                if (app.ranked)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Твой счёт',
                                          style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      RatingControls(
                                        score: app.scoreFor(track),
                                        title: track.title,
                                        onVote: (delta) => voteWithUndo(
                                          context,
                                          app,
                                          track,
                                          delta,
                                        ),
                                      ),
                                    ],
                                  )
                                else if (index >= 0)
                                  Container(
                                    padding: const EdgeInsets.only(
                                      left: 14,
                                      right: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainer,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Вручную: № ${index + 1}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                'В «${app.listTitle}»',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        OrderControls(
                                          title: track.title,
                                          onUp: index > 0 && !app.reordering
                                              ? () => moveWithFeedback(
                                                  context,
                                                  app,
                                                  index,
                                                  -1,
                                                )
                                              : null,
                                          onDown:
                                              index < ordered.length - 1 &&
                                                  !app.reordering
                                              ? () => moveWithFeedback(
                                                  context,
                                                  app,
                                                  index,
                                                  1,
                                                )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 18),
                                InkWell(
                                  onTap: () => setState(() => showQueue = true),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.queue_music_rounded,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                music.playlist.hasNext
                                                    ? 'Далее'
                                                    : 'Последняя песня',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                music.playlist.hasNext
                                                    ? music
                                                          .playlist
                                                          .tracks[music
                                                                  .playlist
                                                                  .index +
                                                              1]
                                                          .title
                                                    : 'Очередь завершится без повтора',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${music.playlist.index + 1}/${music.playlist.tracks.length}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class QueueView extends StatefulWidget {
  const QueueView(this.app, {super.key});
  final AppController app;
  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  late final ScrollController scroll;
  @override
  void initState() {
    super.initState();
    scroll = ScrollController(
      initialScrollOffset: (widget.app.music.playlist.index * 76.0 - 76).clamp(
        0,
        double.infinity,
      ),
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.app.music, queue = music.playlist;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
          child: Text(
            '${queue.tracks.length} треков · ${music.isShuffled ? "случайный порядок" : "сверху вниз"}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: ValueKey('queue:${queue.tracks.length}'),
            controller: scroll,
            itemCount: queue.tracks.length,
            itemBuilder: (context, index) {
              final track = queue.tracks[index], current = index == queue.index;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Material(
                  color: current
                      ? scheme.primary.withValues(alpha: .09)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Artwork(track, size: 48),
                    title: Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: current ? scheme.primary : null,
                      ),
                    ),
                    subtitle: Text(
                      current
                          ? 'Сейчас играет · ${track.artists}'
                          : track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: current
                        ? Icon(Icons.graphic_eq_rounded, color: scheme.primary)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                    onTap: () => music.skipToQueueItem(index),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
