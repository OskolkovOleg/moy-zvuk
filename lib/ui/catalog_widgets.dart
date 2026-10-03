import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import 'widgets.dart';
import 'player_sheet.dart';
import 'catalog_detail_screen.dart';

String catalogError(Object e) =>
    e is ZvukException ? e.message : 'Не удалось загрузить. Попробуй ещё раз.';

Future<void> openCatalog(
  BuildContext context,
  AppController app,
  CatalogItem item,
) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => CatalogDetailScreen(app, item)));

class PlayerScaffold extends StatelessWidget {
  const PlayerScaffold(
    this.app, {
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });
  final AppController app;
  final String title;
  final Widget body;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: body),
          MiniPlayer(app),
        ],
      ),
    ),
  );
}

class CatalogTile extends StatelessWidget {
  const CatalogTile(this.item, {super.key, required this.onTap, this.trailing});
  final CatalogItem item;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    leading: Artwork(
      Track(id: item.id, title: item.title, imageUrl: item.imageUrl),
      size: 52,
    ),
    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: item.subtitle.isEmpty
        ? null
        : Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class CatalogFailure extends StatelessWidget {
  const CatalogFailure(this.message, this.retry, {super.key});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Повторить'),
        ),
      ],
    ),
  );
}

/// Keeps validation and network errors inside the still-open form.
Future<String?> playlistNameDialog(
  BuildContext context, {
  String? initial,
  required Future<void> Function(String name) save,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PlaylistNameDialog(initial: initial, save: save),
);

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({this.initial, required this.save});
  final String? initial;
  final Future<void> Function(String) save;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final input = TextEditingController(text: widget.initial);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    final name = input.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Введи название');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(name);
      if (mounted) Navigator.pop(context, name);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = catalogError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.initial == null ? 'Новый плейлист' : 'Название плейлиста',
      ),
      content: TextField(
        controller: input,
        autofocus: true,
        enabled: !busy,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => submit(),
        decoration: InputDecoration(
          labelText: 'Название',
          errorText: error,
          errorMaxLines: 4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Сохраняем…' : 'Сохранить'),
        ),
      ],
    ),
  );
}
