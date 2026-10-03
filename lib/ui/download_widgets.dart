import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import '../downloads/download_record.dart';
import 'widgets.dart';

Future<void> downloadTracks(
  BuildContext context,
  AppController app,
  List<Track> tracks,
) async {
  try {
    await app.music.downloads.enqueue(tracks);
  } catch (e) {
    if (context.mounted) {
      notify(
        context,
        e is ZvukException
            ? e.message
            : 'Не удалось начать скачивание. Попробуй снова.',
      );
    }
  }
}

class DownloadListButton extends StatelessWidget {
  const DownloadListButton(
    this.app,
    this.tracks, {
    super.key,
    this.compact = false,
  });
  final AppController app;
  final List<Track> tracks;
  final bool compact;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app.music.downloads,
    builder: (context, _) {
      final downloads = app.music.downloads;
      final ids = tracks.map((t) => t.id).toSet();
      final complete = downloads.items
          .where(
            (item) =>
                ids.contains(item.track.id) &&
                item.state == DownloadState.ready,
          )
          .length;
      final active = downloads.items
          .where((item) => ids.contains(item.track.id) && item.active)
          .length;
      final done = tracks.isNotEmpty && complete == ids.length;
      final label = done
          ? 'Скачано'
          : active > 0
          ? 'Скачивается: $complete/${ids.length}'
          : 'Скачать список';
      final icon = done ? Icons.download_done_rounded : Icons.download_rounded;
      void start() => downloadTracks(context, app, tracks);
      if (compact) {
        return IconButton(
          tooltip: label,
          onPressed: tracks.isEmpty || done || active > 0 ? null : start,
          icon: Icon(icon, size: 22),
        );
      }
      return OutlinedButton.icon(
        onPressed: tracks.isEmpty || done || active > 0 ? null : start,
        icon: Icon(icon),
        label: Text(label),
      );
    },
  );
}
