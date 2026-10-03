import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/wave_options.dart';
import '../data/zvuk_api.dart';
import '../playback/music_handler.dart';
import 'catalog_widgets.dart';

Future<void> openWaveSettings(BuildContext context, AppController app) =>
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => WaveSettingsScreen(app)));

class WaveSettingsScreen extends StatefulWidget {
  const WaveSettingsScreen(this.app, {super.key});
  final AppController app;
  @override
  State<WaveSettingsScreen> createState() => _WaveSettingsScreenState();
}

class _WaveSettingsScreenState extends State<WaveSettingsScreen> {
  late final account = widget.app.account?.id;
  late WaveOptions options = widget.app.music.waveOptions;
  bool saving = false;
  String? error;

  void update({
    WaveMood? mood,
    WaveLanguage? language,
    WavePopularity? popularity,
    List<String>? genres,
  }) => setState(() {
    options = WaveOptions(
      mood: mood ?? options.mood,
      language: language ?? options.language,
      popularity: popularity ?? options.popularity,
      genres: genres ?? options.genres,
    );
    error = null;
  });

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (account == null || widget.app.account?.id != account) {
        throw const ZvukException('Аккаунт изменился. Открой настройки снова.');
      }
      await widget.app.music.setWaveOptions(options);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = catalogError(e);
          saving = false;
        });
      }
    }
  }

  Widget group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: children),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 21;
    final reset = TextButton(
      onPressed: saving
          ? null
          : () => setState(() => options = const WaveOptions()),
      child: const Text('Сбросить'),
    );
    final apply = FilledButton(
      onPressed: saving ? null : save,
      child: Text(saving ? 'Сохраняем…' : 'Применить', maxLines: 1),
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: largeText ? 80 : null,
        title: Text(
          'Настроить поток',
          maxLines: 2,
          style: largeText ? const TextStyle(fontSize: 18, height: 1.1) : null,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                children: [
                  Text(
                    'Подбор по твоему вкусу с выбранными фильтрами. '
                    'Если поток уже играет, изменения начнутся со следующей песни.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  group('Настроение', [
                    for (final value in WaveMood.values)
                      ChoiceChip(
                        label: Text(value.label),
                        selected: options.mood == value,
                        onSelected: saving ? null : (_) => update(mood: value),
                      ),
                  ]),
                  group('Жанры', [
                    FilterChip(
                      label: const Text('Все жанры'),
                      selected: options.genres.isEmpty,
                      onSelected: saving ? null : (_) => update(genres: []),
                    ),
                    for (final entry in waveGenres.entries)
                      FilterChip(
                        label: Text(entry.value),
                        selected: options.genres.contains(entry.key),
                        onSelected: saving
                            ? null
                            : (selected) => update(
                                genres: [
                                  ...options.genres.where(
                                    (g) => g != entry.key,
                                  ),
                                  if (selected) entry.key,
                                ],
                              ),
                      ),
                  ]),
                  group('Язык', [
                    for (final value in WaveLanguage.values)
                      ChoiceChip(
                        label: Text(value.label),
                        selected: options.language == value,
                        onSelected: saving
                            ? null
                            : (_) => update(language: value),
                      ),
                  ]),
                  group('Знакомое и новое', [
                    for (final value in WavePopularity.values)
                      ChoiceChip(
                        label: Text(value.label),
                        selected: options.popularity == value,
                        onSelected: saving
                            ? null
                            : (_) => update(popularity: value),
                      ),
                  ]),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: largeText
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [apply, reset],
                    )
                  : Row(
                      children: [
                        reset,
                        const SizedBox(width: 12),
                        Expanded(child: apply),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
