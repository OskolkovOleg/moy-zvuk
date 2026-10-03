import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../playback/music_handler.dart';
import 'widgets.dart';
import 'lyrics_screen.dart';
import 'queue_view.dart';
import 'playback_controls.dart';

part 'player_content.dart';

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
                  onPressed: music.canSkipNext ? music.skipToNext : null,
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
                Expanded(child: _PlayerContent(app, track)),
            ],
          ),
        ),
      );
    },
  );
}
