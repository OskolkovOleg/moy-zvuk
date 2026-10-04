import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../app_version.dart';
import '../data/models.dart';
import '../downloads/download_record.dart';
import 'downloads_screen.dart';
import 'playback_controls.dart';
import 'settings_widgets.dart';
import 'wave_settings.dart';
import 'widgets.dart';
import 'translation_info.dart';

class ConnectForm extends StatefulWidget {
  const ConnectForm(this.app, {super.key, this.onConnected});
  final AppController app;
  final VoidCallback? onConnected;
  @override
  State<ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends State<ConnectForm> {
  final token = TextEditingController();
  String? error;
  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    if (widget.app.connecting) return;
    if (token.text.trim().isEmpty) {
      setState(() => error = 'Вставь токен своего аккаунта');
      return;
    }
    setState(() => error = null);
    try {
      await widget.app.connect(token.text);
      if (!mounted) return;
      token.clear();
      widget.onConnected?.call();
    } catch (_) {
      if (mounted) {
        setState(() => error = widget.app.message ?? 'Подключение не удалось');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('token-input'),
          controller: token,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => connect(),
          decoration: InputDecoration(
            labelText: 'Токен Звука',
            hintText: 'Вставь личный токен',
            errorText: error,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Токен хранится защищённо на этом телефоне. Музыка загружается напрямую из твоего аккаунта.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: widget.app.connecting ? null : connect,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              widget.app.connecting ? 'Подключаю…' : 'Подключить Звук',
            ),
          ),
        ),
      ],
    ),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/brand/icon.png', width: 80, height: 80),
              const SizedBox(height: 32),
              Text(
                'Любимая музыка.\nВ твоём порядке.',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                'Расставляй песни стрелками и слушай сверху вниз. Или добавляй +1 и −1, чтобы любимые треки поднимались по баллам.',
                style: TextStyle(fontSize: 17, height: 1.45),
              ),
              const SizedBox(height: 36),
              ConnectForm(app),
              const SizedBox(height: 28),
              Text(
                'Личный плеер · Мой Звук',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(this.app, {super.key});
  final AppController app;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool transferring = false;
  bool savingQuality = false;

  Future<void> quality({required bool downloads}) async {
    final app = widget.app;
    final account = app.account?.id;
    final preferences = app.music.audioPreferences;
    final value = await chooseAudioQuality(
      context,
      title: downloads ? 'Качество скачивания' : 'Качество музыки',
      current: downloads ? preferences.downloads : preferences.streaming,
    );
    if (value == null || !mounted) return;
    if (account != app.account?.id) {
      notify(context, 'Аккаунт изменился. Открой настройки снова.');
      return;
    }
    setState(() => savingQuality = true);
    try {
      await app.music.setAudioPreferences(
        app.music.audioPreferences.copyWith(
          streaming: downloads ? null : value,
          downloads: downloads ? value : null,
        ),
      );
    } catch (_) {
      if (mounted) notify(context, 'Качество не сохранилось. Попробуй снова.');
    } finally {
      if (mounted) setState(() => savingQuality = false);
    }
  }

  Future<void> sort() async {
    final app = widget.app, account = widget.app.account?.id;
    final ranked = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in [false, true])
              ListTile(
                title: Text(value ? 'По баллам' : 'Мой порядок'),
                subtitle: Text(
                  value
                      ? 'Самые ценные песни сверху'
                      : 'Порядок, который ты задаёшь стрелками',
                ),
                trailing: app.ranked == value
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheet, value),
              ),
          ],
        ),
      ),
    );
    if (ranked != null && account == app.account?.id) {
      await app.setSort(ranked);
    }
  }

  Future<void> exportBackup() async {
    final account = widget.app.account?.id;
    if (account == null || transferring) return;
    setState(() => transferring = true);
    try {
      final json = await widget.app.store.exportRatings(account);
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Сохранить оценки',
        fileName:
            'zvuk-ratings-${DateTime.now().toIso8601String().substring(0, 10)}.json',
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (mounted && uri != null) notify(context, 'Резервная копия сохранена');
    } catch (_) {
      if (mounted) {
        notify(context, 'Не удалось сохранить файл. Попробуй другое место.');
      }
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  Future<void> importBackup() async {
    final account = widget.app.account?.id;
    if (account == null || transferring) return;
    setState(() => transferring = true);
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Восстановить оценки',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      if ((file.lengthSync() ?? 0) > 20 * 1024 * 1024) {
        throw const FormatException('Файл слишком большой');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Файл слишком большой');
      }
      if (widget.app.account?.id != account) {
        throw const FormatException(
          'Аккаунт изменился. Открой настройки снова.',
        );
      }
      final count = await widget.app.importRatings(utf8.decode(bytes));
      if (mounted) {
        notify(context, 'Копия загружена. Новых оценок: $count.');
      }
    } catch (e) {
      if (mounted) {
        notify(
          context,
          e is FormatException ? e.message : 'Не удалось прочитать файл.',
        );
      }
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.app,
      widget.app.music.revision,
      widget.app.music.downloads,
    ]),
    builder: (context, _) {
      final app = widget.app,
          music = app.music,
          downloads = app.music.downloads;
      final scheme = Theme.of(context).colorScheme;
      final preferences = music.audioPreferences;
      return ListView(
        key: const Key('settings-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/brand/icon.png',
                    width: 48,
                    height: 48,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.account?.name ?? 'Мой аккаунт',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        app.api == null
                            ? 'Сохранённая библиотека'
                            : 'Звук подключён',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SettingsSection(
            title: 'Воспроизведение',
            note: 'Новое качество применяется к следующей песне. Скачанные треки играют из сохранённого файла.',
            children: [
              SettingsRow(
                key: const Key('settings-stream-quality'),
                icon: Icons.graphic_eq_rounded,
                title: 'Качество музыки',
                subtitle: preferences.streaming.label,
                busy: savingQuality,
                onTap: () => quality(downloads: false),
              ),
              SettingsRow(
                key: const Key('settings-repeat'),
                icon: Icons.repeat_rounded,
                title: 'Повтор',
                subtitle: settingsRepeatLabel(music.repeatMode),
                onTap: () => chooseRepeatMode(context, music),
              ),
              SettingsRow(
                key: const Key('settings-sleep'),
                icon: Icons.bedtime_outlined,
                title: 'Таймер сна',
                subtitle: music.sleepTimer.active
                    ? sleepLabel(music)
                    : 'Выключен',
                onTap: () => showSleepTimer(context, music),
              ),
              SettingsRow(
                key: const Key('settings-wave'),
                icon: Icons.waves_rounded,
                title: 'Мой поток',
                subtitle: 'Настроение, жанры и новые песни',
                onTap: () => openWaveSettings(context, app),
              ),
            ],
          ),
          SettingsSection(
            title: 'Скачивания',
            note: 'Качество меняется для новых загрузок. Скачивание использует текущую сеть, в том числе мобильную.',
            children: [
              SettingsRow(
                key: const Key('settings-download-quality'),
                icon: Icons.download_rounded,
                title: 'Качество скачивания',
                subtitle: preferences.downloads.label,
                busy: savingQuality,
                onTap: () => quality(downloads: true),
              ),
              SettingsRow(
                key: const Key('settings-downloads'),
                icon: Icons.folder_outlined,
                title: 'Скачанная музыка',
                subtitle:
                    '${trackCountLabel(downloads.tracks.length)} · ${downloadSize(downloads.storedBytes)}${downloads.pendingCount == 0 ? '' : ' · в очереди: ${downloads.pendingCount}'}',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => DownloadsScreen(app)),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Библиотека и баллы',
            note: 'Каждая песня начинает с 10 баллов. Минус снижает балл и оставляет песню в списке.',
            children: [
              SettingsRow(
                key: const Key('settings-sort'),
                icon: Icons.sort_rounded,
                title: 'Порядок песен',
                subtitle: app.ranked ? 'По баллам' : 'Мой порядок',
                onTap: sort,
              ),
              SettingsRow(
                key: const Key('settings-export'),
                icon: Icons.ios_share_rounded,
                title: 'Сохранить в файл',
                subtitle: 'Резервная копия баллов и порядка',
                busy: transferring,
                onTap: app.account == null ? null : exportBackup,
              ),
              SettingsRow(
                key: const Key('settings-import'),
                icon: Icons.file_open_outlined,
                title: 'Восстановить из файла',
                subtitle: 'Повторные оценки пропускаются',
                busy: transferring,
                onTap: app.account == null ? null : importBackup,
              ),
            ],
          ),
          SettingsSection(
            title: 'Аккаунт',
            children: [
              ExpansionTile(
                key: const Key('settings-token'),
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: const Icon(Icons.key_rounded, size: 22),
                title: const Text(
                  'Заменить токен',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Подключение к твоему аккаунту',
                  style: TextStyle(fontSize: 13),
                ),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  ConnectForm(
                    app,
                    onConnected: () => notify(context, 'Подключение обновлено'),
                  ),
                ],
              ),
            ],
          ),
          SettingsSection(
            title: 'Приложение',
            note: 'Личный неофициальный клиент Звука. Баллы, порядок и скачанная музыка хранятся на этом телефоне.',
            children: [
              const SettingsRow(
                icon: Icons.music_note_rounded,
                title: 'Мой Звук',
                subtitle: 'Версия $appVersion',
              ),
              SettingsRow(
                icon: Icons.translate_rounded,
                title: 'Перевод текста песен',
                subtitle: 'Английский → русский, Google Translate на телефоне',
                onTap: () => showTranslationInfo(context),
              ),
              SettingsRow(
                key: const Key('settings-licenses'),
                icon: Icons.description_outlined,
                title: 'Лицензии компонентов',
                subtitle: 'Открытые библиотеки приложения',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Мой Звук',
                  applicationVersion: appVersion,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
