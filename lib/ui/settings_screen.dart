import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'widgets.dart';

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
  Future<void> exportBackup() async {
    setState(() => transferring = true);
    try {
      final json = await widget.app.store.exportRatings(widget.app.account!.id);
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
    animation: widget.app,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Подключение', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          widget.app.account?.name ?? 'Мой аккаунт',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'ID ${widget.app.account?.id ?? ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Заменить токен'),
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
          children: [
            ConnectForm(
              widget.app,
              onConnected: () => notify(context, 'Подключение обновлено'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Порядок и оценки',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Копия содержит порядок списков и оценки. При восстановлении уже настроенный порядок остаётся, а повторные оценки пропускаются.',
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: transferring ? null : exportBackup,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Сохранить в файл'),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: transferring ? null : importBackup,
          icon: const Icon(Icons.file_open_outlined),
          label: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Восстановить из файла'),
          ),
        ),
        if (transferring)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 36),
        Text(
          'Мой Звук · 1.9.0',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Личное неофициальное приложение. Порядок и оценки хранятся на телефоне. Воспроизведение требует интернета и доступа к треку в Звуке.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Мой Звук',
            applicationVersion: '1.9.0',
          ),
          child: const Text('Лицензии компонентов'),
        ),
      ],
    ),
  );
}
