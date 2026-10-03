import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../playback/music_handler.dart';

String repeatLabel(AudioServiceRepeatMode mode) => switch (mode) {
  AudioServiceRepeatMode.one => 'Один трек',
  AudioServiceRepeatMode.all => 'Вся очередь',
  _ => 'Повтор',
};
String sleepLabel(MusicHandler music) {
  if (music.sleepTimer.stopsAfterSong) return 'После песни';
  final left = music.sleepTimer.remaining(DateTime.now());
  if (left == null) return 'Таймер сна';
  final seconds = (left.inMilliseconds / 1000).ceil();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class PlaybackControls extends StatelessWidget {
  const PlaybackControls(this.music, {super.key});
  final MusicHandler music;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        TextButton.icon(
          key: const Key('repeat-mode'),
          style: TextButton.styleFrom(
            foregroundColor: music.repeatMode == AudioServiceRepeatMode.none
                ? scheme.onSurfaceVariant
                : scheme.primary,
          ),
          onPressed: () => music.setRepeatMode(switch (music.repeatMode) {
            AudioServiceRepeatMode.none =>
              music.isWave
                  ? AudioServiceRepeatMode.one
                  : AudioServiceRepeatMode.all,
            AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
            _ => AudioServiceRepeatMode.none,
          }),
          icon: Icon(
            music.repeatMode == AudioServiceRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
          label: Text(repeatLabel(music.repeatMode)),
        ),
        TextButton.icon(
          key: const Key('sleep-timer'),
          style: TextButton.styleFrom(
            foregroundColor: music.sleepTimer.active
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
          onPressed: () => showSleepTimer(context, music),
          icon: const Icon(Icons.bedtime_outlined),
          label: Text(sleepLabel(music)),
        ),
      ],
    );
  }
}

Future<void> showSleepTimer(BuildContext context, MusicHandler music) async {
  final selection = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Таймер сна',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            for (final minutes in [5, 15, 30, 60])
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: Text('Через $minutes мин'),
                onTap: () => Navigator.pop(sheet, minutes),
              ),
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('После песни'),
              subtitle: const Text('Пауза, когда песня закончится'),
              onTap: () => Navigator.pop(sheet, -1),
            ),
            if (music.sleepTimer.active)
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Выключить таймер'),
                onTap: () => Navigator.pop(sheet, 0),
              ),
          ],
        ),
      ),
    ),
  );
  if (selection == null) return;
  if (selection == -1) {
    music.sleepAfterSong();
  } else if (selection == 0) {
    music.cancelSleepTimer();
  } else {
    music.setSleepTimer(Duration(minutes: selection));
  }
}
