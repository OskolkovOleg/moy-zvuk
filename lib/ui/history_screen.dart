import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/history_store.dart';
import '../data/personal_models.dart';
import '../data/zvuk_api.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen(this.app, {super.key});
  final AppController app;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool remote = false, busy = false;
  List<ListeningEntry> entries = [];
  String? error;
  int? next;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    final app = widget.app, api = widget.app.api, id = widget.app.account?.id;
    if (id == null || (more && busy)) return;
    final current = ++request, source = remote;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final HistoryPage page;
      if (source) {
        if (api == null) {
          throw const ZvukException('Обнови подключение в настройках.');
        }
        page = await api.listeningHistory(offset: more ? next ?? 0 : 0);
      } else {
        page = HistoryPage(await HistoryStore(app.store).recent(id), null);
      }
      if (!mounted ||
          current != request ||
          id != app.account?.id ||
          api != app.api) {
        return;
      }
      setState(() {
        entries = recentUnique([
          ...more ? entries : <ListeningEntry>[],
          ...page.entries,
        ], limit: 5000);
        next = page.nextOffset;
      });
    } catch (e) {
      if (mounted && current == request) {
        setState(() => error = catalogError(e));
      }
    } finally {
      if (mounted && current == request) setState(() => busy = false);
    }
  }

  void select(bool value) {
    if (value == remote) return;
    setState(() {
      remote = value;
      entries = [];
      next = null;
    });
    load();
  }

  @override
  Widget build(BuildContext context) => PlayerScaffold(
    widget.app,
    title: 'История',
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('На устройстве', textAlign: TextAlign.center),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('В Звуке', textAlign: TextAlign.center),
                ),
              ],
              selected: {remote},
              onSelectionChanged: (values) => select(values.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            remote
                ? 'Последние песни из истории Звука. Данные могут появляться с задержкой.'
                : 'Последние 200 песен, включённых в этом приложении.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => load(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: entries.length + 1,
              itemBuilder: (context, index) {
                if (index == entries.length) {
                  return Column(
                    children: [
                      if (error != null)
                        CatalogFailure(
                          error!,
                          () => load(more: entries.isNotEmpty && next != null),
                        ),
                      if (entries.isEmpty && !busy && error == null)
                        const EmptyState(
                          icon: Icons.history_rounded,
                          title: 'История пока пуста',
                          message:
                              'Включи музыку — здесь появятся недавние песни.',
                        ),
                      if (next != null && !busy && error == null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton(
                            onPressed: () => load(more: true),
                            child: const Text('Загрузить ещё'),
                          ),
                        ),
                    ],
                  );
                }
                final entry = entries[index];
                final day = dateLabel(entry.at);
                final header =
                    index == 0 || day != dateLabel(entries[index - 1].at);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (header)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Text(
                          day,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    TrackTile(
                      app: widget.app,
                      track: entry.track,
                      catalog: true,
                      onPlay: () => widget.app.music.playList(
                        entries.map((e) => e.track).toList(),
                        index,
                        title: 'История',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

String dateLabel(DateTime date) {
  final value = date.toLocal(), now = DateTime.now();
  final day = DateTime(value.year, value.month, value.day),
      today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Сегодня';
  if (day == today.subtract(const Duration(days: 1))) return 'Вчера';
  return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}
