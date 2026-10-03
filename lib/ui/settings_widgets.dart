import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../data/audio_preferences.dart';
import '../playback/music_handler.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.note,
  });
  final String title;
  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Material(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 52,
                      endIndent: 16,
                      color: scheme.outlineVariant.withValues(alpha: .6),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                note!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    horizontalTitleGap: 12,
    leading: Icon(icon, size: 22),
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(subtitle, style: const TextStyle(fontSize: 13, height: 1.3)),
    ),
    trailing: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : onTap == null
        ? null
        : const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: busy ? null : onTap,
  );
}

Future<AudioQuality?> chooseAudioQuality(
  BuildContext context, {
  required String title,
  required AudioQuality current,
}) => showModalBottomSheet<AudioQuality>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(title, style: Theme.of(sheet).textTheme.headlineSmall),
          ),
          for (final quality in AudioQuality.values)
            ListTile(
              key: ValueKey('quality-${quality.apiValue}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 4,
              ),
              title: Text(quality.label),
              subtitle: Text(quality.description),
              trailing: quality == current
                  ? Icon(
                      Icons.check_rounded,
                      color: Theme.of(sheet).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(sheet, quality),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  ),
);

String settingsRepeatLabel(AudioServiceRepeatMode mode) => switch (mode) {
  AudioServiceRepeatMode.one => 'Один трек',
  AudioServiceRepeatMode.all => 'Вся очередь',
  _ => 'Выключен',
};

Future<void> chooseRepeatMode(BuildContext context, MusicHandler music) async {
  final mode = await showModalBottomSheet<AudioServiceRepeatMode>(
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
                  'Повтор',
                  style: Theme.of(sheet).textTheme.headlineSmall,
                ),
              ),
            ),
            for (final value in [
              AudioServiceRepeatMode.none,
              AudioServiceRepeatMode.one,
              if (!music.isWave) AudioServiceRepeatMode.all,
            ])
              ListTile(
                key: ValueKey('settings-repeat-${value.name}'),
                title: Text(settingsRepeatLabel(value)),
                trailing: value == music.repeatMode
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(sheet).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(sheet, value),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
  if (mode != null) await music.setRepeatMode(mode);
}
