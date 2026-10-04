part of 'player_sheet.dart';

/// The cover receives the space left after the controls, so playback and
/// ratings stay visible without scrolling on short screens or with large text.
class _PlayerContent extends StatelessWidget {
  const _PlayerContent(this.app, this.track);
  final AppController app;
  final Track track;

  Widget cover() => LayoutBuilder(
    builder: (context, box) {
      final size = math.min(360.0, math.min(box.maxWidth, box.maxHeight));
      if (size < 48) return const SizedBox.shrink();
      return Center(
        child: Hero(
          tag: 'now-playing-cover',
          child: Artwork(track, size: size),
        ),
      );
    },
  );

  Widget identity(BuildContext context, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: track.title,
                      child: Text(
                        track.title,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 22 : 26,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ArtistLink(
                      app,
                      track,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FavoriteButton(app, track),
              TrackMenu(app, track),
            ],
          ),
          const SizedBox(height: 6),
          RatingPositionLabel(
            position: app.positionFor(track),
            listTitle: app.listTitle,
            compact: true,
          ),
          if (app.music.error.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                app.music.error.value!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget rating(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ordered = app.visibleTracks;
    final index = ordered.indexWhere((t) => t.id == track.id);
    if (app.ranked) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Твой счёт',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ),
          RatingControls(
            score: app.scoreFor(track),
            title: track.title,
            onVote: (delta) => voteWithFeedback(context, app, track, delta),
          ),
        ],
      );
    }
    if (index < 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: 'В «${app.listTitle}»',
            child: Text(
              'Вручную: № ${index + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        OrderControls(
          title: track.title,
          onUp: index > 0 && !app.reordering
              ? () => moveWithFeedback(context, app, index, -1)
              : null,
          onDown: index < ordered.length - 1 && !app.reordering
              ? () => moveWithFeedback(context, app, index, 1)
              : null,
        ),
      ],
    );
  }

  Widget controls(
    BuildContext context, {
    required bool includeIdentity,
    required bool compact,
  }) {
    final music = app.music;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (includeIdentity) identity(context, compact: compact),
        PositionControl(
          music,
          key: ValueKey('seek:${track.id}:${music.playlist.index}'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Предыдущий трек',
              iconSize: 36,
              onPressed: music.skipToPrevious,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            PlayButton(app),
            IconButton(
              tooltip: 'Следующий трек',
              iconSize: 36,
              onPressed: music.canSkipNext ? music.skipToNext : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        PlaybackControls(
          music,
          center: TextButton.icon(
            onPressed: () => openLyrics(context, app, track),
            icon: const Icon(Icons.lyrics_outlined),
            label: const Text(
              'Текст песни',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        rating(context),
      ],
    );
  }

  Widget fitted(Widget child, double width, double height) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: height),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(width: width, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight * 1.3 && box.maxWidth > 500;
        if (wide) {
          final width = (box.maxWidth - 24) / 2;
          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: cover()),
                    fitted(
                      identity(context, compact: true),
                      width,
                      box.maxHeight,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Center(
                  child: fitted(
                    controls(context, includeIdentity: false, compact: true),
                    width,
                    box.maxHeight,
                  ),
                ),
              ),
            ],
          );
        }
        final width = math.min(460.0, box.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                Expanded(child: cover()),
                fitted(
                  controls(
                    context,
                    includeIdentity: true,
                    compact: box.maxHeight < 600,
                  ),
                  width,
                  box.maxHeight,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
