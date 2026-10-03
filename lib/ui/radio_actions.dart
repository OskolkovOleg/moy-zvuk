import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../data/wave_source.dart';
import '../playback/music_handler.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';

Future<void> openRadioAction(
  BuildContext context,
  AppController app,
  WaveSource source, {
  Track? appendFor,
}) async {
  // Each sheet owns a distinct request, including the const favorites source.
  final requestSource = WaveSource(
    kind: source.kind,
    id: source.id,
    title: source.title,
  );
  final message = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RadioActionSheet(app, requestSource, appendFor),
  );
  if (message != null && context.mounted) notify(context, message);
}

class _RadioActionSheet extends StatefulWidget {
  const _RadioActionSheet(this.app, this.source, this.appendFor);
  final AppController app;
  final WaveSource source;
  final Track? appendFor;
  @override
  State<_RadioActionSheet> createState() => _RadioActionSheetState();
}

class _RadioActionSheetState extends State<_RadioActionSheet> {
  bool busy = true, finished = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) run();
    });
  }

  @override
  void dispose() {
    if (!finished && widget.appendFor == null) {
      unawaited(widget.app.music.cancelWaveStart(widget.source));
    }
    super.dispose();
  }

  Future<void> run() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final music = widget.app.music;
      String message;
      if (widget.appendFor != null) {
        final count = await music.appendSimilar(
          widget.appendFor!,
          cancelled: () => !mounted,
        );
        message = count == 0
            ? 'Новых похожих песен пока нет'
            : 'В очередь добавлено: ${trackCountLabel(count)}';
      } else {
        await music.startWave(source: widget.source);
        if (!mounted) return;
        if (music.error.value != null) {
          throw StateError(music.error.value!);
        }
        if (!music.isWave || !identical(music.waveSource, widget.source)) {
          finished = true;
          Navigator.pop(context);
          return;
        }
        message = widget.source.queueTitle;
      }
      if (mounted) {
        finished = true;
        Navigator.pop(context, message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is StateError ? e.message : catalogError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.appendFor == null
                ? 'Подбираем поток'
                : 'Похожие песни в очередь',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            widget.source.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          if (busy) const LinearProgressIndicator() else Text(error!),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!busy)
                FilledButton.icon(
                  onPressed: run,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Повторить'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(busy ? 'Отмена' : 'Закрыть'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
